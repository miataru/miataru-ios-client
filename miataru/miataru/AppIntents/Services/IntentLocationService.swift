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
    func suggestedDevices() async throws -> [TrackedDeviceEntity]
    func device(for id: String) async throws -> TrackedDeviceEntity?
    func latestLocation(for deviceID: String) async throws -> IntentDeviceLocation
    func deviceStatus(for deviceID: String) async throws -> IntentDeviceStatus
    func distanceStatus(for deviceID: String) async throws -> IntentDeviceStatus
    func etaStatus(for deviceID: String) async throws -> IntentETAStatus
    func knownPlaces() async throws -> [MiataruPlaceEntity]
    func knownPlaces(forDeviceID deviceID: String) async throws -> [MiataruPlaceEntity]
    func place(for id: UUID) async throws -> MiataruPlaceEntity?
    func saveCurrentPlace(deviceID: String, name: String, radiusMeters: Double?) async throws -> MiataruPlaceEntity
    func isDeviceNearPlace(deviceID: String, placeID: UUID) async throws -> IntentPlaceProximityStatus
    func devicesNearPlace(placeID: UUID) async throws -> [IntentPlaceProximityStatus]
}

struct IntentDeviceLocation: Sendable, Equatable {
    let deviceID: String
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
            return NSLocalizedString("intent_location_age_less_than_minute", tableName: "AppIntents", comment: "Age text for a location younger than one minute")
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = age >= 86_400 ? [.day] : age >= 3_600 ? [.hour] : [.minute]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full
        formatter.calendar = Calendar.current
        return formatter.string(from: age) ?? NSLocalizedString("intent_location_age_unknown", tableName: "AppIntents", comment: "Fallback age text when a location age cannot be formatted")
    }
}

enum IntentLocationError: LocalizedError, Equatable {
    case noDevicesConfigured
    case deviceUnavailable
    case unauthorized
    case noLocationAvailable
    case networkUnavailable
    case invalidServerConfiguration
    case userLocationUnavailable
    case currentLocationTooOld
    case etaUnavailable
    case placeUnavailable

    var errorDescription: String? {
        switch self {
        case .noDevicesConfigured:
            return NSLocalizedString("intent_location_error_no_devices_configured", tableName: "AppIntents", comment: "Error when no tracked devices are configured")
        case .deviceUnavailable:
            return NSLocalizedString("intent_location_error_device_unavailable", tableName: "AppIntents", comment: "Error when a selected tracked device is no longer available")
        case .unauthorized:
            return NSLocalizedString("intent_location_error_unauthorized", tableName: "AppIntents", comment: "Error when the user has no current-location access for a device")
        case .noLocationAvailable:
            return NSLocalizedString("intent_location_error_no_location_available", tableName: "AppIntents", comment: "Error when no location exists for a device")
        case .networkUnavailable:
            return NSLocalizedString("intent_location_error_network_unavailable", tableName: "AppIntents", comment: "Error when the Miataru server cannot be reached")
        case .invalidServerConfiguration:
            return NSLocalizedString("intent_location_error_invalid_server_configuration", tableName: "AppIntents", comment: "Error when the Miataru server URL is invalid")
        case .userLocationUnavailable:
            return NSLocalizedString("intent_location_error_user_location_unavailable", tableName: "AppIntents", comment: "Error when the user's current location is unavailable")
        case .currentLocationTooOld:
            return NSLocalizedString("intent_location_error_current_location_too_old", tableName: "AppIntents", comment: "Error when the user's current location is too old to save as a place")
        case .etaUnavailable:
            return NSLocalizedString("intent_location_error_eta_unavailable", tableName: "AppIntents", comment: "Error when a route ETA cannot be calculated")
        case .placeUnavailable:
            return NSLocalizedString("intent_location_error_place_unavailable", tableName: "AppIntents", comment: "Error when a selected saved place is no longer available")
        }
    }
}

struct IntentDeviceRecord: Sendable, Equatable, Identifiable {
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
    func deviceRecords() async -> [IntentDeviceRecord]
    func latestLocationPayload(for deviceID: String) async throws -> IntentLocationPayload?
    func cachedPlaceDescription(for deviceID: String) async -> String?
}

final class IntentLocationService: IntentLocationServicing, @unchecked Sendable {
    static let shared = IntentLocationService()

    private let provider: any IntentLocationDataProviding
    private let currentLocationProvider: any IntentCurrentLocationProviding
    private let routeProvider: any IntentRouteProviding
    private let navigationSettingsProvider: any IntentNavigationSettingsProviding
    private let placeStore: any MiataruPlaceStoring
    private let nowProvider: @Sendable () -> Date

    static let maximumCurrentLocationAge: TimeInterval = 15 * 60

    init(
        provider: any IntentLocationDataProviding = MiataruIntentLocationDataProvider(),
        currentLocationProvider: any IntentCurrentLocationProviding = MiataruIntentCurrentLocationProvider(),
        routeProvider: any IntentRouteProviding = MiataruIntentRouteProvider(),
        navigationSettingsProvider: any IntentNavigationSettingsProviding = MiataruIntentNavigationSettingsProvider(),
        placeStore: any MiataruPlaceStoring = MiataruPlaceStore.shared,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.currentLocationProvider = currentLocationProvider
        self.routeProvider = routeProvider
        self.navigationSettingsProvider = navigationSettingsProvider
        self.placeStore = placeStore
        self.nowProvider = nowProvider
    }

    func suggestedDevices() async throws -> [TrackedDeviceEntity] {
        let devices = await visibleDeviceRecords()
        return devices.map(Self.entity(from:))
    }

    func device(for id: String) async throws -> TrackedDeviceEntity? {
        guard let record = await visibleDeviceRecord(for: id) else { return nil }
        return Self.entity(from: record)
    }

    func latestLocation(for deviceID: String) async throws -> IntentDeviceLocation {
        let records = await provider.deviceRecords()
        guard !records.isEmpty else { throw IntentLocationError.noDevicesConfigured }
        guard let record = Self.matchingRecord(in: records, id: deviceID) else {
            throw IntentLocationError.deviceUnavailable
        }
        guard record.hasCurrentLocationAccess else {
            throw IntentLocationError.unauthorized
        }
        let requestDeviceID = TrackedDeviceIntentMetadata.trimmedDeviceID(record.id)
        guard let payload = try await provider.latestLocationPayload(for: requestDeviceID) else {
            throw IntentLocationError.noLocationAvailable
        }

        return Self.location(
            from: payload,
            device: record,
            placeDescription: await provider.cachedPlaceDescription(for: requestDeviceID)
        )
    }

    func deviceStatus(for deviceID: String) async throws -> IntentDeviceStatus {
        let location = try await latestLocation(for: deviceID)
        return Self.status(
            from: location,
            userLocation: await currentLocationProvider.currentUserLocation(),
            referenceDate: nowProvider()
        )
    }

    func distanceStatus(for deviceID: String) async throws -> IntentDeviceStatus {
        let location = try await latestLocation(for: deviceID)
        guard let userLocation = await currentLocationProvider.currentUserLocation() else {
            throw IntentLocationError.userLocationUnavailable
        }
        return Self.status(
            from: location,
            userLocation: userLocation,
            referenceDate: nowProvider()
        )
    }

    func etaStatus(for deviceID: String) async throws -> IntentETAStatus {
        let location = try await latestLocation(for: deviceID)
        guard let userLocation = await currentLocationProvider.currentUserLocation() else {
            throw IntentLocationError.userLocationUnavailable
        }
        let transportMode = await navigationSettingsProvider.transportMode()
        let route = try await routeProvider.route(
            from: userLocation.coordinate,
            to: IntentCoordinate(latitude: location.latitude, longitude: location.longitude),
            transportMode: transportMode
        )
        let deviceStatus = Self.status(
            from: location,
            userLocation: userLocation,
            referenceDate: nowProvider()
        )
        return IntentETAStatus(
            deviceStatus: deviceStatus,
            expectedTravelTimeSeconds: route.expectedTravelTimeSeconds,
            distanceMeters: route.distanceMeters,
            transportMode: transportMode
        )
    }

    func knownPlaces() async throws -> [MiataruPlaceEntity] {
        await placeStore.allPlaces().map(MiataruPlaceIntentMetadata.entity(from:))
    }

    func knownPlaces(forDeviceID deviceID: String) async throws -> [MiataruPlaceEntity] {
        let canonicalDeviceID = try await canonicalDeviceID(for: deviceID)
        return await placeStore.places(forDeviceID: canonicalDeviceID).map(MiataruPlaceIntentMetadata.entity(from:))
    }

    func place(for id: UUID) async throws -> MiataruPlaceEntity? {
        await placeStore.place(id: id).map(MiataruPlaceIntentMetadata.entity(from:))
    }

    func saveCurrentPlace(deviceID: String, name: String, radiusMeters: Double? = nil) async throws -> MiataruPlaceEntity {
        let now = nowProvider()
        let canonicalDeviceID = try await canonicalDeviceID(for: deviceID)
        guard let userLocation = await currentLocationProvider.currentUserLocation() else {
            throw IntentLocationError.userLocationUnavailable
        }
        guard now.timeIntervalSince(userLocation.timestamp) <= Self.maximumCurrentLocationAge else {
            throw IntentLocationError.currentLocationTooOld
        }
        let record = try await placeStore.savePlace(
            deviceID: canonicalDeviceID,
            name: name,
            latitude: userLocation.latitude,
            longitude: userLocation.longitude,
            radiusMeters: radiusMeters
        )
        return MiataruPlaceIntentMetadata.entity(from: record)
    }

    func isDeviceNearPlace(deviceID: String, placeID: UUID) async throws -> IntentPlaceProximityStatus {
        guard let place = await placeStore.place(id: placeID) else {
            throw IntentLocationError.placeUnavailable
        }
        guard Self.deviceIDsMatch(place.deviceID, deviceID) else {
            throw IntentLocationError.placeUnavailable
        }
        let location = try await latestLocation(for: deviceID)
        return Self.proximityStatus(for: location, place: place)
    }

    func devicesNearPlace(placeID: UUID) async throws -> [IntentPlaceProximityStatus] {
        guard let place = await placeStore.place(id: placeID) else {
            throw IntentLocationError.placeUnavailable
        }
        let records = await visibleDeviceRecords()
        guard !records.isEmpty else {
            throw IntentLocationError.noDevicesConfigured
        }

        var statuses: [IntentPlaceProximityStatus] = []
        for record in records {
            do {
                let location = try await latestLocation(for: record.id)
                let status = Self.proximityStatus(for: location, place: place)
                if status.isNear {
                    statuses.append(status)
                }
            } catch let error as IntentLocationError where [
                .noLocationAvailable,
                .deviceUnavailable,
                .unauthorized
            ].contains(error) {
                continue
            }
        }
        return statuses.sorted {
            if $0.distanceMeters != $1.distanceMeters {
                return $0.distanceMeters < $1.distanceMeters
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    static func entity(from record: IntentDeviceRecord) -> TrackedDeviceEntity {
        TrackedDeviceEntity(
            id: TrackedDeviceIntentMetadata.trimmedDeviceID(record.id),
            name: TrackedDeviceIntentMetadata.displayName(deviceName: record.name, deviceID: record.id)
        )
    }

    static func location(from payload: IntentLocationPayload, device: IntentDeviceRecord, placeDescription: String?) -> IntentDeviceLocation {
        IntentDeviceLocation(
            deviceID: TrackedDeviceIntentMetadata.trimmedDeviceID(device.id),
            displayName: TrackedDeviceIntentMetadata.displayName(deviceName: device.name, deviceID: device.id),
            latitude: payload.latitude,
            longitude: payload.longitude,
            timestamp: payload.timestamp,
            horizontalAccuracy: payload.horizontalAccuracy,
            placeDescription: placeDescription
        )
    }

    static func status(
        from location: IntentDeviceLocation,
        userLocation: IntentUserLocation?,
        referenceDate: Date
    ) -> IntentDeviceStatus {
        let targetCoordinate = IntentCoordinate(latitude: location.latitude, longitude: location.longitude)
        let distanceMeters: Double?
        let bearingDegrees: Double?
        if let userLocation {
            distanceMeters = userLocation.location.distance(from: targetCoordinate.location)
            bearingDegrees = Self.bearingDegrees(from: userLocation.coordinate, to: targetCoordinate)
        } else {
            distanceMeters = nil
            bearingDegrees = nil
        }

        return IntentDeviceStatus(
            deviceID: location.deviceID,
            displayName: location.displayName,
            timestamp: location.timestamp,
            ageText: IntentDeviceLocation.ageText(for: location.timestamp, referenceDate: referenceDate),
            horizontalAccuracy: location.horizontalAccuracy,
            coarsePlaceDescription: location.placeDescription,
            distanceMeters: distanceMeters,
            bearingDegrees: bearingDegrees
        )
    }

    static func proximityStatus(
        for location: IntentDeviceLocation,
        place: MiataruPlaceRecord
    ) -> IntentPlaceProximityStatus {
        let deviceLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let distanceMeters = deviceLocation.distance(from: placeLocation)
        let accuracyAllowance = max(location.horizontalAccuracy ?? 0, 0)
        let isNear = distanceMeters <= place.radiusMeters + accuracyAllowance

        return IntentPlaceProximityStatus(
            deviceID: location.deviceID,
            displayName: location.displayName,
            placeID: place.id,
            placeName: place.name,
            radiusMeters: place.radiusMeters,
            distanceMeters: distanceMeters,
            horizontalAccuracy: location.horizontalAccuracy,
            isNear: isNear
        )
    }

    static func bearingDegrees(from source: IntentCoordinate, to destination: IntentCoordinate) -> Double {
        let sourceLatitude = degreesToRadians(source.latitude)
        let destinationLatitude = degreesToRadians(destination.latitude)
        let longitudeDelta = degreesToRadians(destination.longitude - source.longitude)

        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(sourceLatitude) * sin(destinationLatitude) -
            sin(sourceLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        let bearing = radiansToDegrees(atan2(y, x))
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private func visibleDeviceRecords() async -> [IntentDeviceRecord] {
        let records = await provider.deviceRecords()
        return records.filter {
            TrackedDeviceIntentMetadata.isVisible(
                deviceID: $0.id,
                hasCurrentLocationAccess: $0.hasCurrentLocationAccess
            )
        }
    }

    private func visibleDeviceRecord(for id: String) async -> IntentDeviceRecord? {
        let records = await visibleDeviceRecords()
        return Self.matchingRecord(in: records, id: id)
    }

    private func canonicalDeviceID(for id: String) async throws -> String {
        let records = await provider.deviceRecords()
        guard !records.isEmpty else {
            throw IntentLocationError.noDevicesConfigured
        }
        guard let record = Self.matchingRecord(in: records, id: id) else {
            throw IntentLocationError.deviceUnavailable
        }
        return TrackedDeviceIntentMetadata.trimmedDeviceID(record.id)
    }

    private static func matchingRecord(in records: [IntentDeviceRecord], id: String) -> IntentDeviceRecord? {
        let normalizedID = normalizedDeviceID(id)
        guard !normalizedID.isEmpty else { return nil }
        return records.first { normalizedDeviceID($0.id) == normalizedID }
    }

    private static func deviceIDsMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedDeviceID(lhs) == normalizedDeviceID(rhs)
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        TrackedDeviceIntentMetadata.normalizedDeviceID(deviceID)
    }
}

final class MiataruIntentLocationDataProvider: IntentLocationDataProviding, @unchecked Sendable {
    func deviceRecords() async -> [IntentDeviceRecord] {
        await MainActor.run {
            KnownDeviceStore.shared.devices.map(Self.record(from:))
        }
    }

    func latestLocationPayload(for deviceID: String) async throws -> IntentLocationPayload? {
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
                forDeviceIDs: [deviceID],
                requestingDeviceID: configuration.ownDeviceID,
                requestingDeviceKey: configuration.ownDeviceKey
            )
            return locations
                .filter { Self.normalizedDeviceID($0.Device) == Self.normalizedDeviceID(deviceID) }
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

    func cachedPlaceDescription(for deviceID: String) async -> String? {
        await MainActor.run {
            guard let placemark = DeviceLocationCacheStore.shared.getPlacemark(for: deviceID) else {
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

    static func record(from device: KnownDevice) -> IntentDeviceRecord {
        IntentDeviceRecord(
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
        TrackedDeviceIntentMetadata.displayName(deviceName: device.DeviceName, deviceID: device.DeviceID)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        TrackedDeviceIntentMetadata.normalizedDeviceID(deviceID)
    }
}
