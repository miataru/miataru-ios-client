/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * IntentStatusModels.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import AppIntents
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
    case lowBatteryDisabled
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

enum IntentNavigationDirection: String, AppEnum, Equatable, Sendable {
    case userToDevice
    case deviceToUser

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent_navigation_direction_type_name",
            defaultValue: "Route Direction",
            comment: "Display name for the route direction App Intent enum"
        )
    )

    static var caseDisplayRepresentations: [IntentNavigationDirection: DisplayRepresentation] = [
        .userToDevice: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_navigation_direction_user_to_device",
                defaultValue: "From Me to Device",
                comment: "Route direction from the user's current location to the selected device"
            )
        ),
        .deviceToUser: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_navigation_direction_device_to_user",
                defaultValue: "From Device to Me",
                comment: "Route direction from the selected device to the user's current location"
            )
        )
    ]

    var launchDirection: DeviceNavigationRouteDirection {
        switch self {
        case .userToDevice:
            return .userToDevice
        case .deviceToUser:
            return .deviceToUser
        }
    }

    static func fromLaunchDirection(_ direction: DeviceNavigationRouteDirection) -> IntentNavigationDirection {
        switch direction {
        case .userToDevice:
            return .userToDevice
        case .deviceToUser:
            return .deviceToUser
        }
    }
}

enum IntentNavigationPresentation: String, AppEnum, Equatable, Sendable {
    case standard
    case focused

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent_navigation_presentation_type_name",
            defaultValue: "Navigation Presentation",
            comment: "Display name for the Miataru navigation presentation App Intent enum"
        )
    )

    static var caseDisplayRepresentations: [IntentNavigationPresentation: DisplayRepresentation] = [
        .standard: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_navigation_presentation_standard",
                defaultValue: "Standard",
                comment: "Standard Miataru navigation presentation"
            )
        ),
        .focused: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_navigation_presentation_focused",
                defaultValue: "Focused",
                comment: "Focused Miataru navigation presentation"
            )
        )
    ]

    var launchPresentation: DeviceNavigationPresentation {
        switch self {
        case .standard:
            return .overview
        case .focused:
            return .focused
        }
    }

    static func fromLaunchPresentation(_ presentation: DeviceNavigationPresentation) -> IntentNavigationPresentation {
        switch presentation {
        case .overview:
            return .standard
        case .focused:
            return .focused
        }
    }
}

enum IntentTransportMode: String, AppEnum, Equatable, Sendable {
    case walking
    case automobile
    case transit

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent_transport_mode_type_name",
            defaultValue: "Transport Mode",
            comment: "Display name for the transport mode App Intent enum"
        )
    )

    static var caseDisplayRepresentations: [IntentTransportMode: DisplayRepresentation] = [
        .walking: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_transport_mode_walking",
                defaultValue: "Walking",
                comment: "Localized transport mode: walking"
            )
        ),
        .automobile: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_transport_mode_automobile",
                defaultValue: "Car",
                comment: "Localized transport mode: automobile"
            )
        ),
        .transit: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_transport_mode_transit",
                defaultValue: "Transit",
                comment: "Localized transport mode: transit"
            )
        )
    ]

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

    var navigationSettingValue: Int {
        switch self {
        case .walking:
            return 0
        case .automobile:
            return 2
        case .transit:
            return 3
        }
    }

    var appleMapsDirectionsFlag: String {
        switch self {
        case .walking:
            return "w"
        case .automobile:
            return "d"
        case .transit:
            return "r"
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

enum IntentFrequentTrackingDuration: String, AppEnum, Equatable, Sendable {
    case oneHour
    case twoHours
    case threeHours
    case fourHours
    case twelveHours
    case twentyFourHours
    case unlimited

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent_frequent_tracking_duration_type_name",
            defaultValue: "Frequent Tracking Duration",
            comment: "Display name for the frequent tracking duration App Intent enum"
        )
    )

    static var caseDisplayRepresentations: [IntentFrequentTrackingDuration: DisplayRepresentation] = [
        .oneHour: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_one_hour",
                defaultValue: "1 Hour",
                comment: "Frequent tracking duration: one hour"
            )
        ),
        .twoHours: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_two_hours",
                defaultValue: "2 Hours",
                comment: "Frequent tracking duration: two hours"
            )
        ),
        .threeHours: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_three_hours",
                defaultValue: "3 Hours",
                comment: "Frequent tracking duration: three hours"
            )
        ),
        .fourHours: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_four_hours",
                defaultValue: "4 Hours",
                comment: "Frequent tracking duration: four hours"
            )
        ),
        .twelveHours: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_twelve_hours",
                defaultValue: "12 Hours",
                comment: "Frequent tracking duration: twelve hours"
            )
        ),
        .twentyFourHours: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_twenty_four_hours",
                defaultValue: "24 Hours",
                comment: "Frequent tracking duration: twenty-four hours"
            )
        ),
        .unlimited: DisplayRepresentation(
            title: LocalizedStringResource(
                "intent_frequent_tracking_duration_unlimited",
                defaultValue: "Until Stopped",
                comment: "Frequent tracking duration: unlimited until stopped"
            )
        )
    ]

    var durationMode: FrequentBackgroundLocationUpdateDuration {
        switch self {
        case .oneHour:
            return .oneHour
        case .twoHours:
            return .twoHours
        case .threeHours:
            return .threeHours
        case .fourHours:
            return .fourHours
        case .twelveHours:
            return .twelveHours
        case .twentyFourHours:
            return .twentyFourHours
        case .unlimited:
            return .unlimited
        }
    }

    static func fromDurationMode(_ mode: FrequentBackgroundLocationUpdateDuration) -> IntentFrequentTrackingDuration {
        switch mode {
        case .oneHour:
            return .oneHour
        case .twoHours:
            return .twoHours
        case .threeHours:
            return .threeHours
        case .fourHours:
            return .fourHours
        case .twelveHours:
            return .twelveHours
        case .twentyFourHours:
            return .twentyFourHours
        case .unlimited:
            return .unlimited
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
