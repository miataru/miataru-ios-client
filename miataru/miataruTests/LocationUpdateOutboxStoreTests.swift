/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateOutboxStoreTests.swift
 * miataruTests
 *
 * Created by Codex on 04.03.26.
 */

import Testing
import Foundation
import MiataruAPIClient
@testable import miataru

struct LocationUpdateOutboxStoreTests {
    @Test("FIFO order and max-cap enforcement")
    func fifoAndCap() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let clock = MutableClock(now: Date(timeIntervalSince1970: 10))
        let store = LocationUpdateOutboxStore(
            fileURL: tempURL,
            maxItems: 3,
            ttl: 3600,
            nowProvider: { clock.now }
        )

        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "1"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "2"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "3"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "4"), enableHistory: true, retentionTime: 60)

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.count == 3)
        #expect(snapshot[0].payload.Timestamp == "2")
        #expect(snapshot[1].payload.Timestamp == "3")
        #expect(snapshot[2].payload.Timestamp == "4")
    }

    @Test("TTL pruning before enqueue and read")
    func ttlPruning() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let clock = MutableClock(now: Date(timeIntervalSince1970: 100))
        let store = LocationUpdateOutboxStore(
            fileURL: tempURL,
            maxItems: 10,
            ttl: 10,
            nowProvider: { clock.now }
        )

        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "old"), enableHistory: false, retentionTime: 30)
        clock.now = Date(timeIntervalSince1970: 111)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "new"), enableHistory: false, retentionTime: 30)

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.count == 1)
        #expect(snapshot.first?.payload.Timestamp == "new")
    }

    @Test("Dedupe by Device+Timestamp+Latitude+Longitude")
    func dedupe() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let store = LocationUpdateOutboxStore(
            fileURL: tempURL,
            maxItems: 10,
            ttl: 3600
        )

        let duplicatePayload = payload(timestamp: "123", latitude: 52.0, longitude: 13.0)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: duplicatePayload, enableHistory: true, retentionTime: 40)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: duplicatePayload, enableHistory: true, retentionTime: 40)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "124", latitude: 52.0, longitude: 13.0), enableHistory: true, retentionTime: 40)

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.count == 2)
        #expect(snapshot[0].payload.Timestamp == "123")
        #expect(snapshot[1].payload.Timestamp == "124")
    }

    @Test("Runtime policy can keep aged items and raise max cap")
    func runtimePolicyCanKeepAgedItemsAndRaiseCap() async throws {
        let tempURL = temporaryOutboxURL()
        defer { try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent()) }

        let clock = MutableClock(now: Date(timeIntervalSince1970: 100))
        let store = LocationUpdateOutboxStore(
            fileURL: tempURL,
            maxItems: 1,
            ttl: 10,
            nowProvider: { clock.now }
        )

        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "old"), enableHistory: true, retentionTime: 60)
        clock.now = Date(timeIntervalSince1970: 111)
        await store.updatePolicy(maxItems: 3, ttl: nil)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "new-1"), enableHistory: true, retentionTime: 60)
        await store.enqueue(serverURL: URL(string: "https://example.org")!, payload: payload(timestamp: "new-2"), enableHistory: true, retentionTime: 60)

        let snapshot = await store.itemsSnapshot()
        #expect(snapshot.map(\.payload.Timestamp) == ["old", "new-1", "new-2"])
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
            HorizontalAccuracy: 12.0,
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

private final class MutableClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
