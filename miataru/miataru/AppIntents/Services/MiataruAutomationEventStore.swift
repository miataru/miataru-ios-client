/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAutomationEventStore.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import Foundation

enum MiataruAutomationEventKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case navigationStarted
    case navigationEnded
    case frequentTrackingStarted
    case frequentTrackingStopped
    case frequentTrackingExpired
    case trackingPaused
    case trackingResumed
    case deviceLocationUpdated
    case deviceEnteredPlace
    case deviceLeftPlace
    case unknownVisitorDetected
    case knownDeviceRequestedLocalPosition
    case deviceKeyBlockedOperation
    case lowBatteryDisabledFrequentTracking
}

enum MiataruAutomationEventPrivacyLevel: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case publicSummary
    case privateLocation
    case securitySensitive
}

struct MiataruAutomationEventRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MiataruAutomationEventKind
    let timestamp: Date
    let privacyLevel: MiataruAutomationEventPrivacyLevel
    let deviceID: String?
    let deviceDisplayName: String?
    let placeID: String?
    let placeName: String?
    let latitude: Double?
    let longitude: Double?
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        kind: MiataruAutomationEventKind,
        timestamp: Date = Date(),
        privacyLevel: MiataruAutomationEventPrivacyLevel,
        deviceID: String? = nil,
        deviceDisplayName: String? = nil,
        placeID: String? = nil,
        placeName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
        self.privacyLevel = privacyLevel
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.placeID = placeID
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.payload = payload
    }
}

struct MiataruAutomationEventFilter: Equatable, Sendable {
    var kinds: Set<MiataruAutomationEventKind>?
    var privacyLevels: Set<MiataruAutomationEventPrivacyLevel>?
    var deviceID: String?
    var includeSecuritySensitive: Bool

    init(
        kinds: Set<MiataruAutomationEventKind>? = nil,
        privacyLevels: Set<MiataruAutomationEventPrivacyLevel>? = nil,
        deviceID: String? = nil,
        includeSecuritySensitive: Bool = true
    ) {
        self.kinds = kinds
        self.privacyLevels = privacyLevels
        self.deviceID = deviceID
        self.includeSecuritySensitive = includeSecuritySensitive
    }

    static let all = MiataruAutomationEventFilter()

    func matches(_ record: MiataruAutomationEventRecord) -> Bool {
        if let kinds, !kinds.contains(record.kind) {
            return false
        }
        if let privacyLevels, !privacyLevels.contains(record.privacyLevel) {
            return false
        }
        if !includeSecuritySensitive, record.privacyLevel == .securitySensitive {
            return false
        }
        if let deviceID {
            let normalizedFilterID = Self.normalizedID(deviceID)
            guard !normalizedFilterID.isEmpty,
                  Self.normalizedID(record.deviceID ?? "") == normalizedFilterID else {
                return false
            }
        }
        return true
    }

    private static func normalizedID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct MiataruAutomationEventStorageInfo: Equatable, Sendable {
    let recordCount: Int
    let maxRecords: Int
    let retentionDays: Int
    let fileSizeBytes: Int64
}

struct MiataruAutomationEventExport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let retentionDays: Int
    let maxRecords: Int
    let recordCount: Int
    let storageBytes: Int64
    let events: [MiataruAutomationEventOutput]
}

struct MiataruAutomationEventOutput: Codable, Equatable, Sendable {
    let kind: String
    let timestamp: Date
    let summary: String
    let privacyLevel: String
    let deviceDisplayName: String?
    let placeName: String?
    let payload: [String: String]
}

protocol MiataruAutomationEventStoring: Sendable {
    func append(_ event: MiataruAutomationEventRecord) async
    func replace(
        matching shouldReplace: @Sendable (MiataruAutomationEventRecord) -> Bool,
        with event: MiataruAutomationEventRecord
    ) async
    func latest(matching filter: MiataruAutomationEventFilter) async -> MiataruAutomationEventRecord?
    func recent(since date: Date?, limit: Int) async -> [MiataruAutomationEventRecord]
    func recent(matching filter: MiataruAutomationEventFilter, since date: Date?, limit: Int) async -> [MiataruAutomationEventRecord]
    @discardableResult
    func trim(matching filter: MiataruAutomationEventFilter, limit: Int) async -> Int
    @discardableResult
    func clear(olderThan date: Date?) async -> Int
}

actor MiataruAutomationEventStore: MiataruAutomationEventStoring {
    static let shared = MiataruAutomationEventStore()

    static let schemaVersion = 1
    static let defaultMaxRecords = 2_500
    static let defaultRetentionInterval: TimeInterval = 90 * 24 * 60 * 60
    static let defaultFileName = "automation-events.json"
    static let maxPayloadEntries = 12
    static let maxPayloadKeyLength = 48
    static let maxPayloadValueLength = 160
    static let maxIdentifierLength = 128
    static let maxDisplayNameLength = 96
    static let knownDeviceLocationRequestMaxRecords = 100
    static let defaultKindMaxRecords: [MiataruAutomationEventKind: Int] = [:]

    private var records: [MiataruAutomationEventRecord]
    private let fileURL: URL
    private let maxRecords: Int
    private let kindMaxRecords: [MiataruAutomationEventKind: Int]
    private let retentionInterval: TimeInterval
    private let nowProvider: () -> Date
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL? = nil,
        maxRecords: Int = MiataruAutomationEventStore.defaultMaxRecords,
        kindMaxRecords: [MiataruAutomationEventKind: Int] = MiataruAutomationEventStore.defaultKindMaxRecords,
        retentionInterval: TimeInterval = MiataruAutomationEventStore.defaultRetentionInterval,
        nowProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL(fileManager: fileManager)
        self.maxRecords = max(1, maxRecords)
        self.kindMaxRecords = kindMaxRecords.reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key] = max(1, entry.value)
        }
        self.retentionInterval = max(1, retentionInterval)
        self.nowProvider = nowProvider
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601

        let loaded = Self.loadRecords(from: self.fileURL, decoder: decoder, fileManager: fileManager)
        let pruned = Self.prunedRecords(
            loaded,
            now: nowProvider(),
            retentionInterval: self.retentionInterval,
            maxRecords: self.maxRecords,
            kindMaxRecords: self.kindMaxRecords
        )
        records = pruned
        if pruned != loaded {
            Self.persist(pruned, to: self.fileURL, encoder: encoder, fileManager: fileManager)
        }
    }

    func append(_ event: MiataruAutomationEventRecord) async {
        let originalRecords = records
        pruneIfNeeded(persistWhenChanged: false)
        records.append(Self.sanitized(event))
        enforceMaxRecordCount()
        pruneIfNeeded(persistWhenChanged: false)
        guard records != originalRecords else { return }
        persist()
        NotificationCenter.default.post(name: .miataruAutomationEventsDidChange, object: nil)
    }

    func replace(
        matching shouldReplace: @Sendable (MiataruAutomationEventRecord) -> Bool,
        with event: MiataruAutomationEventRecord
    ) async {
        let originalRecords = records
        pruneIfNeeded(persistWhenChanged: false)
        records.removeAll(where: shouldReplace)
        records.append(Self.sanitized(event))
        enforceMaxRecordCount()
        pruneIfNeeded(persistWhenChanged: false)
        guard records != originalRecords else { return }
        persist()
        NotificationCenter.default.post(name: .miataruAutomationEventsDidChange, object: nil)
    }

    func latest(matching filter: MiataruAutomationEventFilter = .all) async -> MiataruAutomationEventRecord? {
        pruneIfNeeded()
        return records.reversed().first { filter.matches($0) }
    }

    func recent(since date: Date? = nil, limit: Int) async -> [MiataruAutomationEventRecord] {
        await recent(matching: .all, since: date, limit: limit)
    }

    func recent(
        matching filter: MiataruAutomationEventFilter = .all,
        since date: Date? = nil,
        limit: Int
    ) async -> [MiataruAutomationEventRecord] {
        pruneIfNeeded()
        let boundedLimit = max(1, min(limit, maxRecords))
        return records
            .reversed()
            .filter { record in
                if let date, record.timestamp < date {
                    return false
                }
                return filter.matches(record)
            }
            .prefix(boundedLimit)
            .map { $0 }
    }

    @discardableResult
    func trim(matching filter: MiataruAutomationEventFilter, limit: Int) async -> Int {
        let boundedLimit = max(1, limit)
        pruneIfNeeded(persistWhenChanged: false)
        let matchingRecords = records.filter { filter.matches($0) }
        let overflowCount = matchingRecords.count - boundedLimit
        guard overflowCount > 0 else { return 0 }

        let removedIDs = Set(matchingRecords.prefix(overflowCount).map(\.id))
        records.removeAll { removedIDs.contains($0.id) }
        persist()
        NotificationCenter.default.post(name: .miataruAutomationEventsDidChange, object: nil)
        return overflowCount
    }

    @discardableResult
    func clear(olderThan date: Date? = nil) async -> Int {
        let originalCount = records.count
        if let date {
            records.removeAll { $0.timestamp < date }
        } else {
            records.removeAll()
        }
        let removedCount = originalCount - records.count
        guard removedCount > 0 else { return 0 }
        if records.isEmpty {
            try? fileManager.removeItem(at: fileURL)
        } else {
            persist()
        }
        NotificationCenter.default.post(name: .miataruAutomationEventsDidChange, object: nil)
        return removedCount
    }

    func storageInfo() async -> MiataruAutomationEventStorageInfo {
        pruneIfNeeded()
        return MiataruAutomationEventStorageInfo(
            recordCount: records.count,
            maxRecords: maxRecords,
            retentionDays: Int(retentionInterval / (24 * 60 * 60)),
            fileSizeBytes: Self.fileSize(at: fileURL, fileManager: fileManager)
        )
    }

    func makeExport(
        filter: MiataruAutomationEventFilter = .all,
        generatedAt: Date = Date()
    ) async -> MiataruAutomationEventExport {
        pruneIfNeeded()
        let events = records
            .filter { filter.matches($0) }
            .map(MiataruAutomationEventFormatting.output)
        return MiataruAutomationEventExport(
            schemaVersion: Self.schemaVersion,
            generatedAt: generatedAt,
            retentionDays: Int(retentionInterval / (24 * 60 * 60)),
            maxRecords: maxRecords,
            recordCount: events.count,
            storageBytes: Self.fileSize(at: fileURL, fileManager: fileManager),
            events: events
        )
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let appContainerName = Bundle.main.bundleIdentifier ?? "miataru"
        return baseURL
            .appendingPathComponent(appContainerName, isDirectory: true)
            .appendingPathComponent(defaultFileName)
    }

    static func storageFileURL(fileManager: FileManager = .default) -> URL {
        defaultFileURL(fileManager: fileManager)
    }

    static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    static func sanitized(_ record: MiataruAutomationEventRecord) -> MiataruAutomationEventRecord {
        MiataruAutomationEventRecord(
            id: record.id,
            kind: record.kind,
            timestamp: record.timestamp,
            privacyLevel: record.privacyLevel,
            deviceID: sanitizedOptional(record.deviceID, maxLength: maxIdentifierLength),
            deviceDisplayName: sanitizedOptional(record.deviceDisplayName, maxLength: maxDisplayNameLength),
            placeID: sanitizedOptional(record.placeID, maxLength: maxIdentifierLength),
            placeName: sanitizedOptional(record.placeName, maxLength: maxDisplayNameLength),
            latitude: sanitizedCoordinate(record.latitude),
            longitude: sanitizedCoordinate(record.longitude),
            payload: sanitizedPayload(record.payload)
        )
    }

    private static func sanitizedPayload(_ payload: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for key in payload.keys.sorted() {
            guard sanitized.count < maxPayloadEntries else { break }
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty,
                  !isSensitivePayloadKey(normalizedKey),
                  let value = payload[key] else {
                continue
            }
            let sanitizedKey = truncated(normalizedKey, maxLength: maxPayloadKeyLength)
            let sanitizedValue = truncated(
                value.trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: maxPayloadValueLength
            )
            guard !sanitizedValue.isEmpty else { continue }
            sanitized[sanitizedKey] = sanitizedValue
        }
        return sanitized
    }

    private static func sanitizedOptional(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return truncated(trimmed, maxLength: maxLength)
    }

    private static func sanitizedCoordinate(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func isSensitivePayloadKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return lowered.contains("devicekey")
            || lowered.contains("device_key")
            || lowered.contains("authorization")
            || lowered.contains("auth")
            || lowered.contains("token")
            || lowered.contains("rawresponse")
            || lowered.contains("raw_response")
            || lowered.contains("apiresponse")
            || lowered.contains("api_response")
    }

    private static func truncated(_ value: String, maxLength: Int) -> String {
        guard value.count > maxLength else { return value }
        return String(value.prefix(maxLength))
    }

    private func pruneIfNeeded(persistWhenChanged: Bool = true) {
        let pruned = Self.prunedRecords(
            records,
            now: nowProvider(),
            retentionInterval: retentionInterval,
            maxRecords: maxRecords,
            kindMaxRecords: kindMaxRecords
        )
        guard pruned != records else { return }
        records = pruned
        if persistWhenChanged {
            persist()
        }
    }

    private func enforceMaxRecordCount() {
        guard records.count > maxRecords else { return }
        records.removeFirst(records.count - maxRecords)
    }

    private func persist() {
        Self.persist(records, to: fileURL, encoder: encoder, fileManager: fileManager)
    }

    private static func prunedRecords(
        _ records: [MiataruAutomationEventRecord],
        now: Date,
        retentionInterval: TimeInterval,
        maxRecords: Int,
        kindMaxRecords: [MiataruAutomationEventKind: Int]
    ) -> [MiataruAutomationEventRecord] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let agePruned = records
            .filter { $0.timestamp >= cutoff }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.timestamp < rhs.timestamp
            }
        let kindLimited = recordsByApplyingKindLimits(agePruned, kindMaxRecords: kindMaxRecords)
        guard kindLimited.count > maxRecords else { return kindLimited }
        return Array(kindLimited.suffix(maxRecords))
    }

    private static func recordsByApplyingKindLimits(
        _ records: [MiataruAutomationEventRecord],
        kindMaxRecords: [MiataruAutomationEventKind: Int]
    ) -> [MiataruAutomationEventRecord] {
        guard !kindMaxRecords.isEmpty else { return records }

        var keptReversed: [MiataruAutomationEventRecord] = []
        keptReversed.reserveCapacity(records.count)
        var keptCountByKind: [MiataruAutomationEventKind: Int] = [:]

        for record in records.reversed() {
            if let limit = kindMaxRecords[record.kind] {
                let keptCount = keptCountByKind[record.kind, default: 0]
                guard keptCount < limit else { continue }
                keptCountByKind[record.kind] = keptCount + 1
            }
            keptReversed.append(record)
        }

        return keptReversed.reversed()
    }

    private static func loadRecords(
        from fileURL: URL,
        decoder: JSONDecoder,
        fileManager: FileManager
    ) -> [MiataruAutomationEventRecord] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        do {
            let persistedLog = try decoder.decode(PersistedLog.self, from: data)
            guard persistedLog.schemaVersion == schemaVersion else {
                try? fileManager.removeItem(at: fileURL)
                return []
            }
            return persistedLog.records.map(sanitized)
        } catch {
            debugLog("[MiataruAutomationEventStore] Failed decoding event log, starting empty: \(error)")
            try? fileManager.removeItem(at: fileURL)
            return []
        }
    }

    private static func persist(
        _ records: [MiataruAutomationEventRecord],
        to fileURL: URL,
        encoder: JSONEncoder,
        fileManager: FileManager
    ) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(PersistedLog(schemaVersion: schemaVersion, records: records))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[MiataruAutomationEventStore] Failed persisting event log: \(error)")
        }
    }

    private struct PersistedLog: Codable, Equatable {
        let schemaVersion: Int
        let records: [MiataruAutomationEventRecord]
    }
}

extension Notification.Name {
    static let miataruAutomationEventsDidChange = Notification.Name("miataruAutomationEventsDidChange")
}
