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

    static let shared = LocationUpdateDeliveryCoordinator()

    private let outboxStore: LocationUpdateOutboxStore
    private let updateSender: UpdateSender
    private let flushBatchSize: Int
    private let flushInterval: TimeInterval

    private var periodicFlushTask: Task<Void, Never>?
    private var isFlushing = false

    init(
        outboxStore: LocationUpdateOutboxStore = LocationUpdateOutboxStore(),
        flushBatchSize: Int = 25,
        flushInterval: TimeInterval = 60,
        updateSender: UpdateSender? = nil
    ) {
        self.outboxStore = outboxStore
        self.flushBatchSize = max(1, flushBatchSize)
        self.flushInterval = max(1, flushInterval)
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
                await self.flushOutbox(trigger: "timer")
            }
        }
    }

    func stopPeriodicFlushTaskForTesting() {
        periodicFlushTask?.cancel()
        periodicFlushTask = nil
    }

    func submit(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int
    ) async -> SubmitResult {
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
            return .queued
        }
    }

    func appDidBecomeActive() async {
        await flushOutbox(trigger: "appDidBecomeActive")
    }

    func networkBecameAvailable() async {
        await flushOutbox(trigger: "networkBecameAvailable")
    }

    func flushOutboxNow() async {
        await flushOutbox(trigger: "manual")
    }

    func pendingOutboxCount() async -> Int {
        await outboxStore.count()
    }

    private func flushOutbox(trigger: String) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        await outboxStore.pruneExpiredEntries()

        var processedCount = 0
        while processedCount < flushBatchSize {
            guard let head = await outboxStore.peekHead() else { break }
            guard let serverURL = URL(string: head.serverURLString) else {
                debugLog("[LocationUpdateDeliveryCoordinator] Dropping outbox item with invalid URL: \(head.serverURLString)")
                await outboxStore.removeHead()
                processedCount += 1
                continue
            }

            do {
                let success = try await updateSender(serverURL, head.payload, head.enableHistory, head.retentionTime)
                if success {
                    await outboxStore.removeHead()
                    processedCount += 1
                    Task {
                        await UnknownVisitorAlertService.shared.processAfterSuccessfulLocationUpdate(serverURL: serverURL)
                    }
                    continue
                }

                debugLog("[LocationUpdateDeliveryCoordinator] Dropping outbox item because server did not ACK")
                await outboxStore.removeHead()
                processedCount += 1
            } catch {
                if MiataruRetryClassifier.isRetryable(error) {
                    await outboxStore.incrementHeadAttemptCount()
                    debugLog("[LocationUpdateDeliveryCoordinator] Flush stopped (transient head error, trigger=\(trigger)): \(error)")
                    break
                }

                debugLog("[LocationUpdateDeliveryCoordinator] Dropping non-retryable outbox item error: \(error)")
                await outboxStore.removeHead()
                processedCount += 1
            }
        }
    }
}
