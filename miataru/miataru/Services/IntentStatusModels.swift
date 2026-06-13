/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * IntentStatusModels.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import CoreLocation
import Foundation
import MapKit

struct IntentTrackingStatus: Equatable, Sendable {
    let trackingEnabled: Bool
    let authorizationStatus: CLAuthorizationStatus
    let deviceKeyAuthBlocked: Bool
    let effectiveMode: IntentTrackingMode
    let frequentTracking: IntentFrequentTrackingStatus
}

enum IntentTrackingMode: String, Equatable, Sendable {
    case stopped
    case foregroundHighAccuracy
    case backgroundSignificantChange
    case smartWaiting
    case smartFrequentActive
    case manualFrequentActive
    case blocked
}

struct IntentFrequentTrackingStatus: Equatable, Sendable {
    let manualEnabled: Bool
    let smartEnabled: Bool
    let active: Bool
    let expiresAt: Date?
    let remainingSeconds: TimeInterval?
    let durationMode: FrequentBackgroundLocationUpdateDuration
    let blockingReason: IntentFrequentTrackingBlockingReason?
}

enum IntentFrequentTrackingBlockingReason: String, Equatable, Sendable {
    case trackingDisabled
    case deviceKeyBlocked
    case alwaysAuthorizationRequired
}

struct IntentDeviceStatus: Equatable, Sendable {
    let deviceID: String
    let displayName: String
    let timestamp: Date
    let ageText: String
    let horizontalAccuracy: Double?
    let coarsePlaceDescription: String?
    let distanceMeters: Double?
    let bearingDegrees: Double?
}

struct IntentETAStatus: Equatable, Sendable {
    let deviceStatus: IntentDeviceStatus
    let expectedTravelTimeSeconds: TimeInterval
    let distanceMeters: Double
    let transportMode: IntentTransportMode
}

enum IntentTransportMode: String, Equatable, Sendable {
    case walking
    case automobile
    case transit

    static func fromNavigationSetting(_ value: Int) -> IntentTransportMode {
        switch value {
        case 0:
            return .walking
        case 3:
            return .transit
        default:
            return .automobile
        }
    }

    var directionsTransportType: MKDirectionsTransportType {
        switch self {
        case .walking:
            return .walking
        case .automobile:
            return .automobile
        case .transit:
            return .transit
        }
    }
}

struct IntentCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var coreLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct IntentUserLocation: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let horizontalAccuracy: Double?

    init(latitude: Double, longitude: Double, timestamp: Date = Date(), horizontalAccuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        horizontalAccuracy = location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
    }

    var coordinate: IntentCoordinate {
        IntentCoordinate(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct IntentRouteStatus: Equatable, Sendable {
    let expectedTravelTimeSeconds: TimeInterval
    let distanceMeters: Double
}

protocol IntentCurrentLocationProviding: Sendable {
    func currentUserLocation() async -> IntentUserLocation?
}

protocol IntentRouteProviding: Sendable {
    func route(
        from source: IntentCoordinate,
        to destination: IntentCoordinate,
        transportMode: IntentTransportMode
    ) async throws -> IntentRouteStatus
}

protocol IntentNavigationSettingsProviding: Sendable {
    func transportMode() async -> IntentTransportMode
}

struct MiataruIntentCurrentLocationProvider: IntentCurrentLocationProviding {
    func currentUserLocation() async -> IntentUserLocation? {
        await MainActor.run {
            guard let location = LocationManager.shared.currentLocation else { return nil }
            return IntentUserLocation(location: location)
        }
    }
}

struct MiataruIntentRouteProvider: IntentRouteProviding {
    func route(
        from source: IntentCoordinate,
        to destination: IntentCoordinate,
        transportMode: IntentTransportMode
    ) async throws -> IntentRouteStatus {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source.coreLocationCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coreLocationCoordinate))
        request.transportType = transportMode.directionsTransportType

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw IntentLocationError.etaUnavailable
            }
            return IntentRouteStatus(
                expectedTravelTimeSeconds: route.expectedTravelTime,
                distanceMeters: route.distance
            )
        } catch let error as IntentLocationError {
            throw error
        } catch {
            throw IntentLocationError.etaUnavailable
        }
    }
}

struct MiataruIntentNavigationSettingsProvider: IntentNavigationSettingsProviding {
    func transportMode() async -> IntentTransportMode {
        await MainActor.run {
            IntentTransportMode.fromNavigationSetting(SettingsManager.shared.navigationTransportType)
        }
    }
}
