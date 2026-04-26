/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateDeliveryCoordinatorTests.swift
 * miataruTests
 *
 * Created by Codex on 04.03.26.
 */

import Testing
import Foundation
import MiataruAPIClient
@testable import miataru

struct LocationUpdateDeliveryCoordinatorTests {
    @Test("Submit queues update after transient failure")
    func submitQueuesAfterTransientFailure() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.requestFailed(URLError(.timedOut)))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "1"),
            enableHistory: true,
            retentionTime: 60
        )

        switch result {
        case .queued:
            break
        default:
            Issue.record("Expected queued result")
        }

        let pendingCount = await coordinator.pendingOutboxCount()
        #expect(pendingCount == 1)
        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.first?.payload.Timestamp == "1")
        #expect(snapshot.first?.enableHistory == true)
        #expect(snapshot.first?.retentionTime == 60)
        #expect(await sender.callCount == 1)
    }

    @Test("Submit appends behind pending outbox instead of bypassing order")
    func submitAppendsBehindPendingOutbox() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "old"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .success(true),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "new"),
            enableHistory: false,
            retentionTime: 90
        )

        switch result {
        case .queued:
            break
        default:
            Issue.record("Expected queued result when older outbox entries exist")
        }

        var snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["old", "new"])
        #expect(snapshot[1].enableHistory == false)
        #expect(snapshot[1].retentionTime == 90)
        #expect(await sender.callCount == 0)

        await coordinator.flushOutboxNow()

        snapshot = await store.itemsSnapshot()
        #expect(snapshot.isEmpty)
        #expect(await sender.sentTimestamps == ["old", "new"])
    }

    @Test("Submit with pending outbox schedules deferred drain")
    func submitWithPendingOutboxSchedulesDeferredDrain() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "old"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .success(true),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.05,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "new"),
            enableHistory: false,
            retentionTime: 90
        )

        switch result {
        case .queued:
            break
        default:
            Issue.record("Expected queued result when older outbox entries exist")
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(await store.count() == 0)
        #expect(await sender.sentTimestamps == ["old", "new"])
        await coordinator.stopPeriodicFlushTaskForTesting()
    }

    @Test("Delayed submit batches updates until the selected delivery window")
    func delayedSubmitBatchesUpdatesUntilDeliveryWindow() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .success(true),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.05,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let firstResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "1"),
            enableHistory: true,
            retentionTime: 60,
            deliveryDelay: 0.1
        )
        let secondResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "2"),
            enableHistory: true,
            retentionTime: 60,
            deliveryDelay: 0.1
        )

        if case .queued = firstResult {
        } else {
            Issue.record("Expected first delayed update to be queued")
        }
        if case .queued = secondResult {
        } else {
            Issue.record("Expected second delayed update to be queued")
        }

        var snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["1", "2"])
        #expect(snapshot[0].availableAfter == snapshot[1].availableAfter)
        #expect(await sender.callCount == 0)

        try await Task.sleep(nanoseconds: 300_000_000)

        snapshot = await store.itemsSnapshot()
        #expect(snapshot.isEmpty)
        #expect(await sender.sentTimestamps == ["1", "2"])
        await coordinator.stopPeriodicFlushTaskForTesting()
    }

    @Test("Manual full flush drains more than one batch")
    func manualFullFlushDrainsMoreThanOneBatch() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "1"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "2"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "3"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .success(true),
            .success(true),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 2,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        await coordinator.flushOutboxCompletelyNow()

        #expect(await store.count() == 0)
        #expect(await sender.sentTimestamps == ["1", "2", "3"])
    }

    @Test("Flush stops on transient head error and keeps queue order")
    func flushStopsOnTransientHeadError() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "head"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "tail"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.requestFailed(URLError(.networkConnectionLost)))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        await coordinator.flushOutboxNow()

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot[0].payload.Timestamp == "head")
        #expect(snapshot[0].attemptCount == 1)
        #expect(snapshot[1].payload.Timestamp == "tail")
        #expect(snapshot[1].attemptCount == 0)
        #expect(await sender.callCount == 1)
    }

    @Test("Flush drops non-retryable head and continues with next item")
    func flushDropsNonRetryableAndContinues() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "first"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "second"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.serverError(statusCode: 403, message: "forbidden")),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        await coordinator.flushOutboxNow()

        #expect(await store.count() == 0)
        #expect(await sender.callCount == 2)
    }

    @Test("Submit returns failed for non-retryable error without queueing")
    func submitFailsWithoutQueueingOnNonRetryableError() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.serverError(statusCode: 401, message: "unauthorized"))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "1"),
            enableHistory: true,
            retentionTime: 60
        )

        switch result {
        case .failed:
            break
        default:
            Issue.record("Expected failed result")
        }

        #expect(await store.count() == 0)
        #expect(await sender.callCount == 1)
    }

    @Test("Pending outbox can be sent to changed server URL")
    func pendingOutboxCanBeSentToChangedServerURL() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let oldServerURL = URL(string: "https://old.example.org")!
        let olderServerURL = URL(string: "https://older.example.org")!
        let newServerURL = URL(string: "https://new.example.org")!
        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: oldServerURL, payload: payload(timestamp: "queued-1"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: olderServerURL, payload: payload(timestamp: "queued-2"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .success(true),
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        await coordinator.sendPendingOutbox(to: newServerURL)

        #expect(await store.count() == 0)
        #expect(await sender.sentURLs == [newServerURL.absoluteString, newServerURL.absoluteString])
        #expect(await sender.sentTimestamps == ["queued-1", "queued-2"])
    }

    @Test("Server URL retarget keeps in-flight old URL item queued for new URL")
    func serverURLRetargetKeepsInFlightOldURLItemQueuedForNewURL() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let oldServerURL = URL(string: "https://old.example.org")!
        let newServerURL = URL(string: "https://new.example.org")!
        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: oldServerURL, payload: payload(timestamp: "queued"), enableHistory: true, retentionTime: 60)

        let sender = BlockingFirstUpdateSender()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.05,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        let flushTask = Task {
            await coordinator.flushOutboxNow()
        }
        await sender.waitForFirstCall()

        let retargetTask = Task {
            await coordinator.sendPendingOutbox(to: newServerURL)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await sender.releaseFirstCall()
        await flushTask.value
        await retargetTask.value
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(await store.count() == 0)
        #expect(await sender.sentURLs == [oldServerURL.absoluteString, newServerURL.absoluteString])
        #expect(await sender.sentTimestamps == ["queued", "queued"])
    }

    @Test("Pending outbox can be discarded after server URL change")
    func pendingOutboxCanBeDiscardedAfterServerURLChange() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(serverURL: URL(string: "https://old.example.org")!, payload: payload(timestamp: "queued"), enableHistory: true, retentionTime: 60)

        let sender = MockUpdateSender(outcomes: [
            .success(true)
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            }
        )

        await coordinator.discardPendingOutbox()

        #expect(await store.count() == 0)
        #expect(await sender.callCount == 0)
    }

    private func payload(
        timestamp: String,
        latitude: Double = 50.0,
        longitude: Double = 8.0
    ) -> UpdateLocationPayload {
        UpdateLocationPayload(
            Device: "TEST_DEVICE",
            DeviceKey: "KEY",
            Timestamp: timestamp,
            Longitude: longitude,
            Latitude: latitude,
            HorizontalAccuracy: 15.0,
            Speed: nil,
            BatteryLevel: nil,
            Altitude: nil
        )
    }

    private func temporaryOutboxURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return directory.appendingPathComponent("locationUpdateOutbox.json")
    }
}

private actor MockUpdateSender {
    enum Outcome {
        case success(Bool)
        case failure(Error)
    }

    private(set) var callCount: Int = 0
    private(set) var sentTimestamps: [String] = []
    private(set) var sentURLs: [String] = []
    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func send(
        url: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int
    ) async throws -> Bool {
        _ = enableHistory
        _ = retentionTime

        callCount += 1
        sentTimestamps.append(payload.Timestamp)
        sentURLs.append(url.absoluteString)
        guard !outcomes.isEmpty else {
            return true
        }

        let outcome = outcomes.removeFirst()
        switch outcome {
        case .success(let success):
            return success
        case .failure(let error):
            throw error
        }
    }
}

private actor BlockingFirstUpdateSender {
    private(set) var sentTimestamps: [String] = []
    private(set) var sentURLs: [String] = []
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var firstCallWaiters: [CheckedContinuation<Void, Never>] = []

    func send(
        url: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int
    ) async throws -> Bool {
        _ = enableHistory
        _ = retentionTime

        sentTimestamps.append(payload.Timestamp)
        sentURLs.append(url.absoluteString)

        if sentURLs.count == 1 {
            firstCallWaiters.forEach { $0.resume() }
            firstCallWaiters.removeAll()
            await withCheckedContinuation { continuation in
                firstCallContinuation = continuation
            }
        }

        return true
    }

    func waitForFirstCall() async {
        guard sentURLs.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstCallWaiters.append(continuation)
        }
    }

    func releaseFirstCall() {
        firstCallContinuation?.resume()
        firstCallContinuation = nil
    }
}
