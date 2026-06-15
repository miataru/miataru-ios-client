/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateDeliveryCoordinator.swift
 * miataru
 *
 * Created by Codex on 04.03.26.
 */

import Foundation
import MiataruAPIClient
import UIKit

enum LocationUpdateDeliveryError: LocalizedError {
    case serverDidNotAcknowledge

    var errorDescription: String? {
        switch self {
        case .serverDidNotAcknowledge:
            return "Server response was not successful"
        }
    }
}

actor LocationUpdateDeliveryCoordinator {
    enum SubmitResult {
        case sent
        case queued
        case failed(Error)
    }

    typealias UpdateSender = (URL, UpdateLocationPayload, Bool, Int) async throws -> Bool
    typealias VisitorProcessor = (URL, TimeInterval?, Bool) async -> Void
    typealias FlushObserver = (LocationUpdateOutboxItem, String, Date) async -> Void

    private struct FlushResult {
        let didReachBatchLimit: Bool
        let stoppedOnRetryableError: Bool
        let hasPendingItems: Bool
    }

    static let shared = LocationUpdateDeliveryCoordinator(
        outboxStore: LocationUpdateOutboxStore(
            maxItems: SettingsManager.shared.locationUpdateOutboxMaxItems,
            ttl: SettingsManager.shared.locationUpdateOutboxRetentionTimeToLive
        )
    )

    private let outboxStore: LocationUpdateOutboxStore
    private let updateSender: UpdateSender
    private let flushBatchSize: Int
    private let flushInterval: TimeInterval
    private let deferredFlushDelay: TimeInterval
    private let visitorProcessor: VisitorProcessor
    private let flushObserver: FlushObserver

    private var periodicFlushTask: Task<Void, Never>?
    private var deferredFlushTask: Task<Void, Never>?
    private var deferredFlushDate: Date?
    private var isFlushing = false

    init(
        outboxStore: LocationUpdateOutboxStore = LocationUpdateOutboxStore(),
        flushBatchSize: Int = 25,
        flushInterval: TimeInterval = 60,
        deferredFlushDelay: TimeInterval = 1,
        updateSender: UpdateSender? = nil,
        visitorProcessor: VisitorProcessor? = nil,
        flushObserver: FlushObserver? = nil
    ) {
        self.outboxStore = outboxStore
        self.flushBatchSize = max(1, flushBatchSize)
        self.flushInterval = max(1, flushInterval)
        self.deferredFlushDelay = max(0.05, deferredFlushDelay)
        self.updateSender = updateSender ?? { serverURL, payload, enableHistory, retentionTime in
            APIRequestCounter.shared.record(.updateLocation)
            return try await MiataruAppAPI.updateLocation(
                serverURL: serverURL,
                locationData: payload,
                enableHistory: enableHistory,
                retentionTime: retentionTime,
                retryPolicy: .updateLocation
            )
        }
        self.visitorProcessor = visitorProcessor ?? { serverURL, minimumInterval, processKnownVisitorAlerts in
            let processKnownVisitorAlertsNow = await MainActor.run {
                processKnownVisitorAlerts && UIApplication.shared.applicationState != .active
            }
            await UnknownVisitorAlertService.shared.processAfterSuccessfulLocationUpdate(
                serverURL: serverURL,
                minimumInterval: minimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlertsNow
            )
        }
        self.flushObserver = flushObserver ?? { item, trigger, flushedAt in
            Self.recordFlushedLocationUpdateDiagnostics(item: item, trigger: trigger, flushedAt: flushedAt)
        }
    }

    static func recordFlushedLocationUpdateDiagnostics(
        item: LocationUpdateOutboxItem,
        trigger: String,
        flushedAt: Date,
        diagnosticsLog: LocationDiagnosticsLogStore = .shared
    ) {
        diagnosticsLog.appendCoalesced(
            level: .info,
            event: "locationUpload",
            summary: "Queued location update sent to server.",
            result: "flushed",
            reason: "outbox flush",
            coalescingKey: "locationUpload|flushed",
            context: [
                "trigger": .string(trigger),
                "locationTimestamp": .string(item.payload.Timestamp),
                "enqueuedAt": .string(ISO8601DateFormatter().string(from: item.enqueuedAt)),
                "flushedAt": .string(ISO8601DateFormatter().string(from: flushedAt)),
                "attemptCount": .integer(item.attemptCount),
                "serverURL": .string(item.serverURLString),
                "enableHistory": .bool(item.enableHistory),
                "retentionTime": .integer(item.retentionTime)
            ],
            timestamp: flushedAt,
            sampleEvery: 100
        )
    }

    func start() {
        guard periodicFlushTask == nil else { return }
        periodicFlushTask = Task { [flushInterval] in
            while !Task.isCancelled {
                let sleepNanoseconds = UInt64(flushInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: sleepNanoseconds)
                let pendingCount = await self.outboxStore.count()
                guard pendingCount > 0 else { continue }
                _ = await self.flushOutbox(trigger: "timer")
            }
        }
    }

    func stopPeriodicFlushTaskForTesting() {
        periodicFlushTask?.cancel()
        periodicFlushTask = nil
        deferredFlushTask?.cancel()
        deferredFlushTask = nil
        deferredFlushDate = nil
    }

    func submit(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        deliveryDelay: TimeInterval? = nil,
        visitorCheckMinimumInterval: TimeInterval? = nil,
        processKnownVisitorAlerts: Bool = false
    ) async -> SubmitResult {
        if let deliveryDelay, deliveryDelay > 0 {
            let now = Date()
            let availableAfter = await outboxStore.activeDelayedBatchReleaseDate(now: now)
                ?? now.addingTimeInterval(deliveryDelay)
            await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: enableHistory,
                retentionTime: retentionTime,
                availableAfter: availableAfter,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            )
            await notifyOutboxDidChange()
            await scheduleNextFlushIfNeeded(now: now, trigger: "delayedSubmit")
            return .queued
        }

        if !(await outboxStore.isEmpty()) {
            await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: enableHistory,
                retentionTime: retentionTime,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            )
            await notifyOutboxDidChange()
            scheduleFlushSoon(trigger: "submitWithPendingOutbox")
            return .queued
        }

        do {
            let success = try await updateSender(serverURL, payload, enableHistory, retentionTime)
            return success ? .sent : .failed(LocationUpdateDeliveryError.serverDidNotAcknowledge)
        } catch {
            guard MiataruRetryClassifier.isRetryable(error) else {
                return .failed(error)
            }
            await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: enableHistory,
                retentionTime: retentionTime,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            )
            await notifyOutboxDidChange()
            return .queued
        }
    }

    func appDidBecomeActive() async {
        _ = await flushOutbox(trigger: "appDidBecomeActive")
    }

    func networkBecameAvailable() async {
        _ = await flushOutbox(trigger: "networkBecameAvailable")
    }

    func flushOutboxNow() async {
        cancelDeferredFlush()
        _ = await flushOutbox(trigger: "manual")
    }

    func flushOutboxCompletelyNow() async {
        cancelDeferredFlush()
        while true {
            let result = await flushOutbox(trigger: "manualFull", scheduleContinuation: false, includeDelayedItems: true)
            guard result.didReachBatchLimit,
                  !result.stoppedOnRetryableError,
                  result.hasPendingItems else {
                break
            }
        }
    }

    func pendingOutboxCount() async -> Int {
        await outboxStore.count()
    }

    func updateOutboxPolicy(maxItems: Int, ttl: TimeInterval?) async {
        await outboxStore.updatePolicy(maxItems: maxItems, ttl: ttl)
        await notifyOutboxDidChange()
    }

    func sendPendingOutbox(to serverURL: URL) async {
        guard await outboxStore.count() > 0 else { return }
        let didRetarget = await outboxStore.updateServerURLForPendingItems(serverURL)
        if didRetarget {
            await notifyOutboxDidChange()
        }
        cancelDeferredFlush()
        await flushOutboxCompletely(trigger: "serverURLChanged")
    }

    func discardPendingOutbox() async {
        cancelDeferredFlush()
        await outboxStore.removeAll()
        await notifyOutboxDidChange()
    }

    private func flushOutboxCompletely(trigger: String) async {
        cancelDeferredFlush()
        while true {
            let result = await flushOutbox(trigger: trigger, scheduleContinuation: false, includeDelayedItems: true)
            guard result.didReachBatchLimit,
                  !result.stoppedOnRetryableError,
                  result.hasPendingItems else {
                break
            }
        }
    }

    private func flushOutbox(trigger: String,
                             scheduleContinuation: Bool = true,
                             includeDelayedItems: Bool = false) async -> FlushResult {
        guard !isFlushing else {
            scheduleFlushSoon(trigger: "\(trigger):coalesced")
            return FlushResult(
                didReachBatchLimit: false,
                stoppedOnRetryableError: true,
                hasPendingItems: await outboxStore.count() > 0
            )
        }
        isFlushing = true
        var shouldContinueAfterBatch = false
        defer {
            isFlushing = false
            if scheduleContinuation && shouldContinueAfterBatch {
                scheduleFlushSoon(trigger: "\(trigger):continuation")
            }
        }

        await outboxStore.pruneExpiredEntries()

        var processedCount = 0
        var stoppedOnRetryableError = false
        while processedCount < flushBatchSize {
            guard let head = await outboxStore.peekHead() else { break }
            if !includeDelayedItems,
               let availableAfter = head.availableAfter,
               availableAfter > Date() {
                scheduleFlush(at: availableAfter, trigger: "\(trigger):delayedHead")
                break
            }
            guard let serverURL = URL(string: head.serverURLString) else {
                debugLog("[LocationUpdateDeliveryCoordinator] Dropping outbox item with invalid URL: \(head.serverURLString)")
                guard await outboxStore.removeHead(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed while dropping invalid URL item")
                    break
                }
                await notifyOutboxDidChange()
                processedCount += 1
                continue
            }

            do {
                let success = try await updateSender(serverURL, head.payload, head.enableHistory, head.retentionTime)
                if success {
                    guard await outboxStore.removeHead(matching: head) else {
                        debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed during send; keeping current queue state")
                        break
                    }
                    await notifyOutboxDidChange()
                    processedCount += 1
                    await notifyOwnLocationUpdateDidSend()
                    await flushObserver(head, trigger, Date())
                    Task {
                        await visitorProcessor(
                            serverURL,
                            head.visitorCheckMinimumInterval,
                            head.processKnownVisitorAlerts
                        )
                    }
                    continue
                }

                debugLog("[LocationUpdateDeliveryCoordinator] Dropping outbox item because server did not ACK")
                guard await outboxStore.removeHead(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed while dropping non-ACK item")
                    break
                }
                await notifyOutboxDidChange()
                processedCount += 1
            } catch {
                if MiataruRetryClassifier.isRetryable(error) {
                    guard await outboxStore.incrementHeadAttemptCount(matching: head) else {
                        debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed during retryable error; keeping current queue state")
                        break
                    }
                    debugLog("[LocationUpdateDeliveryCoordinator] Flush stopped (transient head error, trigger=\(trigger)): \(error)")
                    stoppedOnRetryableError = true
                    break
                }

                debugLog("[LocationUpdateDeliveryCoordinator] Dropping non-retryable outbox item error: \(error)")
                guard await outboxStore.removeHead(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed while dropping non-retryable item")
                    break
                }
                await notifyOutboxDidChange()
                processedCount += 1
            }
        }

        if processedCount >= flushBatchSize,
           !stoppedOnRetryableError,
           !(await outboxStore.isEmpty()) {
            shouldContinueAfterBatch = true
        }

        return FlushResult(
            didReachBatchLimit: processedCount >= flushBatchSize,
            stoppedOnRetryableError: stoppedOnRetryableError,
            hasPendingItems: shouldContinueAfterBatch
        )
    }

    private func scheduleFlushSoon(trigger: String) {
        scheduleFlush(after: deferredFlushDelay, trigger: trigger)
    }

    private func scheduleNextFlushIfNeeded(now: Date, trigger: String) async {
        guard let nextFlushDate = await outboxStore.nextFlushDate(now: now) else { return }
        scheduleFlush(for: nextFlushDate, now: now, trigger: trigger)
    }

    private func scheduleFlush(for date: Date, now: Date = Date(), trigger: String) {
        let delay = max(deferredFlushDelay, date.timeIntervalSince(now))
        scheduleFlush(after: delay, trigger: trigger)
    }

    private func scheduleFlush(at date: Date, trigger: String) {
        scheduleFlush(for: date, trigger: trigger)
    }

    private func scheduleFlush(after delay: TimeInterval, trigger: String) {
        let normalizedDelay = max(0.05, delay)
        let scheduledDate = Date().addingTimeInterval(normalizedDelay)
        if let deferredFlushDate, deferredFlushDate <= scheduledDate {
            return
        }

        deferredFlushTask?.cancel()
        let sleepNanoseconds = UInt64(normalizedDelay * 1_000_000_000)
        deferredFlushDate = scheduledDate
        deferredFlushTask = Task {
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            guard !Task.isCancelled else { return }
            await self.runDeferredFlush(trigger: trigger)
        }
    }

    private func runDeferredFlush(trigger: String) async {
        deferredFlushTask = nil
        deferredFlushDate = nil
        _ = await flushOutbox(trigger: trigger)
    }

    private func cancelDeferredFlush() {
        deferredFlushTask?.cancel()
        deferredFlushTask = nil
        deferredFlushDate = nil
    }

    private func notifyOutboxDidChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .locationUpdateOutboxDidChange, object: nil)
        }
    }

    private func notifyOwnLocationUpdateDidSend() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .didSendOwnLocationUpdate, object: nil)
        }
    }
}

extension Notification.Name {
    static let locationUpdateOutboxDidChange = Notification.Name("locationUpdateOutboxDidChange")
}
