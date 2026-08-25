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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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

    @Test("Submit queues update after expired TLS certificate failure")
    func submitQueuesAfterExpiredTLSCertificateFailure() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.requestFailed(URLError(.serverCertificateHasBadDate)))
        ])
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "tls-expired"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .failed = result {
        } else {
            Issue.record("Expected expired TLS certificate failure to remain visible while queueing original payload")
        }
        #expect(await store.itemsSnapshot().map(\.payload.Timestamp) == ["tls-expired"])
        #expect(await sender.callCount == 1)
    }

    @Test("Submit queues update when server does not acknowledge it")
    func submitQueuesWhenServerDoesNotAcknowledge() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [.success(false)])
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "not-acknowledged"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .failed = result {
        } else {
            Issue.record("Expected non-acknowledged update to report failure while remaining queued")
        }
        #expect(await store.itemsSnapshot().map(\.payload.Timestamp) == ["not-acknowledged"])
    }

    @Test("Startup heartbeat preserves cached location and refreshes timestamp and battery")
    func startupHeartbeatPreservesCachedLocationAndRefreshesMetadata() throws {
        let cachedTimestamp = Date(timeIntervalSince1970: 1_000)
        let heartbeatTimestamp = Date(timeIntervalSince1970: 2_000)
        let cachedLocation = CachedDeviceLocation(
            deviceID: "heartbeat-device",
            latitude: 49.860511,
            longitude: 10.859793,
            accuracy: 4.7,
            timestamp: cachedTimestamp,
            batteryLevel: 12,
            altitude: 273.2,
            speed: 12.6
        )

        let heartbeatLocation = try #require(
            LocationManager.startupHeartbeatLocation(
                from: cachedLocation,
                timestamp: heartbeatTimestamp
            )
        )
        let payload = try #require(
            LocationUpdateUploadService.payload(
                from: heartbeatLocation,
                deviceID: cachedLocation.deviceID,
                deviceKey: "key",
                batteryLevel: 0.85
            )
        )

        #expect(payload.Latitude == cachedLocation.latitude)
        #expect(payload.Longitude == cachedLocation.longitude)
        #expect(payload.HorizontalAccuracy == cachedLocation.accuracy)
        #expect(payload.Altitude == cachedLocation.altitude)
        #expect(payload.Speed == cachedLocation.speed)
        #expect(payload.Timestamp == "2000")
        #expect(payload.BatteryLevel == 85)
        #expect(cachedLocation.timestamp == cachedTimestamp)
        #expect(cachedLocation.batteryLevel == 12)
    }

    @Test("Startup heartbeat requires enabled reporting and a stale server update")
    func startupHeartbeatRequiresEnabledReportingAndStaleServerUpdate() {
        let now = Date(timeIntervalSince1970: 20_000)
        let minimumAge = LocationManager.startupHeartbeatMinimumServerUpdateAge

        #expect(LocationManager.shouldSendStartupHeartbeat(
            reportingEnabled: false,
            lastServerUpdate: nil,
            now: now
        ) == false)
        #expect(LocationManager.shouldSendStartupHeartbeat(
            reportingEnabled: true,
            lastServerUpdate: now.addingTimeInterval(-(minimumAge - 1)),
            now: now
        ) == false)
        #expect(LocationManager.shouldSendStartupHeartbeat(
            reportingEnabled: true,
            lastServerUpdate: now.addingTimeInterval(-minimumAge),
            now: now
        ) == true)
        #expect(LocationManager.shouldSendStartupHeartbeat(
            reportingEnabled: true,
            lastServerUpdate: nil,
            now: now
        ) == true)
    }

    @Test("Submit queues update after uncertain decoding failure")
    func submitQueuesAfterDecodingFailure() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.decodingError(NSError(domain: "decode", code: 1)))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "decode-failed"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .queued = result {
        } else {
            Issue.record("Expected decoding failure to queue original payload")
        }

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["decode-failed"])
    }

    @Test("Submit queues update after uncertain invalid response")
    func submitQueuesAfterInvalidResponse() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.invalidResponse(nil))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "invalid-response"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .queued = result {
        } else {
            Issue.record("Expected invalid response to queue original payload")
        }

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["invalid-response"])
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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

    @Test("Submit during in-flight direct send queues without waiting")
    func submitDuringInFlightDirectSendQueuesWithoutWaiting() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = BlockingFirstUpdateSender()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.2,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let firstTask = Task {
            await coordinator.submit(
                serverURL: URL(string: "https://example.org")!,
                payload: payload(timestamp: "first"),
                enableHistory: true,
                retentionTime: 60
            )
        }
        await sender.waitForFirstCall()

        let secondTask = Task {
            await coordinator.submit(
                serverURL: URL(string: "https://example.org")!,
                payload: payload(timestamp: "second"),
                enableHistory: true,
                retentionTime: 60
            )
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        let snapshotWhileFirstSendIsBlocked = await store.itemsSnapshot()
        #expect(snapshotWhileFirstSendIsBlocked.map(\.payload.Timestamp) == ["second"])

        await sender.releaseFirstCall()
        if case .sent = await firstTask.value {
        } else {
            Issue.record("Expected first direct submit to report sent after release")
        }
        if case .queued = await secondTask.value {
        } else {
            Issue.record("Expected second submit to queue while first send is in flight")
        }
        await coordinator.stopPeriodicFlushTaskForTesting()
    }

    @Test("In-flight direct send drains queued tail in FIFO order")
    func inFlightDirectSendDrainsQueuedTailInFIFOOrder() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = BlockingFirstUpdateSender()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.05,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let firstTask = Task {
            await coordinator.submit(
                serverURL: URL(string: "https://example.org")!,
                payload: payload(timestamp: "first"),
                enableHistory: true,
                retentionTime: 60
            )
        }
        await sender.waitForFirstCall()

        let secondResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "second"),
            enableHistory: false,
            retentionTime: 90
        )
        if case .queued = secondResult {
        } else {
            Issue.record("Expected second submit to queue behind in-flight direct send")
        }

        await sender.releaseFirstCall()
        _ = await firstTask.value
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(await store.count() == 0)
        #expect(await sender.sentTimestamps == ["first", "second"])
        await coordinator.stopPeriodicFlushTaskForTesting()
    }

    @Test("Retryable in-flight direct failure queues original before later submissions")
    func retryableInFlightDirectFailureQueuesOriginalBeforeLaterSubmissions() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = BlockingFirstUpdateSender(firstOutcome: .failure(MiataruAPIClient.APIError.requestFailed(URLError(.timedOut))))
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.5,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let firstTask = Task {
            await coordinator.submit(
                serverURL: URL(string: "https://example.org")!,
                payload: payload(timestamp: "first"),
                enableHistory: true,
                retentionTime: 60
            )
        }
        await sender.waitForFirstCall()

        let secondResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "second"),
            enableHistory: true,
            retentionTime: 60
        )
        if case .queued = secondResult {
        } else {
            Issue.record("Expected second submit to queue while first send is in flight")
        }

        await sender.releaseFirstCall()
        if case .queued = await firstTask.value {
        } else {
            Issue.record("Expected retryable first send failure to queue original payload")
        }

        var snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["first", "second"])

        await coordinator.flushOutboxNow()

        snapshot = await store.itemsSnapshot()
        #expect(snapshot.isEmpty)
        #expect(await sender.sentTimestamps == ["first", "first", "second"])
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let firstResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "1"),
            enableHistory: true,
            retentionTime: 60,
            deliveryDelay: 0.1,
            visitorCheckMinimumInterval: 600
        )
        let secondResult = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "2"),
            enableHistory: true,
            retentionTime: 60,
            deliveryDelay: 0.1,
            visitorCheckMinimumInterval: 600
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
        #expect(snapshot[0].visitorCheckMinimumInterval == 600)
        #expect(snapshot[1].visitorCheckMinimumInterval == 600)
        #expect(await sender.callCount == 0)

        try await Task.sleep(nanoseconds: 300_000_000)

        snapshot = await store.itemsSnapshot()
        #expect(snapshot.isEmpty)
        #expect(await sender.sentTimestamps == ["1", "2"])
        await coordinator.stopPeriodicFlushTaskForTesting()
    }

    @Test("Flush forwards queued visitor check context")
    func flushForwardsQueuedVisitorCheckContext() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "visitor-check"),
            enableHistory: true,
            retentionTime: 60,
            visitorCheckMinimumInterval: 600,
            processKnownVisitorAlerts: true
        )

        let sender = MockUpdateSender(outcomes: [.success(true)])
        let visitorProcessor = RecordingVisitorProcessor()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: { url, minimumInterval, processKnownVisitorAlerts in
                await visitorProcessor.record(
                    url: url,
                    minimumInterval: minimumInterval,
                    processKnownVisitorAlerts: processKnownVisitorAlerts
                )
            }
        )

        await coordinator.flushOutboxNow()

        let records = await visitorProcessor.recordsSnapshot()
        #expect(records.count == 1)
        #expect(records.first?.urlString == "https://example.org")
        #expect(records.first?.minimumInterval == 600)
        #expect(records.first?.processKnownVisitorAlerts == true)
    }

    @Test("Flush observer receives original queued payload metadata")
    func flushObserverReceivesOriginalQueuedPayloadMetadata() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "original-timestamp"),
            enableHistory: false,
            retentionTime: 90
        )

        let sender = MockUpdateSender(outcomes: [.success(true)])
        let flushObserver = RecordingFlushObserver()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor,
            flushObserver: { item, trigger, flushedAt in
                await flushObserver.record(item: item, trigger: trigger, flushedAt: flushedAt)
            }
        )

        await coordinator.flushOutboxNow()

        let records = await flushObserver.recordsSnapshot()
        #expect(records.count == 1)
        #expect(records.first?.timestamp == "original-timestamp")
        #expect(records.first?.trigger == "manual")
        #expect(records.first?.enableHistory == false)
        #expect(records.first?.retentionTime == 90)
    }

    @Test("Flush gate blocks automatic sends until server update pause ends")
    func flushGateBlocksSendsUntilServerUpdatePauseEnds() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "paused"),
            enableHistory: true,
            retentionTime: 60
        )

        let sender = MockUpdateSender(outcomes: [.success(true)])
        let gate = FlushEligibilityGate(allowed: false)
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor,
            flushEligibilityProvider: {
                await gate.isAllowed()
            }
        )

        await coordinator.flushOutboxNow()
        #expect(await sender.callCount == 0)
        #expect(await store.count() == 1)

        await gate.setAllowed(true)
        await coordinator.flushOutboxNow()

        #expect(await sender.sentTimestamps == ["paused"])
        #expect(await store.count() == 0)
    }

    @Test("Discarded pause outbox is not delivered after server update pause ends")
    func discardedPauseOutboxIsNotDeliveredAfterServerUpdatePauseEnds() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        await store.enqueue(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "queued-before-pause"),
            enableHistory: true,
            retentionTime: 60
        )

        let sender = MockUpdateSender(outcomes: [.success(true)])
        let gate = FlushEligibilityGate(allowed: false)
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor,
            flushEligibilityProvider: {
                await gate.isAllowed()
            }
        )

        await coordinator.discardPendingOutbox()
        await gate.setAllowed(true)
        await coordinator.flushOutboxNow()

        #expect(await sender.callCount == 0)
        #expect(await store.count() == 0)
    }

    @Test("Submit drops new updates while server update pause gate is closed")
    func submitDropsNewUpdatesWhileServerUpdatePauseGateIsClosed() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [.success(true)])
        let gate = FlushEligibilityGate(allowed: false)
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor,
            flushEligibilityProvider: {
                await gate.isAllowed()
            }
        )

        let dropped = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "during-pause"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .dropped = dropped {
        } else {
            Issue.record("Expected server update pause to drop the update")
        }
        #expect(await sender.callCount == 0)
        #expect(await store.count() == 0)

        await gate.setAllowed(true)
        let sent = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "after-pause"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .sent = sent {
        } else {
            Issue.record("Expected updates after the pause to send normally")
        }
        #expect(await sender.sentTimestamps == ["after-pause"])
        #expect(await store.count() == 0)
    }

    @Test("Flushed upload diagnostics are coalesced")
    @MainActor
    func flushedUploadDiagnosticsAreCoalesced() throws {
        let suiteName = "LocationUpdateDeliveryDiagnosticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationUpdateDeliveryDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let diagnosticsURL = directoryURL.appendingPathComponent("diagnostics.json")

        let diagnosticsLog = LocationDiagnosticsLogStore(
            userDefaults: defaults,
            fileURL: diagnosticsURL,
            automaticallyFlushesDeferredPersistence: false,
            registersLifecycleFlushObservers: false
        )
        diagnosticsLog.setEnabled(true)

        let enqueuedAt = Date(timeIntervalSince1970: 1_000)
        let flushedAt = Date(timeIntervalSince1970: 2_000)
        for index in 1...101 {
            let item = LocationUpdateOutboxItem(
                serverURLString: "https://example.org",
                enqueuedAt: enqueuedAt.addingTimeInterval(TimeInterval(index)),
                attemptCount: index,
                payload: payload(timestamp: "timestamp-\(index)", latitude: 50 + Double(index) / 1_000),
                enableHistory: index.isMultiple(of: 2),
                retentionTime: 90 + index
            )
            LocationUpdateDeliveryCoordinator.recordFlushedLocationUpdateDiagnostics(
                item: item,
                trigger: index == 101 ? "manual" : "timer",
                flushedAt: flushedAt.addingTimeInterval(TimeInterval(index)),
                diagnosticsLog: diagnosticsLog
            )
        }

        #expect(diagnosticsLog.coalescedCounts.count == 1)
        #expect(diagnosticsLog.coalescedCounts.first?.count == 101)
        #expect(diagnosticsLog.entries.map(\.event) == ["locationUpload", "locationUpload"])
        #expect(diagnosticsLog.persistenceWriteCount == 0)
        #expect(diagnosticsLog.hasPendingPersistence)

        let lastContext = try #require(diagnosticsLog.coalescedCounts.first?.lastContext)
        #expect(lastContext["trigger"] == .string("manual"))
        #expect(lastContext["locationTimestamp"] == .string("timestamp-101"))
        #expect(lastContext["attemptCount"] == .integer(101))
        #expect(lastContext["retentionTime"] == .integer(191))
        #expect(lastContext["serverURL"] == .string("https://example.org"))

        let exportData = try diagnosticsLog.exportData(appVersion: "9.9", build: "42")
        #expect(diagnosticsLog.persistenceWriteCount == 1)
        let exportObject = try #require(JSONSerialization.jsonObject(with: exportData) as? [String: Any])
        let coalescedCounts = try #require(exportObject["coalescedCounts"] as? [[String: Any]])
        #expect(coalescedCounts.first?["count"] as? Int == 101)
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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

    @Test("Flush retains failed head regardless of retry classification")
    func flushRetainsFailedHeadRegardlessOfRetryClassification() async throws {
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        await coordinator.flushOutboxNow()

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["first", "second"])
        #expect(snapshot[0].attemptCount == 1)
        #expect(snapshot[1].attemptCount == 0)
        #expect(await sender.callCount == 1)
    }

    @Test("Submit queues update for non-retryable error")
    func submitQueuesOnNonRetryableError() async throws {
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "1"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .failed = result {
        } else {
            Issue.record("Expected non-retryable error to report failure while queueing the update")
        }

        #expect(await store.count() == 1)
        #expect(await sender.callCount == 1)
    }

    @Test("Submit queues clear auth invalid response")
    func submitQueuesClearAuthInvalidResponse() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = MockUpdateSender(outcomes: [
            .failure(MiataruAPIClient.APIError.invalidResponse(Self.httpResponse(statusCode: 401)))
        ])

        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let result = await coordinator.submit(
            serverURL: URL(string: "https://example.org")!,
            payload: payload(timestamp: "auth-failed"),
            enableHistory: true,
            retentionTime: 60
        )

        if case .failed = result {
        } else {
            Issue.record("Expected clear auth invalid response to report failure while queueing the update")
        }

        #expect(await store.count() == 1)
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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

    @Test("Server URL retarget replays in-flight direct send to new URL")
    func serverURLRetargetReplaysInFlightDirectSendToNewURL() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let oldServerURL = URL(string: "https://old.example.org")!
        let newServerURL = URL(string: "https://new.example.org")!
        let store = LocationUpdateOutboxStore(fileURL: tempURL, maxItems: 20, ttl: 3600)
        let sender = BlockingFirstUpdateSender()
        let coordinator = LocationUpdateDeliveryCoordinator(
            outboxStore: store,
            flushBatchSize: 25,
            flushInterval: 60,
            deferredFlushDelay: 0.05,
            updateSender: { url, payload, enableHistory, retentionTime in
                try await sender.send(url: url, payload: payload, enableHistory: enableHistory, retentionTime: retentionTime)
            },
            visitorProcessor: Self.noOpVisitorProcessor
        )

        let submitTask = Task {
            await coordinator.submit(
                serverURL: oldServerURL,
                payload: payload(timestamp: "direct"),
                enableHistory: true,
                retentionTime: 60
            )
        }
        await sender.waitForFirstCall()

        await coordinator.sendPendingOutbox(to: newServerURL)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(await sender.sentURLs == [oldServerURL.absoluteString])

        await sender.releaseFirstCall()
        if case .sent = await submitTask.value {
        } else {
            Issue.record("Expected original direct send to report sent")
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(await store.count() == 0)
        #expect(await sender.sentURLs == [oldServerURL.absoluteString, newServerURL.absoluteString])
        #expect(await sender.sentTimestamps == ["direct", "direct"])
        await coordinator.stopPeriodicFlushTaskForTesting()
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
            },
            visitorProcessor: Self.noOpVisitorProcessor
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

    private static func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.org")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static let noOpVisitorProcessor: LocationUpdateDeliveryCoordinator.VisitorProcessor = { _, _, _ in }
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

private actor RecordingVisitorProcessor {
    struct Record: Sendable {
        let urlString: String
        let minimumInterval: TimeInterval?
        let processKnownVisitorAlerts: Bool
    }

    private var records: [Record] = []

    func record(url: URL, minimumInterval: TimeInterval?, processKnownVisitorAlerts: Bool) {
        records.append(Record(
            urlString: url.absoluteString,
            minimumInterval: minimumInterval,
            processKnownVisitorAlerts: processKnownVisitorAlerts
        ))
    }

    func recordsSnapshot() -> [Record] {
        records
    }
}

private actor RecordingFlushObserver {
    struct Record: Sendable {
        let timestamp: String
        let trigger: String
        let flushedAt: Date
        let enableHistory: Bool
        let retentionTime: Int
    }

    private var records: [Record] = []

    func record(item: LocationUpdateOutboxItem, trigger: String, flushedAt: Date) {
        records.append(Record(
            timestamp: item.payload.Timestamp,
            trigger: trigger,
            flushedAt: flushedAt,
            enableHistory: item.enableHistory,
            retentionTime: item.retentionTime
        ))
    }

    func recordsSnapshot() -> [Record] {
        records
    }
}

private actor FlushEligibilityGate {
    private var allowed: Bool

    init(allowed: Bool) {
        self.allowed = allowed
    }

    func isAllowed() -> Bool {
        allowed
    }

    func setAllowed(_ allowed: Bool) {
        self.allowed = allowed
    }
}

private actor BlockingFirstUpdateSender {
    enum FirstOutcome {
        case success(Bool)
        case failure(Error)
    }

    private(set) var sentTimestamps: [String] = []
    private(set) var sentURLs: [String] = []
    private let firstOutcome: FirstOutcome
    private var firstCallContinuation: CheckedContinuation<Void, Never>?
    private var firstCallWaiters: [CheckedContinuation<Void, Never>] = []

    init(firstOutcome: FirstOutcome = .success(true)) {
        self.firstOutcome = firstOutcome
    }

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

            switch firstOutcome {
            case .success(let success):
                return success
            case .failure(let error):
                throw error
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
