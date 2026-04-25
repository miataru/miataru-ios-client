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

    private var periodicFlushTask: Task<Void, Never>?
    private var deferredFlushTask: Task<Void, Never>?
    private var isFlushing = false

    init(
        outboxStore: LocationUpdateOutboxStore = LocationUpdateOutboxStore(),
        flushBatchSize: Int = 25,
        flushInterval: TimeInterval = 60,
        deferredFlushDelay: TimeInterval = 1,
        updateSender: UpdateSender? = nil
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
    }

    func submit(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int
    ) async -> SubmitResult {
        if !(await outboxStore.isEmpty()) {
            await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: enableHistory,
                retentionTime: retentionTime
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
                retentionTime: retentionTime
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
            let result = await flushOutbox(trigger: "manualFull", scheduleContinuation: false)
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
            let result = await flushOutbox(trigger: trigger, scheduleContinuation: false)
            guard result.didReachBatchLimit,
                  !result.stoppedOnRetryableError,
                  result.hasPendingItems else {
                break
            }
        }
    }

    private func flushOutbox(trigger: String, scheduleContinuation: Bool = true) async -> FlushResult {
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
                    Task {
                        await UnknownVisitorAlertService.shared.processAfterSuccessfulLocationUpdate(serverURL: serverURL)
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
        guard deferredFlushTask == nil else { return }
        let sleepNanoseconds = UInt64(deferredFlushDelay * 1_000_000_000)
        deferredFlushTask = Task {
            try? await Task.sleep(nanoseconds: sleepNanoseconds)
            guard !Task.isCancelled else { return }
            await self.runDeferredFlush(trigger: trigger)
        }
    }

    private func runDeferredFlush(trigger: String) async {
        deferredFlushTask = nil
        _ = await flushOutbox(trigger: trigger)
    }

    private func cancelDeferredFlush() {
        deferredFlushTask?.cancel()
        deferredFlushTask = nil
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
