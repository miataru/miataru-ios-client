/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * KnownVisitorAccessHistory.swift
 * miataru
 *
 * Created by Codex on 16.06.26.
 */

import Foundation
import MiataruAPIClient

struct KnownVisitorAccessKnownDeviceSnapshot: Equatable, Sendable {
    let deviceID: String
    let displayName: String
}

struct KnownVisitorAccessLocationSnapshot: Equatable, Sendable {
    let deviceID: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let locality: String?
    let country: String?

    var placeDescription: String? {
        Self.placeDescription(locality: locality, country: country)
    }

    static func placeDescription(locality: String?, country: String?) -> String? {
        let trimmedLocality = locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (trimmedLocality?.isEmpty == false ? trimmedLocality : nil,
                trimmedCountry?.isEmpty == false ? trimmedCountry : nil) {
        case let (locality?, country?):
            return "\(locality), \(country)"
        case let (locality?, nil):
            return locality
        case let (nil, country?):
            return country
        default:
            return nil
        }
    }
}

struct KnownVisitorAccessHistoryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let deviceID: String
    let deviceDisplayName: String
    let timestamp: Date
    let latitude: Double?
    let longitude: Double?
    let placeDescription: String?
    let accessCount: Int
    let earliestTimestamp: Date

    init(
        id: UUID,
        deviceID: String,
        deviceDisplayName: String,
        timestamp: Date,
        latitude: Double?,
        longitude: Double?,
        placeDescription: String?,
        accessCount: Int = 1,
        earliestTimestamp: Date? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.placeDescription = placeDescription
        self.accessCount = max(1, accessCount)
        self.earliestTimestamp = earliestTimestamp ?? timestamp
    }
}

enum KnownVisitorAccessHistory {
    static let maxStoredAccesses = MiataruAutomationEventStore.knownDeviceLocationRequestMaxRecords
    static let accessSummaryWindow: TimeInterval = 60 * 60
    static let eventKind: MiataruAutomationEventKind = .knownDeviceRequestedLocalPosition
    static let visitTimestampMsPayloadKey = "visitTimestampMs"
    static let summaryAccessCountPayloadKey = "summaryAccessCount"
    static let summaryEarliestTimestampMsPayloadKey = "summaryEarliestTimestampMs"
    private static let requestingDevicePlacePayloadKey = "requestingDevicePlace"
    private static let requestingDeviceLocationTimestampPayloadKey = "requestingDeviceLocationTimestamp"
    private static let summaryWindowMinutesPayloadKey = "summaryWindowMinutes"
    private static let sourcePayloadKey = "source"

    @MainActor
    static func recordKnownDeviceVisitorsFromCurrentStores(
        _ visitors: [MiataruVisitor],
        ownDeviceID: String,
        source: String,
        eventStore: any MiataruAutomationEventStoring = MiataruAutomationEventStore.shared
    ) async {
        let knownDevices = KnownDeviceStore.shared.devices.map { device in
            KnownVisitorAccessKnownDeviceSnapshot(
                deviceID: device.DeviceID,
                displayName: displayName(for: device.DeviceName, fallbackDeviceID: device.DeviceID)
            )
        }
        let locations = DeviceLocationCacheStore.shared.locations.map { location in
            KnownVisitorAccessLocationSnapshot(
                deviceID: location.deviceID,
                latitude: location.latitude,
                longitude: location.longitude,
                timestamp: location.timestamp,
                locality: location.locality,
                country: location.country
            )
        }

        await recordKnownDeviceVisitors(
            visitors,
            knownDevices: knownDevices,
            locationSnapshots: locations,
            ownDeviceID: ownDeviceID,
            source: source,
            eventStore: eventStore
        )
    }

    static func recordKnownDeviceVisitors(
        _ visitors: [MiataruVisitor],
        knownDevices: [KnownVisitorAccessKnownDeviceSnapshot],
        locationSnapshots: [KnownVisitorAccessLocationSnapshot],
        ownDeviceID: String,
        source: String,
        eventStore: any MiataruAutomationEventStoring = MiataruAutomationEventStore.shared
    ) async {
        let records = eventRecords(
            from: visitors,
            knownDevices: knownDevices,
            locationSnapshots: locationSnapshots,
            ownDeviceID: ownDeviceID,
            source: source
        )
        guard !records.isEmpty else { return }

        for record in records {
            guard let deviceID = record.deviceID else {
                continue
            }

            let existingRecords = await eventStore.recent(
                matching: MiataruAutomationEventFilter(kinds: [eventKind], deviceID: deviceID),
                since: nil,
                limit: maxStoredAccesses
            )
            if let summaryRecord = summaryRecord(in: existingRecords, for: record) {
                guard let mergedRecord = mergedSummaryRecord(summaryRecord, with: record),
                      mergedRecord != summaryRecord else {
                    continue
                }
                let summaryRecordID = summaryRecord.id
                await eventStore.replace(matching: { $0.id == summaryRecordID }, with: mergedRecord)
                await trimStoredAccesses(for: deviceID, eventStore: eventStore)
                continue
            }

            await eventStore.append(record)
            await trimStoredAccesses(for: deviceID, eventStore: eventStore)
        }
    }

    static func recentAccesses(
        for deviceID: String,
        eventStore: any MiataruAutomationEventStoring = MiataruAutomationEventStore.shared
    ) async -> [KnownVisitorAccessHistoryEntry] {
        let records = await eventStore.recent(
            matching: MiataruAutomationEventFilter(kinds: [eventKind], deviceID: deviceID),
            since: nil,
            limit: maxStoredAccesses
        )
        return records.compactMap(accessEntry)
    }

    static func latestAccess(
        for deviceID: String,
        eventStore: any MiataruAutomationEventStoring = MiataruAutomationEventStore.shared
    ) async -> KnownVisitorAccessHistoryEntry? {
        guard let record = await eventStore.latest(
            matching: MiataruAutomationEventFilter(kinds: [eventKind], deviceID: deviceID)
        ) else {
            return nil
        }
        return accessEntry(from: record)
    }

    static func eventRecords(
        from visitors: [MiataruVisitor],
        knownDevices: [KnownVisitorAccessKnownDeviceSnapshot],
        locationSnapshots: [KnownVisitorAccessLocationSnapshot],
        ownDeviceID: String,
        source: String
    ) -> [MiataruAutomationEventRecord] {
        let normalizedOwnDeviceID = normalizedDeviceID(ownDeviceID)
        guard !normalizedOwnDeviceID.isEmpty else { return [] }

        let knownDevicesByID = knownDevices.reduce(into: [String: KnownVisitorAccessKnownDeviceSnapshot]()) { partialResult, device in
            let normalizedID = normalizedDeviceID(device.deviceID)
            guard !normalizedID.isEmpty, normalizedID != normalizedOwnDeviceID else { return }
            if partialResult[normalizedID] == nil {
                partialResult[normalizedID] = KnownVisitorAccessKnownDeviceSnapshot(
                    deviceID: normalizedID,
                    displayName: displayName(for: device.displayName, fallbackDeviceID: normalizedID)
                )
            }
        }
        guard !knownDevicesByID.isEmpty else { return [] }

        let locationsByID = locationSnapshots.reduce(into: [String: KnownVisitorAccessLocationSnapshot]()) { partialResult, location in
            let normalizedID = normalizedDeviceID(location.deviceID)
            guard !normalizedID.isEmpty,
                  location.latitude.isFinite,
                  location.longitude.isFinite else {
                return
            }

            let normalizedLocation = KnownVisitorAccessLocationSnapshot(
                deviceID: normalizedID,
                latitude: location.latitude,
                longitude: location.longitude,
                timestamp: location.timestamp,
                locality: location.locality,
                country: location.country
            )
            if let existingLocation = partialResult[normalizedID],
               existingLocation.timestamp >= normalizedLocation.timestamp {
                return
            }
            partialResult[normalizedID] = normalizedLocation
        }

        var seenVisitorKeys: Set<String> = []
        var records: [MiataruAutomationEventRecord] = []
        for visitor in visitors {
            let normalizedVisitorDeviceID = normalizedDeviceID(visitor.DeviceID)
            guard let knownDevice = knownDevicesByID[normalizedVisitorDeviceID],
                  let visitTimestampMs = timestampMilliseconds(from: visitor),
                  visitTimestampMs > 0 else {
                continue
            }

            let visitorKey = "\(normalizedVisitorDeviceID)-\(visitTimestampMs)"
            guard !seenVisitorKeys.contains(visitorKey) else { continue }
            seenVisitorKeys.insert(visitorKey)

            let requestDate = Date(timeIntervalSince1970: Double(visitTimestampMs) / 1_000.0)
            let location = locationsByID[normalizedVisitorDeviceID]
            var payload: [String: String] = [
                visitTimestampMsPayloadKey: String(visitTimestampMs),
                summaryAccessCountPayloadKey: "1",
                summaryEarliestTimestampMsPayloadKey: String(visitTimestampMs),
                summaryWindowMinutesPayloadKey: String(Int(accessSummaryWindow / 60)),
                sourcePayloadKey: source
            ]
            if let placeDescription = location?.placeDescription {
                payload[requestingDevicePlacePayloadKey] = placeDescription
            }
            if let locationTimestamp = location?.timestamp {
                payload[requestingDeviceLocationTimestampPayloadKey] = ISO8601DateFormatter().string(from: locationTimestamp)
            }

            records.append(MiataruAutomationEventRecord(
                kind: eventKind,
                timestamp: requestDate,
                privacyLevel: .privateLocation,
                deviceID: normalizedVisitorDeviceID,
                deviceDisplayName: knownDevice.displayName,
                placeName: location?.placeDescription,
                latitude: location?.latitude,
                longitude: location?.longitude,
                payload: payload
            ))
        }

        return records.sorted {
            if $0.timestamp == $1.timestamp {
                return ($0.deviceID ?? "") < ($1.deviceID ?? "")
            }
            return $0.timestamp < $1.timestamp
        }
    }

    static func accessEntry(from record: MiataruAutomationEventRecord) -> KnownVisitorAccessHistoryEntry? {
        guard record.kind == eventKind,
              let deviceID = record.deviceID else {
            return nil
        }

        return KnownVisitorAccessHistoryEntry(
            id: record.id,
            deviceID: deviceID,
            deviceDisplayName: displayName(for: record.deviceDisplayName ?? "", fallbackDeviceID: deviceID),
            timestamp: record.timestamp,
            latitude: record.latitude,
            longitude: record.longitude,
            placeDescription: record.placeName ?? record.payload[requestingDevicePlacePayloadKey],
            accessCount: summaryAccessCount(from: record),
            earliestTimestamp: summaryEarliestTimestamp(from: record)
        )
    }

    private static func summaryRecord(
        in existingRecords: [MiataruAutomationEventRecord],
        for record: MiataruAutomationEventRecord
    ) -> MiataruAutomationEventRecord? {
        existingRecords.first { existingRecord in
            guard existingRecord.kind == eventKind,
                  normalizedDeviceID(existingRecord.deviceID ?? "") == normalizedDeviceID(record.deviceID ?? "") else {
                return false
            }

            let existingEarliest = summaryEarliestTimestamp(from: existingRecord)
            let earliest = min(existingEarliest, record.timestamp)
            let latest = max(existingRecord.timestamp, record.timestamp)
            return latest.timeIntervalSince(earliest) <= accessSummaryWindow
        }
    }

    private static func mergedSummaryRecord(
        _ existingRecord: MiataruAutomationEventRecord,
        with record: MiataruAutomationEventRecord
    ) -> MiataruAutomationEventRecord? {
        guard existingRecord.kind == eventKind,
              record.kind == eventKind,
              normalizedDeviceID(existingRecord.deviceID ?? "") == normalizedDeviceID(record.deviceID ?? "") else {
            return nil
        }

        if record.timestamp <= existingRecord.timestamp {
            return existingRecord
        }

        let earliestTimestamp = min(summaryEarliestTimestamp(from: existingRecord), record.timestamp)
        let accessCount = summaryAccessCount(from: existingRecord) + 1
        var payload = record.payload
        payload[summaryAccessCountPayloadKey] = String(accessCount)
        payload[summaryEarliestTimestampMsPayloadKey] = String(milliseconds(from: earliestTimestamp))
        payload[summaryWindowMinutesPayloadKey] = String(Int(accessSummaryWindow / 60))

        return MiataruAutomationEventRecord(
            id: existingRecord.id,
            kind: record.kind,
            timestamp: record.timestamp,
            privacyLevel: record.privacyLevel,
            deviceID: record.deviceID,
            deviceDisplayName: record.deviceDisplayName,
            placeID: record.placeID,
            placeName: record.placeName,
            latitude: record.latitude,
            longitude: record.longitude,
            payload: payload
        )
    }

    static func locationDescription(for entry: KnownVisitorAccessHistoryEntry) -> String? {
        if let placeDescription = entry.placeDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !placeDescription.isEmpty {
            return placeDescription
        }

        guard let latitude = entry.latitude, let longitude = entry.longitude else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func trimStoredAccesses(
        for deviceID: String,
        eventStore: any MiataruAutomationEventStoring
    ) async {
        await eventStore.trim(
            matching: MiataruAutomationEventFilter(kinds: [eventKind], deviceID: deviceID),
            limit: maxStoredAccesses
        )
    }

    private static func displayName(for rawName: String, fallbackDeviceID: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? fallbackDeviceID : trimmedName
    }

    private static func summaryAccessCount(from record: MiataruAutomationEventRecord) -> Int {
        guard let rawCount = record.payload[summaryAccessCountPayloadKey],
              let count = Int(rawCount) else {
            return 1
        }
        return max(1, count)
    }

    private static func summaryEarliestTimestamp(from record: MiataruAutomationEventRecord) -> Date {
        guard let rawMilliseconds = record.payload[summaryEarliestTimestampMsPayloadKey],
              let milliseconds = Int64(rawMilliseconds),
              milliseconds > 0 else {
            return record.timestamp
        }
        return Date(timeIntervalSince1970: Double(milliseconds) / 1_000.0)
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000.0).rounded())
    }

    private static func timestampMilliseconds(from visitor: MiataruVisitor) -> Int64? {
        if let intValue = Int64(visitor.TimeStamp) {
            return intValue
        }
        if let doubleValue = Double(visitor.TimeStamp), doubleValue.isFinite {
            return Int64(doubleValue.rounded())
        }
        return nil
    }
}
