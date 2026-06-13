/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAutomationEventStoreTests.swift
 * miataruTests
 *
 * Created by Codex on 13.06.26.
 */

import Foundation
import Testing
@testable import miataru

@Suite("Automation event store")
struct MiataruAutomationEventStoreTests {
    @Test("Events encode persist reload and query in newest-first order")
    func eventsEncodePersistReloadAndQueryNewestFirst() async throws {
        let url = try temporaryFileURL()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        let first = event(kind: .navigationStarted, timestamp: firstDate, deviceDisplayName: "Daniel")
        let second = event(kind: .frequentTrackingStarted, timestamp: secondDate)
        let store = MiataruAutomationEventStore(fileURL: url, nowProvider: { secondDate })

        await store.append(first)
        await store.append(second)

        #expect(await store.latest()?.kind == .frequentTrackingStarted)
        #expect(await store.recent(limit: 10).map(\.kind) == [.frequentTrackingStarted, .navigationStarted])

        let reloadedStore = MiataruAutomationEventStore(fileURL: url, nowProvider: { secondDate })
        let reloaded = await reloadedStore.recent(limit: 10)
        #expect(reloaded.map(\.id) == [second.id, first.id])
        #expect(reloaded.first?.payload["source"] == "test")
    }

    @Test("Count cap drops oldest records")
    func countCapDropsOldestRecords() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(
            fileURL: try temporaryFileURL(),
            maxRecords: 2,
            nowProvider: { baseDate.addingTimeInterval(10) }
        )

        await store.append(event(kind: .navigationStarted, timestamp: baseDate))
        await store.append(event(kind: .navigationEnded, timestamp: baseDate.addingTimeInterval(1)))
        await store.append(event(kind: .frequentTrackingStarted, timestamp: baseDate.addingTimeInterval(2)))

        let records = await store.recent(limit: 10)
        #expect(records.map(\.kind) == [.frequentTrackingStarted, .navigationEnded])
        #expect((await store.storageInfo()).recordCount == 2)
    }

    @Test("Age cap prunes old records on load append and query")
    func ageCapPrunesOldRecords() async throws {
        let url = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = event(kind: .navigationStarted, timestamp: now.addingTimeInterval(-200))
        let fresh = event(kind: .navigationEnded, timestamp: now.addingTimeInterval(-20))
        try writePersistedLog([old, fresh], to: url)

        let store = MiataruAutomationEventStore(fileURL: url, retentionInterval: 90, nowProvider: { now })
        #expect(await store.recent(limit: 10).map(\.kind) == [.navigationEnded])

        await store.append(event(kind: .frequentTrackingStarted, timestamp: now.addingTimeInterval(-120)))
        #expect(await store.recent(limit: 10).map(\.kind) == [.navigationEnded])
    }

    @Test("Clear removes matching records and no-op clear avoids persistence")
    func clearRemovesMatchingRecordsAndNoopAvoidsPersistence() async throws {
        let url = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(fileURL: url, nowProvider: { now })

        await store.append(event(kind: .navigationStarted, timestamp: now.addingTimeInterval(-60)))
        await store.append(event(kind: .navigationEnded, timestamp: now))
        let removed = await store.clear(olderThan: now.addingTimeInterval(-1))

        #expect(removed == 1)
        #expect(await store.recent(limit: 10).map(\.kind) == [.navigationEnded])

        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let beforeModificationDate = beforeAttributes[.modificationDate] as? Date
        try await Task.sleep(nanoseconds: 100_000_000)
        let noopRemoved = await store.clear(olderThan: now.addingTimeInterval(-120))
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let afterModificationDate = afterAttributes[.modificationDate] as? Date

        #expect(noopRemoved == 0)
        #expect(afterModificationDate == beforeModificationDate)
    }

    @Test("Corrupt file recovery starts empty and removes invalid file")
    func corruptFileRecoveryStartsEmptyAndRemovesInvalidFile() async throws {
        let url = try temporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)

        let store = MiataruAutomationEventStore(fileURL: url)

        #expect(await store.latest() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Payload sanitizer trims fields bounds payloads and removes sensitive keys")
    func payloadSanitizerTrimsBoundsAndRemovesSensitiveKeys() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(fileURL: try temporaryFileURL(), nowProvider: { now })
        var payload = Dictionary(uniqueKeysWithValues: (0..<20).map { ("field\($0)", "value\($0)") })
        payload[" DeviceKey "] = "secret"
        payload["authorization"] = "bearer secret"
        payload["token"] = "secret"
        payload["long"] = String(repeating: "x", count: 300)

        await store.append(MiataruAutomationEventRecord(
            kind: .deviceKeyBlockedOperation,
            timestamp: now,
            privacyLevel: .securitySensitive,
            deviceID: "  DEVICE-1  ",
            deviceDisplayName: String(repeating: "D", count: 120),
            payload: payload
        ))

        let record = await store.latest()
        #expect(record?.deviceID == "DEVICE-1")
        #expect(record?.deviceDisplayName?.count == MiataruAutomationEventStore.maxDisplayNameLength)
        #expect(record?.payload.count == MiataruAutomationEventStore.maxPayloadEntries)
        #expect(record?.payload.keys.contains("DeviceKey") == false)
        #expect(record?.payload.keys.contains("authorization") == false)
        #expect(record?.payload.keys.contains("token") == false)
        #expect((record?.payload["long"]?.count ?? 0) <= MiataruAutomationEventStore.maxPayloadValueLength)
    }

    @Test("Storage metadata reports count cap retention and file size")
    func storageMetadataReportsCountRetentionAndFileSize() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(
            fileURL: try temporaryFileURL(),
            maxRecords: 7,
            retentionInterval: 3 * 24 * 60 * 60,
            nowProvider: { now }
        )

        await store.append(event(kind: .frequentTrackingStarted, timestamp: now))
        let info = await store.storageInfo()

        #expect(info.recordCount == 1)
        #expect(info.maxRecords == 7)
        #expect(info.retentionDays == 3)
        #expect(info.fileSizeBytes > 0)
    }

    @Test("Intent JSON output is structured and privacy summaries do not speak visitor IDs")
    func intentJSONOutputIsStructuredAndPrivacySafe() throws {
        let visitorID = "UNKNOWN-VISITOR-ID"
        let record = MiataruAutomationEventRecord(
            kind: .unknownVisitorDetected,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            privacyLevel: .securitySensitive,
            deviceID: visitorID,
            payload: ["visitorDeviceID": visitorID]
        )

        let json = MiataruAutomationEventFormatting.jsonString(for: record)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let payload = object?["payload"] as? [String: String]

        #expect(object?["kind"] as? String == "unknownVisitorDetected")
        #expect(object?["privacyLevel"] as? String == "securitySensitive")
        #expect((object?["summary"] as? String)?.contains(visitorID) == false)
        #expect(payload?["visitorDeviceID"] == visitorID)
        #expect(object?["deviceID"] == nil)
        #expect(MiataruAutomationEventFormatting.noEventJSON() == "null")
    }

    private func event(
        kind: MiataruAutomationEventKind,
        timestamp: Date,
        deviceDisplayName: String? = nil
    ) -> MiataruAutomationEventRecord {
        MiataruAutomationEventRecord(
            id: UUID(),
            kind: kind,
            timestamp: timestamp,
            privacyLevel: .publicSummary,
            deviceDisplayName: deviceDisplayName,
            payload: ["source": "test"]
        )
    }

    private func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiataruAutomationEventStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("automation-events.json")
    }

    private func writePersistedLog(_ records: [MiataruAutomationEventRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(PersistedAutomationEventLog(
            schemaVersion: MiataruAutomationEventStore.schemaVersion,
            records: records
        ))
        try data.write(to: url, options: .atomic)
    }
}

private struct PersistedAutomationEventLog: Codable {
    let schemaVersion: Int
    let records: [MiataruAutomationEventRecord]
}
