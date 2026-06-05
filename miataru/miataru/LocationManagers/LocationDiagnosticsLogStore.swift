/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationDiagnosticsLogStore.swift
 * miataru
 *
 * Created by Codex on 05.06.26.
 */

import Foundation
import CoreLocation

enum LocationDiagnosticsLogLevel: String, Codable, Equatable {
    case info
    case warning
    case error
}

enum LocationDiagnosticsRetentionClass: String, Codable, Equatable {
    case critical
    case sampled
    case coalesced
}

enum LocationDiagnosticsValue: Codable, Equatable {
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var displayText: String {
        switch self {
        case .bool(let value):
            return value ? "true" : "false"
        case .integer(let value):
            return "\(value)"
        case .double(let value):
            return String(format: "%.4f", value)
        case .string(let value):
            return value
        }
    }
}

struct LocationDiagnosticsCheck: Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let passed: Bool
    let detail: String
}

struct LocationDiagnosticsLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LocationDiagnosticsLogLevel
    let retentionClass: LocationDiagnosticsRetentionClass
    let event: String
    let summary: String
    let result: String
    let reason: String?
    let checks: [LocationDiagnosticsCheck]
    let context: [String: LocationDiagnosticsValue]

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         level: LocationDiagnosticsLogLevel,
         retentionClass: LocationDiagnosticsRetentionClass = .critical,
         event: String,
         summary: String,
         result: String,
         reason: String?,
         checks: [LocationDiagnosticsCheck] = [],
         context: [String: LocationDiagnosticsValue] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.retentionClass = retentionClass
        self.event = event
        self.summary = summary
        self.result = result
        self.reason = reason
        self.checks = checks
        self.context = context
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case level
        case retentionClass
        case event
        case summary
        case result
        case reason
        case checks
        case context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(LocationDiagnosticsLogLevel.self, forKey: .level)
        retentionClass = try container.decodeIfPresent(LocationDiagnosticsRetentionClass.self, forKey: .retentionClass) ?? .critical
        event = try container.decode(String.self, forKey: .event)
        summary = try container.decode(String.self, forKey: .summary)
        result = try container.decode(String.self, forKey: .result)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        checks = try container.decodeIfPresent([LocationDiagnosticsCheck].self, forKey: .checks) ?? []
        context = try container.decodeIfPresent([String: LocationDiagnosticsValue].self, forKey: .context) ?? [:]
    }
}

struct LocationDiagnosticsCoalescedCount: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let event: String
    let summary: String
    let result: String
    let reason: String?
    let firstAt: Date
    var lastAt: Date
    var count: Int
    var lastContext: [String: LocationDiagnosticsValue]
}

struct LocationDiagnosticsExport: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let build: String
    let maxEntries: Int
    let criticalRetentionHours: Int
    let droppedEntryCount: Int
    let oldestEntryAt: Date?
    let entryCount: Int
    let entries: [LocationDiagnosticsLogEntry]
    let coalescedCounts: [LocationDiagnosticsCoalescedCount]
}

struct LocationSignificantChangeRearmStatus: Codable, Equatable {
    enum Result: String, Codable, Equatable {
        case attempted
        case skipped
    }

    let timestamp: Date
    let buildIdentifier: String
    let result: Result
    let reason: String
    let checks: [LocationDiagnosticsCheck]
}

final class LocationDiagnosticsLogStore: ObservableObject {
    static let shared = LocationDiagnosticsLogStore()

    static let schemaVersion = 2
    static let defaultMaxEntries = 2_500
    static let criticalRetentionInterval: TimeInterval = 24 * 60 * 60
    static let defaultCoalescedCountLimit = 250
    static let defaultLogFileName = "location-diagnostics-log.json"

    @Published private(set) var entries: [LocationDiagnosticsLogEntry] = []
    @Published private(set) var coalescedCounts: [LocationDiagnosticsCoalescedCount] = []
    @Published private(set) var droppedEntryCount: Int = 0
    @Published private(set) var isEnabled: Bool

    private let maxEntries: Int
    private let coalescedCountLimit: Int
    private let userDefaults: UserDefaults
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard,
         fileURL: URL? = nil,
         maxEntries: Int = LocationDiagnosticsLogStore.defaultMaxEntries,
         coalescedCountLimit: Int = LocationDiagnosticsLogStore.defaultCoalescedCountLimit,
         fileManager: FileManager = .default) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.coalescedCountLimit = max(1, coalescedCountLimit)
        self.fileURL = fileURL ?? Self.defaultLogFileURL(fileManager: fileManager)
        self.isEnabled = userDefaults.bool(forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        let persistedLog = Self.loadPersistedLog(from: self.fileURL, decoder: decoder, fileManager: fileManager)
        entries = persistedLog.entries
        coalescedCounts = persistedLog.coalescedCounts
        droppedEntryCount = persistedLog.droppedEntryCount
        if entries.count > self.maxEntries {
            trimToLimit()
            persist()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        userDefaults.set(enabled, forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
    }

    func clear() {
        entries = []
        coalescedCounts = []
        droppedEntryCount = 0
        try? fileManager.removeItem(at: fileURL)
    }

    func append(level: LocationDiagnosticsLogLevel,
                retentionClass: LocationDiagnosticsRetentionClass = .critical,
                event: String,
                summary: String,
                result: String,
                reason: String? = nil,
                checks: @autoclosure () -> [LocationDiagnosticsCheck] = [],
                context: @autoclosure () -> [String: LocationDiagnosticsValue] = [:],
                timestamp: @autoclosure () -> Date = Date()) {
        guard isEnabled else { return }
        entries.append(LocationDiagnosticsLogEntry(
            timestamp: timestamp(),
            level: level,
            retentionClass: retentionClass,
            event: event,
            summary: summary,
            result: result,
            reason: reason,
            checks: checks(),
            context: context()
        ))
        trimToLimit()
        persist()
    }

    func appendCoalesced(level: LocationDiagnosticsLogLevel,
                         event: String,
                         summary: String,
                         result: String,
                         reason: String? = nil,
                         coalescingKey: String,
                         context: @autoclosure () -> [String: LocationDiagnosticsValue] = [:],
                         timestamp: @autoclosure () -> Date = Date(),
                         sampleEvery sampleInterval: Int = 50) {
        guard isEnabled else { return }

        let resolvedTimestamp = timestamp()
        let resolvedContext = context()
        if let index = coalescedCounts.firstIndex(where: { $0.key == coalescingKey }) {
            coalescedCounts[index].count += 1
            coalescedCounts[index].lastAt = resolvedTimestamp
            coalescedCounts[index].lastContext = resolvedContext
            if sampleInterval > 0, coalescedCounts[index].count % sampleInterval == 0 {
                append(
                    level: level,
                    retentionClass: .sampled,
                    event: event,
                    summary: "\(summary) (sample \(coalescedCounts[index].count))",
                    result: result,
                    reason: reason,
                    context: resolvedContext,
                    timestamp: resolvedTimestamp
                )
                return
            }
        } else {
            coalescedCounts.append(LocationDiagnosticsCoalescedCount(
                key: coalescingKey,
                event: event,
                summary: summary,
                result: result,
                reason: reason,
                firstAt: resolvedTimestamp,
                lastAt: resolvedTimestamp,
                count: 1,
                lastContext: resolvedContext
            ))
            append(
                level: level,
                retentionClass: .sampled,
                event: event,
                summary: "\(summary) (first coalesced sample)",
                result: result,
                reason: reason,
                context: resolvedContext,
                timestamp: resolvedTimestamp
            )
            return
        }

        trimCoalescedCountsToLimit()
        persist()
    }

    func makeExport(appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                    build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
                    generatedAt: Date = Date()) -> LocationDiagnosticsExport {
        LocationDiagnosticsExport(
            schemaVersion: Self.schemaVersion,
            generatedAt: generatedAt,
            appVersion: appVersion,
            build: build,
            maxEntries: maxEntries,
            criticalRetentionHours: Int(Self.criticalRetentionInterval / 3600),
            droppedEntryCount: droppedEntryCount,
            oldestEntryAt: entries.map(\.timestamp).min(),
            entryCount: entries.count,
            entries: entries,
            coalescedCounts: coalescedCounts.sorted { lhs, rhs in
                if lhs.lastAt == rhs.lastAt {
                    return lhs.key < rhs.key
                }
                return lhs.lastAt < rhs.lastAt
            }
        )
    }

    func exportData(appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                    build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown") throws -> Data {
        try encoder.encode(makeExport(appVersion: appVersion, build: build))
    }

    func writeTemporaryExportFile() throws -> URL {
        let data = try exportData()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "miataru-location-diagnostics-\(formatter.string(from: Date())).json"
        let url = fileManager.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func check(_ name: String, _ passed: Bool, detail: String) -> LocationDiagnosticsCheck {
        LocationDiagnosticsCheck(name: name, passed: passed, detail: detail)
    }

    static func roundedLocationContext(_ location: CLLocation?,
                                       prefix: String = "location") -> [String: LocationDiagnosticsValue] {
        guard let location else { return [:] }
        return [
            "\(prefix)Latitude": .double(round(location.coordinate.latitude, places: 4)),
            "\(prefix)Longitude": .double(round(location.coordinate.longitude, places: 4)),
            "\(prefix)AccuracyMeters": .double(round(location.horizontalAccuracy, places: 1)),
            "\(prefix)SpeedKmh": location.speed >= 0 ? .double(round(location.speed * 3.6, places: 1)) : .string("unknown"),
            "\(prefix)Timestamp": .string(ISO8601DateFormatter().string(from: location.timestamp))
        ]
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(LocationDiagnosticsPersistedLog(
                schemaVersion: Self.schemaVersion,
                entries: entries,
                coalescedCounts: coalescedCounts,
                droppedEntryCount: droppedEntryCount
            ))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[LocationDiagnosticsLogStore] Failed persisting diagnostics log: \(error)")
        }
    }

    private func trimToLimit() {
        guard entries.count > maxEntries else { return }
        var keptEntries = entries
        while keptEntries.count > maxEntries,
              let sampledIndex = keptEntries.firstIndex(where: { $0.retentionClass != .critical }) {
            keptEntries.remove(at: sampledIndex)
            droppedEntryCount += 1
        }
        if keptEntries.count > maxEntries {
            let overflowCount = keptEntries.count - maxEntries
            keptEntries.removeFirst(overflowCount)
            droppedEntryCount += overflowCount
        }
        entries = keptEntries
    }

    private func trimCoalescedCountsToLimit() {
        guard coalescedCounts.count > coalescedCountLimit else { return }
        coalescedCounts.sort { lhs, rhs in
            if lhs.lastAt == rhs.lastAt {
                return lhs.key < rhs.key
            }
            return lhs.lastAt < rhs.lastAt
        }
        let overflowCount = coalescedCounts.count - coalescedCountLimit
        coalescedCounts.removeFirst(overflowCount)
        droppedEntryCount += overflowCount
    }

    private static func loadPersistedLog(from fileURL: URL,
                                         decoder: JSONDecoder,
                                         fileManager: FileManager) -> LocationDiagnosticsPersistedLog {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }
        if let persistedLog = try? decoder.decode(LocationDiagnosticsPersistedLog.self, from: data) {
            return persistedLog
        }
        if let legacyEntries = try? decoder.decode([LocationDiagnosticsLogEntry].self, from: data) {
            return LocationDiagnosticsPersistedLog(
                schemaVersion: 1,
                entries: legacyEntries,
                coalescedCounts: [],
                droppedEntryCount: 0
            )
        }
        return .empty
    }

    private struct LocationDiagnosticsPersistedLog: Codable, Equatable {
        let schemaVersion: Int
        var entries: [LocationDiagnosticsLogEntry]
        var coalescedCounts: [LocationDiagnosticsCoalescedCount]
        var droppedEntryCount: Int

        static let empty = LocationDiagnosticsPersistedLog(
            schemaVersion: LocationDiagnosticsLogStore.schemaVersion,
            entries: [],
            coalescedCounts: [],
            droppedEntryCount: 0
        )
    }

    private static func defaultLogFileURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("LocationDiagnostics", isDirectory: true)
            .appendingPathComponent(defaultLogFileName)
    }

    private static func round(_ value: Double, places: Int) -> Double {
        guard value.isFinite else { return value }
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }
}
