/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruPlaceStore.swift
 * miataru
 *
 * Created by Codex on 14.06.26.
 */

import CoreLocation
import Foundation

struct MiataruPlaceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var deviceID: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date
}

enum MiataruPlaceStoreError: LocalizedError, Equatable {
    case invalidDeviceID
    case invalidName
    case duplicateName
    case invalidCoordinate

    var errorDescription: String? {
        switch self {
        case .invalidDeviceID:
            return NSLocalizedString("intent_place_error_invalid_device", tableName: "AppIntents", comment: "Error when a saved place has no owning device")
        case .invalidName:
            return NSLocalizedString("intent_place_error_invalid_name", tableName: "AppIntents", comment: "Error when a saved place name is empty")
        case .duplicateName:
            return NSLocalizedString("intent_place_error_duplicate_name", tableName: "AppIntents", comment: "Error when a saved place name already exists")
        case .invalidCoordinate:
            return NSLocalizedString("intent_place_error_invalid_coordinate", tableName: "AppIntents", comment: "Error when a saved place coordinate is invalid")
        }
    }
}

protocol MiataruPlaceStoring: Sendable {
    func allPlaces() async -> [MiataruPlaceRecord]
    func places(forDeviceID deviceID: String) async -> [MiataruPlaceRecord]
    func place(id: UUID) async -> MiataruPlaceRecord?
    func savePlace(
        deviceID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double?
    ) async throws -> MiataruPlaceRecord
}

actor MiataruPlaceStore: MiataruPlaceStoring {
    static let shared = MiataruPlaceStore()

    static let schemaVersion = 1
    static let defaultFileName = "places.json"
    static let minimumRadiusMeters: Double = 50
    static let defaultRadiusMeters: Double = 150
    static let maximumRadiusMeters: Double = 5_000

    private var records: [MiataruPlaceRecord]
    private let fileURL: URL
    private let nowProvider: @Sendable () -> Date
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.nowProvider = nowProvider
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        records = Self.loadRecords(from: self.fileURL, decoder: decoder, fileManager: fileManager)
    }

    func allPlaces() async -> [MiataruPlaceRecord] {
        Self.sorted(records)
    }

    func place(id: UUID) async -> MiataruPlaceRecord? {
        records.first { $0.id == id }
    }

    func places(forDeviceID deviceID: String) async -> [MiataruPlaceRecord] {
        Self.sorted(records.filter { Self.deviceIDsMatch($0.deviceID, deviceID) })
    }

    @discardableResult
    func savePlace(
        deviceID: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double? = nil
    ) async throws -> MiataruPlaceRecord {
        guard let trimmedDeviceID = Self.normalizedDeviceID(deviceID) else {
            throw MiataruPlaceStoreError.invalidDeviceID
        }
        let trimmedName = Self.normalizedName(name)
        guard !trimmedName.isEmpty else {
            throw MiataruPlaceStoreError.invalidName
        }
        guard Self.isValidCoordinate(latitude: latitude, longitude: longitude) else {
            throw MiataruPlaceStoreError.invalidCoordinate
        }
        guard !records.contains(where: {
            Self.deviceIDsMatch($0.deviceID, trimmedDeviceID) &&
            Self.namesMatch($0.name, trimmedName)
        }) else {
            throw MiataruPlaceStoreError.duplicateName
        }

        let now = nowProvider()
        let record = MiataruPlaceRecord(
            id: UUID(),
            deviceID: trimmedDeviceID,
            name: trimmedName,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: Self.normalizedRadius(radiusMeters),
            createdAt: now,
            updatedAt: now
        )
        records.append(record)
        persist()
        return record
    }

    static func defaultFileURL() -> URL {
        AppDirectories.applicationSupportFile(named: defaultFileName)
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedDeviceID(_ deviceID: String) -> String? {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedRadius(_ radiusMeters: Double?) -> Double {
        guard let radiusMeters, radiusMeters.isFinite else {
            return defaultRadiusMeters
        }
        return min(max(radiusMeters, minimumRadiusMeters), maximumRadiusMeters)
    }

    static func isValidCoordinate(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate)
    }

    static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedName(lhs).compare(
            normalizedName(rhs),
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ) == .orderedSame
    }

    static func deviceIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhs = normalizedDeviceID(lhs),
              let rhs = normalizedDeviceID(rhs) else {
            return false
        }
        return lhs.compare(rhs, options: [.caseInsensitive], locale: .current) == .orderedSame
    }

    private static func sorted(_ records: [MiataruPlaceRecord]) -> [MiataruPlaceRecord] {
        records.sorted { lhs, rhs in
            let deviceOrder = lhs.deviceID.localizedStandardCompare(rhs.deviceID)
            if deviceOrder != .orderedSame {
                return deviceOrder == .orderedAscending
            }
            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func loadRecords(
        from url: URL,
        decoder: JSONDecoder,
        fileManager: FileManager
    ) -> [MiataruPlaceRecord] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let persisted = try decoder.decode(PersistedMiataruPlaceStore.self, from: data)
            guard persisted.schemaVersion == schemaVersion else {
                try? fileManager.removeItem(at: url)
                return []
            }
            return persisted.records.filter {
                normalizedDeviceID($0.deviceID) != nil &&
                !normalizedName($0.name).isEmpty &&
                isValidCoordinate(latitude: $0.latitude, longitude: $0.longitude) &&
                $0.radiusMeters.isFinite
            }
        } catch {
            try? fileManager.removeItem(at: url)
            return []
        }
    }

    private func persist() {
        let persisted = PersistedMiataruPlaceStore(
            schemaVersion: Self.schemaVersion,
            records: records
        )
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[MiataruPlaceStore] Failed to persist places: \(error.localizedDescription)")
        }
    }
}

private struct PersistedMiataruPlaceStore: Codable {
    let schemaVersion: Int
    let records: [MiataruPlaceRecord]
}
