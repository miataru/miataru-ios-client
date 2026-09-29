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

enum LocationUpdateDeliveryError: LocalizedError, Equatable {
    case serverDidNotAcknowledge
    case outboxUnavailable

    var errorDescription: String? {
        switch self {
        case .serverDidNotAcknowledge:
            return "Server response was not successful"
        case .outboxUnavailable:
            return NSLocalizedString(
                "location_update_outbox_unavailable_error",
                tableName: "LocationTracking",
                comment: "Error shown when a location update cannot be durably saved because the local outbox is unavailable"
            )
        }
    }
}

actor LocationUpdateDeliveryCoordinator {
    enum SubmitResult {
        case sent
        case queued
        case dropped
        case failed(Error)
    }

    typealias UpdateSender = (URL, UpdateLocationPayload, Bool, Int) async throws -> Bool
    typealias VisitorProcessor = (URL, TimeInterval?, Bool) async -> Void
    typealias FlushObserver = (LocationUpdateOutboxItem, String, Date) async -> Void
    typealias FlushEligibilityProvider = () async -> Bool
    typealias HistoryEnabledProvider = () async -> Bool

    private struct FlushResult {
        let didReachBatchLimit: Bool
        let stoppedOnDeliveryFailure: Bool
        let hasPendingItems: Bool
    }

    private struct InFlightDirectSend {
        let id: UUID
        var queuedRecord: LocationUpdateOutboxItem?
        let serverURL: URL
        var replayServerURL: URL?
        var discarded = false
    }

    static let shared = LocationUpdateDeliveryCoordinator(
        outboxStore: LocationUpdateOutboxStore(
            maxItems: SettingsManager.shared.locationUpdateOutboxMaxItems,
            ttl: SettingsManager.shared.locationUpdateOutboxRetentionTimeToLive
        ),
        flushEligibilityProvider: {
            await MainActor.run { !SettingsManager.shared.isTrackingPaused }
        },
        historyEnabledProvider: {
            await MainActor.run { SettingsManager.shared.saveLocationHistoryOnServer }
        }
    )

    private let outboxStore: LocationUpdateOutboxStore
    private let updateSender: UpdateSender
    private let flushBatchSize: Int
    private let flushInterval: TimeInterval
    private let deferredFlushDelay: TimeInterval
    private let visitorProcessor: VisitorProcessor
    private let flushObserver: FlushObserver
    private let flushEligibilityProvider: FlushEligibilityProvider
    private let historyEnabledProvider: HistoryEnabledProvider?

    private var periodicFlushTask: Task<Void, Never>?
    private var deferredFlushTask: Task<Void, Never>?
    private var deferredFlushDate: Date?
    private var isFlushing = false
    private var inFlightDirectSend: InFlightDirectSend?
    private var isFinishingDirectSend = false

    private var isDirectSendBlockingQueue: Bool {
        inFlightDirectSend != nil || isFinishingDirectSend
    }

    init(
        outboxStore: LocationUpdateOutboxStore = LocationUpdateOutboxStore(),
        flushBatchSize: Int = 25,
        flushInterval: TimeInterval = 60,
        deferredFlushDelay: TimeInterval = 1,
        updateSender: UpdateSender? = nil,
        visitorProcessor: VisitorProcessor? = nil,
        flushObserver: FlushObserver? = nil,
        flushEligibilityProvider: FlushEligibilityProvider? = nil,
        historyEnabledProvider: HistoryEnabledProvider? = nil
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
        self.flushEligibilityProvider = flushEligibilityProvider ?? { true }
        self.historyEnabledProvider = historyEnabledProvider
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

    func start() async {
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
        if await outboxStore.count() > 0 {
            _ = await flushOutbox(trigger: "launch")
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
        guard await flushEligibilityProvider() else {
            return .dropped
        }
        guard await outboxStore.isStorageAvailable() else {
            return .failed(LocationUpdateDeliveryError.outboxUnavailable)
        }
        let effectiveEnableHistory = await effectiveHistoryEnabled(fallback: enableHistory)

        if let deliveryDelay, deliveryDelay > 0 {
            let now = Date()
            let availableAfter = await outboxStore.activeDelayedBatchReleaseDate(now: now)
                ?? now.addingTimeInterval(deliveryDelay)
            guard await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: effectiveEnableHistory,
                retentionTime: retentionTime,
                availableAfter: availableAfter,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            ) else { return .failed(LocationUpdateDeliveryError.outboxUnavailable) }
            await notifyOutboxDidChange()
            await scheduleNextFlushIfNeeded(now: now, trigger: "delayedSubmit")
            return .queued
        }

        if isDirectSendBlockingQueue {
            guard await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: effectiveEnableHistory,
                retentionTime: retentionTime,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            ) else { return .failed(LocationUpdateDeliveryError.outboxUnavailable) }
            await notifyOutboxDidChange()
            scheduleFlushSoon(trigger: "submitWithInFlightDirectSend")
            return .queued
        }

        let hasPendingOutbox = !(await outboxStore.isEmpty())
        if isDirectSendBlockingQueue {
            guard await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: effectiveEnableHistory,
                retentionTime: retentionTime,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            ) else { return .failed(LocationUpdateDeliveryError.outboxUnavailable) }
            await notifyOutboxDidChange()
            scheduleFlushSoon(trigger: "submitWithInFlightDirectSend")
            return .queued
        }

        if hasPendingOutbox {
            guard await outboxStore.enqueue(
                serverURL: serverURL,
                payload: payload,
                enableHistory: effectiveEnableHistory,
                retentionTime: retentionTime,
                visitorCheckMinimumInterval: visitorCheckMinimumInterval,
                processKnownVisitorAlerts: processKnownVisitorAlerts
            ) else { return .failed(LocationUpdateDeliveryError.outboxUnavailable) }
            await notifyOutboxDidChange()
            scheduleFlushSoon(trigger: "submitWithPendingOutbox")
            return .queued
        }

        // Persist the head before starting the network request. A background process may be
        // terminated while the request is suspended; the next launch can then replay it.
        let directSendID = UUID()
        inFlightDirectSend = InFlightDirectSend(
            id: directSendID,
            queuedRecord: nil,
            serverURL: serverURL
        )
        guard await outboxStore.enqueueAtFront(
            serverURL: serverURL,
            payload: payload,
            enableHistory: effectiveEnableHistory,
            retentionTime: retentionTime,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval,
            processKnownVisitorAlerts: processKnownVisitorAlerts
        ) else {
            inFlightDirectSend = nil
            return .failed(LocationUpdateDeliveryError.outboxUnavailable)
        }
        if inFlightDirectSend?.discarded == true {
            await outboxStore.removeAll()
            inFlightDirectSend = nil
            return .dropped
        }
        if let replayServerURL = inFlightDirectSend?.replayServerURL {
            _ = await outboxStore.updateServerURLForPendingItems(replayServerURL)
        }
        guard let queuedRecord = await outboxStore.peekHead() else {
            inFlightDirectSend = nil
            return .failed(LocationUpdateDeliveryError.serverDidNotAcknowledge)
        }
        if inFlightDirectSend?.discarded == true {
            inFlightDirectSend = nil
            return .dropped
        }
        inFlightDirectSend?.queuedRecord = queuedRecord
        await notifyOutboxDidChange()
        if inFlightDirectSend?.discarded == true {
            inFlightDirectSend = nil
            return .dropped
        }

        do {
            let success = try await updateSender(serverURL, payload, effectiveEnableHistory, retentionTime)
            return await finishInFlightDirectSend(
                id: directSendID,
                result: success ? .sent : .failed(LocationUpdateDeliveryError.serverDidNotAcknowledge)
            )
        } catch {
            let result: SubmitResult = MiataruRetryClassifier.isRetryable(error) ? .queued : .failed(error)
            return await finishInFlightDirectSend(id: directSendID, result: result)
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
                  !result.stoppedOnDeliveryFailure,
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
        let pendingCount = await outboxStore.count()
        let didMarkInFlightReplay = markInFlightDirectSendForReplay(to: serverURL)
        guard pendingCount > 0 || didMarkInFlightReplay else { return }

        let didRetarget = pendingCount > 0
            ? await outboxStore.updateServerURLForPendingItems(serverURL)
            : false
        if didRetarget || didMarkInFlightReplay {
            await notifyOutboxDidChange()
        }
        cancelDeferredFlush()
        await flushOutboxCompletely(trigger: "serverURLChanged")
    }

    func discardPendingOutbox() async {
        cancelDeferredFlush()
        inFlightDirectSend?.replayServerURL = nil
        inFlightDirectSend?.discarded = true
        await outboxStore.removeAll()
        await notifyOutboxDidChange()
    }

    private func flushOutboxCompletely(trigger: String) async {
        cancelDeferredFlush()
        while true {
            let result = await flushOutbox(trigger: trigger, scheduleContinuation: false, includeDelayedItems: true)
            guard result.didReachBatchLimit,
                  !result.stoppedOnDeliveryFailure,
                  result.hasPendingItems else {
                break
            }
        }
    }

    private func finishInFlightDirectSend(id: UUID, result: SubmitResult) async -> SubmitResult {
        guard let completedSend = inFlightDirectSend,
              completedSend.id == id,
              let queuedRecord = completedSend.queuedRecord else {
            return result
        }

        isFinishingDirectSend = true
        inFlightDirectSend = nil
        let shouldRemoveQueuedRecord: Bool
        if completedSend.discarded {
            shouldRemoveQueuedRecord = false
        } else if completedSend.replayServerURL != nil {
            shouldRemoveQueuedRecord = false
        } else if case .sent = result {
            shouldRemoveQueuedRecord = true
        } else if case .dropped = result {
            shouldRemoveQueuedRecord = true
        } else {
            shouldRemoveQueuedRecord = false
        }
        if shouldRemoveQueuedRecord,
           await outboxStore.removeHead(matching: queuedRecord) {
            await notifyOutboxDidChange()
        }

        if case .sent = result {
            await notifyOwnLocationUpdateDidSend()
        }

        if await outboxStore.count() > 0 {
            scheduleFlushSoon(trigger: "directSendCompleted")
        }
        isFinishingDirectSend = false

        if completedSend.discarded {
            if case .sent = result { return .sent }
            return .dropped
        }
        if completedSend.replayServerURL != nil,
           case .failed = result {
            return .queued
        }
        return result
    }

    private func markInFlightDirectSendForReplay(to serverURL: URL) -> Bool {
        guard var directSend = inFlightDirectSend else { return false }

        let previousReplayURLString = directSend.replayServerURL?.absoluteString
        let nextReplayURL = directSend.serverURL.absoluteString == serverURL.absoluteString ? nil : serverURL
        guard previousReplayURLString != nextReplayURL?.absoluteString else {
            return false
        }

        directSend.replayServerURL = nextReplayURL
        inFlightDirectSend = directSend
        return true
    }

    private func flushOutbox(trigger: String,
                             scheduleContinuation: Bool = true,
                             includeDelayedItems: Bool = false) async -> FlushResult {
        if isDirectSendBlockingQueue {
            let pendingCount = await outboxStore.count()
            if pendingCount > 0 {
                scheduleFlushSoon(trigger: "\(trigger):directInFlight")
            }
            return FlushResult(
                didReachBatchLimit: false,
                stoppedOnDeliveryFailure: true,
                hasPendingItems: pendingCount > 0
            )
        }

        guard !isFlushing else {
            scheduleFlushSoon(trigger: "\(trigger):coalesced")
            return FlushResult(
                didReachBatchLimit: false,
                stoppedOnDeliveryFailure: true,
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

        guard await flushEligibilityProvider() else {
            cancelDeferredFlush()
            return FlushResult(
                didReachBatchLimit: false,
                stoppedOnDeliveryFailure: false,
                hasPendingItems: await outboxStore.count() > 0
            )
        }

        guard await outboxStore.isStorageAvailable() else {
            return FlushResult(
                didReachBatchLimit: false,
                stoppedOnDeliveryFailure: true,
                hasPendingItems: false
            )
        }

        await outboxStore.pruneExpiredEntries()

        var processedCount = 0
        var stoppedOnDeliveryFailure = false
        while processedCount < flushBatchSize {
            guard let head = await outboxStore.peekHead() else { break }
            if !includeDelayedItems,
               let availableAfter = head.availableAfter,
               availableAfter > Date() {
                scheduleFlush(at: availableAfter, trigger: "\(trigger):delayedHead")
                break
            }
            guard let serverURL = URL(string: head.serverURLString) else {
                guard await outboxStore.incrementHeadAttemptCount(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed while retaining invalid URL item")
                    break
                }
                debugLog("[LocationUpdateDeliveryCoordinator] Flush stopped and retained outbox item with invalid URL: \(head.serverURLString)")
                stoppedOnDeliveryFailure = true
                break
            }

            do {
                let effectiveEnableHistory = await effectiveHistoryEnabled(fallback: head.enableHistory)
                let success = try await updateSender(serverURL, head.payload, effectiveEnableHistory, head.retentionTime)
                if success {
                    guard await outboxStore.removeHead(matching: head) else {
                        debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed during send; keeping current queue state")
                        break
                    }
                    await notifyOutboxDidChange()
                    processedCount += 1
                    await notifyOwnLocationUpdateDidSend()
                    var deliveredItem = head
                    deliveredItem.enableHistory = effectiveEnableHistory
                    await flushObserver(deliveredItem, trigger, Date())
                    Task {
                        await visitorProcessor(
                            serverURL,
                            head.visitorCheckMinimumInterval,
                            head.processKnownVisitorAlerts
                        )
                    }
                    continue
                }

                guard await outboxStore.incrementHeadAttemptCount(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed while retaining non-ACK item")
                    break
                }
                debugLog("[LocationUpdateDeliveryCoordinator] Flush stopped because server did not ACK; retained outbox item")
                stoppedOnDeliveryFailure = true
                break
            } catch {
                guard await outboxStore.incrementHeadAttemptCount(matching: head) else {
                    debugLog("[LocationUpdateDeliveryCoordinator] Outbox head changed during delivery error; keeping current queue state")
                    break
                }
                debugLog("[LocationUpdateDeliveryCoordinator] Flush stopped and retained outbox item after delivery error (trigger=\(trigger)): \(error)")
                stoppedOnDeliveryFailure = true
                break
            }
        }

        if processedCount >= flushBatchSize,
           !stoppedOnDeliveryFailure,
           !(await outboxStore.isEmpty()) {
            shouldContinueAfterBatch = true
        }

        return FlushResult(
            didReachBatchLimit: processedCount >= flushBatchSize,
            stoppedOnDeliveryFailure: stoppedOnDeliveryFailure,
            hasPendingItems: shouldContinueAfterBatch
        )
    }

    private func effectiveHistoryEnabled(fallback: Bool) async -> Bool {
        // History is a current server-side preference, not immutable event metadata. In
        // particular, replaying a stale false value would erase history created since enqueue.
        guard let historyEnabledProvider else { return fallback }
        return await historyEnabledProvider()
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
