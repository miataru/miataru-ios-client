/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * KnownVisitorAccessHistoryTests.swift
 * miataruTests
 *
 * Created by Codex on 16.06.26.
 */

import Foundation
import MiataruAPIClient
import Testing
@testable import miataru

@Suite("Known visitor access history")
struct KnownVisitorAccessHistoryTests {
    @Test("Known visitor records include current requester location and exclude own or unknown devices")
    func knownVisitorRecordsIncludeCurrentRequesterLocation() {
        let visitDate = Date(timeIntervalSince1970: 1_800_000_000)
        let records = KnownVisitorAccessHistory.eventRecords(
            from: [
                MiataruVisitor(DeviceID: " known-device ", TimeStamp: msString(visitDate)),
                MiataruVisitor(DeviceID: "UNKNOWN-DEVICE", TimeStamp: msString(visitDate.addingTimeInterval(1))),
                MiataruVisitor(DeviceID: "OWN-DEVICE", TimeStamp: msString(visitDate.addingTimeInterval(2)))
            ],
            knownDevices: [
                KnownVisitorAccessKnownDeviceSnapshot(deviceID: "KNOWN-DEVICE", displayName: "Steffi")
            ],
            locationSnapshots: [
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "known-device",
                    latitude: 48.137,
                    longitude: 11.575,
                    timestamp: visitDate.addingTimeInterval(600),
                    locality: "Munich",
                    country: "Germany"
                ),
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "known-device",
                    latitude: 52.52,
                    longitude: 13.405,
                    timestamp: visitDate.addingTimeInterval(-20),
                    locality: "Berlin",
                    country: "Germany"
                )
            ],
            ownDeviceID: "OWN-DEVICE",
            source: "test"
        )

        #expect(records.count == 1)
        #expect(records.first?.kind == .knownDeviceRequestedLocalPosition)
        #expect(records.first?.timestamp == visitDate)
        #expect(records.first?.privacyLevel == .privateLocation)
        #expect(records.first?.deviceID == "KNOWN-DEVICE")
        #expect(records.first?.deviceDisplayName == "Steffi")
        #expect(records.first?.placeName == "Munich, Germany")
        #expect(records.first?.latitude == 48.137)
        #expect(records.first?.longitude == 11.575)
        #expect(records.first?.payload[KnownVisitorAccessHistory.visitTimestampMsPayloadKey] == msString(visitDate))
        #expect(records.first?.payload[KnownVisitorAccessHistory.summaryAccessCountPayloadKey] == "1")
        #expect(records.first?.payload[KnownVisitorAccessHistory.summaryEarliestTimestampMsPayloadKey] == msString(visitDate))
    }

    @Test("Recording deduplicates repeated visitor timestamps")
    func recordingDeduplicatesRepeatedVisitorTimestamps() async throws {
        let visitDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(fileURL: try temporaryFileURL(), nowProvider: { visitDate })
        let visitor = MiataruVisitor(DeviceID: "KNOWN-DEVICE", TimeStamp: msString(visitDate))
        let knownDevices = [
            KnownVisitorAccessKnownDeviceSnapshot(deviceID: "KNOWN-DEVICE", displayName: "Steffi")
        ]
        let locations = [
            KnownVisitorAccessLocationSnapshot(
                deviceID: "KNOWN-DEVICE",
                latitude: 52.52,
                longitude: 13.405,
                timestamp: visitDate,
                locality: "Berlin",
                country: "Germany"
            )
        ]

        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            [visitor],
            knownDevices: knownDevices,
            locationSnapshots: locations,
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )
        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            [visitor],
            knownDevices: knownDevices,
            locationSnapshots: locations,
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )

        let records = await store.recent(
            matching: MiataruAutomationEventFilter(kinds: [.knownDeviceRequestedLocalPosition], deviceID: "known-device"),
            since: nil,
            limit: 10
        )
        let latestAccess = await KnownVisitorAccessHistory.latestAccess(for: "KNOWN-DEVICE", eventStore: store)

        #expect(records.count == 1)
        #expect(records.first?.payload[KnownVisitorAccessHistory.summaryAccessCountPayloadKey] == "1")
        #expect(latestAccess?.deviceDisplayName == "Steffi")
        #expect(latestAccess?.placeDescription == "Berlin, Germany")
        #expect(latestAccess?.accessCount == 1)
    }

    @Test("Recording summarizes newer accesses within one hour")
    func recordingSummarizesNewerAccessesWithinOneHour() async throws {
        let firstVisitDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondVisitDate = firstVisitDate.addingTimeInterval(45 * 60)
        let thirdVisitDate = firstVisitDate.addingTimeInterval(2 * 60 * 60)
        let store = MiataruAutomationEventStore(fileURL: try temporaryFileURL(), nowProvider: { thirdVisitDate })
        let knownDevices = [
            KnownVisitorAccessKnownDeviceSnapshot(deviceID: "KNOWN-DEVICE", displayName: "Steffi")
        ]

        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            [MiataruVisitor(DeviceID: "KNOWN-DEVICE", TimeStamp: msString(firstVisitDate))],
            knownDevices: knownDevices,
            locationSnapshots: [
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "KNOWN-DEVICE",
                    latitude: 52.52,
                    longitude: 13.405,
                    timestamp: firstVisitDate,
                    locality: "Berlin",
                    country: "Germany"
                )
            ],
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )
        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            [MiataruVisitor(DeviceID: "KNOWN-DEVICE", TimeStamp: msString(secondVisitDate))],
            knownDevices: knownDevices,
            locationSnapshots: [
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "KNOWN-DEVICE",
                    latitude: 48.137,
                    longitude: 11.575,
                    timestamp: secondVisitDate,
                    locality: "Munich",
                    country: "Germany"
                )
            ],
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )
        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            [MiataruVisitor(DeviceID: "KNOWN-DEVICE", TimeStamp: msString(thirdVisitDate))],
            knownDevices: knownDevices,
            locationSnapshots: [
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "KNOWN-DEVICE",
                    latitude: 53.551,
                    longitude: 9.993,
                    timestamp: thirdVisitDate,
                    locality: "Hamburg",
                    country: "Germany"
                )
            ],
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )

        let records = await store.recent(
            matching: MiataruAutomationEventFilter(kinds: [.knownDeviceRequestedLocalPosition], deviceID: "known-device"),
            since: nil,
            limit: 10
        )
        let accesses = await KnownVisitorAccessHistory.recentAccesses(for: "KNOWN-DEVICE", eventStore: store)

        #expect(records.count == 2)
        #expect(records.first?.timestamp == thirdVisitDate)
        #expect(records.first?.placeName == "Hamburg, Germany")
        #expect(records.first?.payload[KnownVisitorAccessHistory.summaryAccessCountPayloadKey] == "1")
        #expect(records.last?.timestamp == secondVisitDate)
        #expect(records.last?.placeName == "Munich, Germany")
        #expect(records.last?.payload[KnownVisitorAccessHistory.summaryAccessCountPayloadKey] == "2")
        #expect(records.last?.payload[KnownVisitorAccessHistory.summaryEarliestTimestampMsPayloadKey] == msString(firstVisitDate))
        #expect(accesses.last?.accessCount == 2)
        #expect(accesses.last?.earliestTimestamp == firstVisitDate)
    }

    @Test("Recording caps summarized accesses per device")
    func recordingCapsSummarizedAccessesPerDevice() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let store = MiataruAutomationEventStore(fileURL: try temporaryFileURL(), nowProvider: { baseDate.addingTimeInterval(200 * 60 * 60) })
        let knownDevices = [
            KnownVisitorAccessKnownDeviceSnapshot(deviceID: "DEVICE-A", displayName: "Steffi"),
            KnownVisitorAccessKnownDeviceSnapshot(deviceID: "DEVICE-B", displayName: "Daniel")
        ]
        var visitors = (0...KnownVisitorAccessHistory.maxStoredAccesses).map { index in
            MiataruVisitor(DeviceID: "DEVICE-A", TimeStamp: msString(baseDate.addingTimeInterval(TimeInterval(index) * 2 * 60 * 60)))
        }
        let otherDeviceVisitDate = baseDate.addingTimeInterval(30 * 60)
        visitors.append(MiataruVisitor(DeviceID: "DEVICE-B", TimeStamp: msString(otherDeviceVisitDate)))

        await KnownVisitorAccessHistory.recordKnownDeviceVisitors(
            visitors,
            knownDevices: knownDevices,
            locationSnapshots: [
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "DEVICE-A",
                    latitude: 48.137,
                    longitude: 11.575,
                    timestamp: baseDate,
                    locality: "Munich",
                    country: "Germany"
                ),
                KnownVisitorAccessLocationSnapshot(
                    deviceID: "DEVICE-B",
                    latitude: 52.52,
                    longitude: 13.405,
                    timestamp: otherDeviceVisitDate,
                    locality: "Berlin",
                    country: "Germany"
                )
            ],
            ownDeviceID: "OWN-DEVICE",
            source: "test",
            eventStore: store
        )

        let deviceARecords = await store.recent(
            matching: MiataruAutomationEventFilter(kinds: [.knownDeviceRequestedLocalPosition], deviceID: "DEVICE-A"),
            since: nil,
            limit: KnownVisitorAccessHistory.maxStoredAccesses + 10
        )
        let deviceBRecords = await store.recent(
            matching: MiataruAutomationEventFilter(kinds: [.knownDeviceRequestedLocalPosition], deviceID: "DEVICE-B"),
            since: nil,
            limit: 10
        )

        #expect(deviceARecords.count == KnownVisitorAccessHistory.maxStoredAccesses)
        #expect(deviceARecords.last?.timestamp == baseDate.addingTimeInterval(2 * 60 * 60))
        #expect(deviceBRecords.count == 1)
        #expect(deviceBRecords.first?.timestamp == otherDeviceVisitDate)
    }

    private func msString(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1_000.0).rounded()))
    }

    private func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KnownVisitorAccessHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("automation-events.json")
    }
}
