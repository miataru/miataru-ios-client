/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * IntentLocationService.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import CoreLocation
import Foundation
import MiataruAPIClient

protocol IntentLocationServicing: Sendable {
    func suggestedPeople() async throws -> [TrackedPersonEntity]
    func person(for id: String) async throws -> TrackedPersonEntity?
    func latestLocation(for personID: String) async throws -> IntentPersonLocation
    func knownPlaces() async throws -> [Never]
    func place(for id: String) async throws -> Never?
}

struct IntentPersonLocation: Sendable, Equatable {
    let personID: String
    let displayName: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double?
    let placeDescription: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var ageText: String {
        Self.ageText(for: timestamp)
    }

    static func ageText(for timestamp: Date, referenceDate: Date = Date()) -> String {
        let age = max(0, referenceDate.timeIntervalSince(timestamp))
        guard age >= 60 else {
            return NSLocalizedString("intent_location_age_less_than_minute", comment: "Age text for a location younger than one minute")
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = age >= 86_400 ? [.day] : age >= 3_600 ? [.hour] : [.minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        formatter.calendar = Calendar.current
        return formatter.string(from: age) ?? NSLocalizedString("intent_location_age_unknown", comment: "Fallback age text when a location age cannot be formatted")
    }
}

enum IntentLocationError: LocalizedError, Equatable {
    case noPeopleConfigured
    case personUnavailable
    case unauthorized
    case noLocationAvailable
    case networkUnavailable
    case invalidServerConfiguration

    var errorDescription: String? {
        switch self {
        case .noPeopleConfigured:
            return NSLocalizedString("intent_location_error_no_people_configured", comment: "Error when no tracked people are configured")
        case .personUnavailable:
            return NSLocalizedString("intent_location_error_person_unavailable", comment: "Error when a selected tracked person is no longer available")
        case .unauthorized:
            return NSLocalizedString("intent_location_error_unauthorized", comment: "Error when the user has no current-location access for a person")
        case .noLocationAvailable:
            return NSLocalizedString("intent_location_error_no_location_available", comment: "Error when no location exists for a person")
        case .networkUnavailable:
            return NSLocalizedString("intent_location_error_network_unavailable", comment: "Error when the Miataru server cannot be reached")
        case .invalidServerConfiguration:
            return NSLocalizedString("intent_location_error_invalid_server_configuration", comment: "Error when the Miataru server URL is invalid")
        }
    }
}

struct IntentPersonRecord: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let hasCurrentLocationAccess: Bool
}

struct IntentLocationPayload: Sendable, Equatable {
    let deviceID: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double?
}

protocol IntentLocationDataProviding: Sendable {
    func personRecords() async -> [IntentPersonRecord]
    func latestLocationPayload(for personID: String) async throws -> IntentLocationPayload?
    func cachedPlaceDescription(for personID: String) async -> String?
}

final class IntentLocationService: IntentLocationServicing, @unchecked Sendable {
    static let shared = IntentLocationService()

    private let provider: any IntentLocationDataProviding

    init(provider: any IntentLocationDataProviding = MiataruIntentLocationDataProvider()) {
        self.provider = provider
    }

    func suggestedPeople() async throws -> [TrackedPersonEntity] {
        let people = await visiblePersonRecords()
        return people.map(Self.entity(from:))
    }

    func person(for id: String) async throws -> TrackedPersonEntity? {
        guard let record = await visiblePersonRecord(for: id) else { return nil }
        return Self.entity(from: record)
    }

    func latestLocation(for personID: String) async throws -> IntentPersonLocation {
        let records = await provider.personRecords()
        guard !records.isEmpty else { throw IntentLocationError.noPeopleConfigured }
        guard let record = Self.matchingRecord(in: records, id: personID) else {
            throw IntentLocationError.personUnavailable
        }
        guard record.hasCurrentLocationAccess else {
            throw IntentLocationError.unauthorized
        }
        guard let payload = try await provider.latestLocationPayload(for: record.id) else {
            throw IntentLocationError.noLocationAvailable
        }

        return Self.location(
            from: payload,
            person: record,
            placeDescription: await provider.cachedPlaceDescription(for: record.id)
        )
    }

    func knownPlaces() async throws -> [Never] {
        []
    }

    func place(for id: String) async throws -> Never? {
        nil
    }

    static func entity(from record: IntentPersonRecord) -> TrackedPersonEntity {
        TrackedPersonEntity(id: record.id, name: record.name)
    }

    static func location(from payload: IntentLocationPayload, person: IntentPersonRecord, placeDescription: String?) -> IntentPersonLocation {
        IntentPersonLocation(
            personID: person.id,
            displayName: person.name,
            latitude: payload.latitude,
            longitude: payload.longitude,
            timestamp: payload.timestamp,
            horizontalAccuracy: payload.horizontalAccuracy,
            placeDescription: placeDescription
        )
    }

    private func visiblePersonRecords() async -> [IntentPersonRecord] {
        let records = await provider.personRecords()
        return records.filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.hasCurrentLocationAccess }
    }

    private func visiblePersonRecord(for id: String) async -> IntentPersonRecord? {
        let records = await visiblePersonRecords()
        return Self.matchingRecord(in: records, id: id)
    }

    private static func matchingRecord(in records: [IntentPersonRecord], id: String) -> IntentPersonRecord? {
        let normalizedID = normalizedDeviceID(id)
        guard !normalizedID.isEmpty else { return nil }
        return records.first { normalizedDeviceID($0.id) == normalizedID }
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

final class MiataruIntentLocationDataProvider: IntentLocationDataProviding, @unchecked Sendable {
    func personRecords() async -> [IntentPersonRecord] {
        await MainActor.run {
            KnownDeviceStore.shared.devices.map(Self.record(from:))
        }
    }

    func latestLocationPayload(for personID: String) async throws -> IntentLocationPayload? {
        let configuration = await MainActor.run {
            (
                serverURL: URL(string: SettingsManager.shared.miataruServerURL),
                ownDeviceID: thisDeviceIDManager.shared.deviceID,
                ownDeviceKey: SettingsManager.shared.deviceKey
            )
        }
        guard let serverURL = configuration.serverURL else {
            throw IntentLocationError.invalidServerConfiguration
        }

        APIRequestCounter.shared.record(.getLocation)
        do {
            let locations = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: [personID],
                requestingDeviceID: configuration.ownDeviceID,
                requestingDeviceKey: configuration.ownDeviceKey
            )
            return locations
                .filter { Self.normalizedDeviceID($0.Device) == Self.normalizedDeviceID(personID) }
                .max { $0.TimestampDate < $1.TimestampDate }
                .map(Self.payload(from:))
        } catch let error as MiataruAPIClient.APIError {
            if Self.isNetworkError(error) {
                throw IntentLocationError.networkUnavailable
            }
            if Self.isAuthorizationError(error) {
                throw IntentLocationError.unauthorized
            }
            throw error
        }
    }

    func cachedPlaceDescription(for personID: String) async -> String? {
        await MainActor.run {
            guard let placemark = DeviceLocationCacheStore.shared.getPlacemark(for: personID) else {
                return nil
            }
            return Self.placeDescription(locality: placemark.locality, country: placemark.country)
        }
    }

    static func payload(from location: MiataruLocationData) -> IntentLocationPayload {
        IntentLocationPayload(
            deviceID: location.Device,
            latitude: location.Latitude,
            longitude: location.Longitude,
            timestamp: location.TimestampDate,
            horizontalAccuracy: location.HorizontalAccuracy
        )
    }

    static func record(from device: KnownDevice) -> IntentPersonRecord {
        IntentPersonRecord(
            id: device.DeviceID,
            name: displayName(for: device),
            hasCurrentLocationAccess: device.hasCurrentLocationAccess
        )
    }

    static func placeDescription(locality: String?, country: String?) -> String? {
        let trimmedLocality = trimmed(locality)
        let trimmedCountry = trimmed(country)

        switch (trimmedLocality, trimmedCountry) {
        case let (locality?, country?) where locality.localizedCaseInsensitiveCompare(country) != .orderedSame:
            return "\(locality), \(country)"
        case let (locality?, _):
            return locality
        case let (_, country?):
            return country
        default:
            return nil
        }
    }

    private static func isNetworkError(_ error: MiataruAPIClient.APIError) -> Bool {
        switch error {
        case .requestFailed(let underlyingError):
            return findURLError(in: underlyingError) != nil
        case .serverError(let statusCode, _):
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        case .invalidResponse(let response):
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return true }
            return statusCode != 401 && statusCode != 403
        case .invalidURL:
            return false
        case .encodingError, .decodingError:
            return false
        }
    }

    private static func isAuthorizationError(_ error: MiataruAPIClient.APIError) -> Bool {
        switch error {
        case .serverError(let statusCode, _):
            return statusCode == 401 || statusCode == 403
        case .invalidResponse(let response):
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode else { return false }
            return statusCode == 401 || statusCode == 403
        default:
            return false
        }
    }

    private static func findURLError(in error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code), userInfo: nsError.userInfo)
        }

        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return findURLError(in: underlyingError)
        }

        return nil
    }

    private static func displayName(for device: KnownDevice) -> String {
        let trimmedName = device.DeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? NSLocalizedString("intent_person_fallback_name", comment: "Fallback display name for a person without a device name")
            : trimmedName
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
