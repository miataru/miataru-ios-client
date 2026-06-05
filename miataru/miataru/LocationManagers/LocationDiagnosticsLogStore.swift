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
    let event: String
    let summary: String
    let result: String
    let reason: String?
    let checks: [LocationDiagnosticsCheck]
    let context: [String: LocationDiagnosticsValue]

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         level: LocationDiagnosticsLogLevel,
         event: String,
         summary: String,
         result: String,
         reason: String?,
         checks: [LocationDiagnosticsCheck] = [],
         context: [String: LocationDiagnosticsValue] = [:]) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.event = event
        self.summary = summary
        self.result = result
        self.reason = reason
        self.checks = checks
        self.context = context
    }
}

struct LocationDiagnosticsExport: Codable, Equatable {
    let generatedAt: Date
    let appVersion: String
    let build: String
    let maxEntries: Int
    let entryCount: Int
    let entries: [LocationDiagnosticsLogEntry]
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

    static let defaultMaxEntries = 1_000
    static let defaultLogFileName = "location-diagnostics-log.json"

    @Published private(set) var entries: [LocationDiagnosticsLogEntry] = []
    @Published private(set) var isEnabled: Bool

    private let maxEntries: Int
    private let userDefaults: UserDefaults
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard,
         fileURL: URL? = nil,
         maxEntries: Int = LocationDiagnosticsLogStore.defaultMaxEntries,
         fileManager: FileManager = .default) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.fileURL = fileURL ?? Self.defaultLogFileURL(fileManager: fileManager)
        self.isEnabled = userDefaults.bool(forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        entries = Self.loadEntries(from: self.fileURL, decoder: decoder, fileManager: fileManager)
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
        try? fileManager.removeItem(at: fileURL)
    }

    func append(level: LocationDiagnosticsLogLevel,
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

    func makeExport(appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
                    build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
                    generatedAt: Date = Date()) -> LocationDiagnosticsExport {
        LocationDiagnosticsExport(
            generatedAt: generatedAt,
            appVersion: appVersion,
            build: build,
            maxEntries: maxEntries,
            entryCount: entries.count,
            entries: entries
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
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[LocationDiagnosticsLogStore] Failed persisting diagnostics log: \(error)")
        }
    }

    private func trimToLimit() {
        guard entries.count > maxEntries else { return }
        entries = Array(entries.suffix(maxEntries))
    }

    private static func loadEntries(from fileURL: URL,
                                    decoder: JSONDecoder,
                                    fileManager: FileManager) -> [LocationDiagnosticsLogEntry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([LocationDiagnosticsLogEntry].self, from: data) else {
            return []
        }
        return entries
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
