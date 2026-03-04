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
        #expect(await sender.callCount == 1)
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
        _ = url
        _ = payload
        _ = enableHistory
        _ = retentionTime

        callCount += 1
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
