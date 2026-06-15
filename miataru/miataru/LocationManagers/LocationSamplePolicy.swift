/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationSamplePolicy.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

enum LocationSamplePolicy {
    enum ProcessingDecision: String, Equatable {
        case process
        case invalid
        case futureDated
        case stale
        case outOfOrder
    }

    enum AcceptanceRejectionReason: String, Equatable {
        case invalidAccuracy = "invalid accuracy"
        case accuracyTooPoor = "accuracy too poor"
        case implausibleSpeed = "implausible speed"
    }

    struct AcceptanceMetrics: Equatable {
        let distanceMeters: CLLocationDistance?
        let elapsedSeconds: TimeInterval?
        let derivedSpeedKmh: Double?
        let gpsSpeedKmh: Double?
        let gpsSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy?
        let previousHorizontalAccuracy: CLLocationAccuracy?
        let horizontalAccuracy: CLLocationAccuracy
        let maximumHorizontalAccuracy: CLLocationAccuracy
        let maximumImplausibleSpeedKmh: Double
        let maximumTrustedGPSSpeedKmh: Double
        let maximumTrustedSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy
        let largeJumpDistanceMeters: CLLocationDistance
        let largeJumpMinimumElapsedSeconds: TimeInterval
        let largeJumpConfirmationRadiusMeters: CLLocationDistance
    }

    enum AcceptanceDecision: Equatable {
        case accept(AcceptanceMetrics)
        case reject(reason: AcceptanceRejectionReason, metrics: AcceptanceMetrics)
        case deferForConfirmation(AcceptanceMetrics)
    }

    struct SubmissionDeduplicationKey: Equatable {
        let timestampSeconds: Int64
        let latitudeMicrodegrees: Int64
        let longitudeMicrodegrees: Int64
    }

    static let maximumFutureSkew: TimeInterval = 60
    static let maximumAge: TimeInterval = 10 * 60
    static let maximumAcceptedHorizontalAccuracy: CLLocationAccuracy = 300
    static let speedSpikeMinimumDistance: CLLocationDistance = 50
    static let speedSpikeMaximumElapsed: TimeInterval = 5
    static let maximumImplausibleDerivedSpeedKmh: Double = 180
    static let maximumTrustedGPSSpeedKmh: Double = 220
    static let maximumTrustedSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy = 2
    static let largeJumpDistance: CLLocationDistance = 500
    static let largeJumpMinimumElapsed: TimeInterval = 120
    static let largeJumpConfirmationRadius: CLLocationDistance = 150

    static func processableLocationUpdates(from locations: [CLLocation]) -> [CLLocation] {
        locations
            .enumerated()
            .filter { _, location in
                let coordinate = location.coordinate
                return coordinate.latitude.isFinite &&
                coordinate.longitude.isFinite &&
                CLLocationCoordinate2DIsValid(coordinate) &&
                location.timestamp.timeIntervalSince1970.isFinite
            }
            .sorted { lhs, rhs in
                let lhsTimestamp = lhs.element.timestamp
                let rhsTimestamp = rhs.element.timestamp
                if lhsTimestamp == rhsTimestamp {
                    return lhs.offset < rhs.offset
                }
                return lhsTimestamp < rhsTimestamp
            }
            .map(\.element)
    }

    static func processingDecision(for location: CLLocation,
                                   now: Date,
                                   latestRawLocation: CLLocation?,
                                   currentLocation: CLLocation?,
                                   smartReferenceLocation: CLLocation?,
                                   maximumAge: TimeInterval = maximumAge,
                                   futureTolerance: TimeInterval = maximumFutureSkew) -> ProcessingDecision {
        let coordinate = location.coordinate
        guard coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate),
              location.timestamp.timeIntervalSince1970.isFinite,
              now.timeIntervalSince1970.isFinite else {
            return .invalid
        }

        let age = now.timeIntervalSince(location.timestamp)
        if futureTolerance >= 0, age < -futureTolerance {
            return .futureDated
        }
        if maximumAge > 0, age > maximumAge {
            return .stale
        }
        if let latestReferenceTimestamp = newestValidLocationTimestamp([
            latestRawLocation,
            currentLocation,
            smartReferenceLocation
        ]),
           location.timestamp < latestReferenceTimestamp {
            return .outOfOrder
        }
        return .process
    }

    static func newestValidLocationTimestamp(_ locations: [CLLocation?]) -> Date? {
        locations
            .compactMap { $0 }
            .filter { location in
                let coordinate = location.coordinate
                return coordinate.latitude.isFinite &&
                coordinate.longitude.isFinite &&
                CLLocationCoordinate2DIsValid(coordinate) &&
                location.timestamp.timeIntervalSince1970.isFinite
            }
            .map(\.timestamp)
            .max()
    }

    static func shouldBypassLocationSensitivityForFrequentBackgroundUpload(applicationState: UIApplication.State,
                                                                           updateSourceIsFrequentBackground: Bool,
                                                                           manualFrequentEnabled: Bool,
                                                                           smartRuntimePhase: SmartFrequentBackgroundPolicy.RuntimePhase) -> Bool {
        guard applicationState != .active,
              updateSourceIsFrequentBackground else {
            return false
        }

        return manualFrequentEnabled || smartRuntimePhase != .waiting
    }

    static func sensitivityValues(for level: Int) -> (distance: CLLocationDistance, accuracy: CLLocationAccuracy) {
        switch level {
        case 1: return (3, 2)
        case 2: return (5, 5)
        case 3: return (10, 10)
        case 4: return (25, 20)
        case 5: return (50, 40)
        default: return (5, 5)
        }
    }

    static func acceptanceDecision(for location: CLLocation,
                                   previousAcceptedLocation: CLLocation?,
                                   maximumHorizontalAccuracy: CLLocationAccuracy = maximumAcceptedHorizontalAccuracy,
                                   speedSpikeMinimumDistance: CLLocationDistance = speedSpikeMinimumDistance,
                                   speedSpikeMaximumElapsed: TimeInterval = speedSpikeMaximumElapsed,
                                   maximumImplausibleSpeedKmh: Double = maximumImplausibleDerivedSpeedKmh,
                                   maximumTrustedGPSSpeedKmh: Double = maximumTrustedGPSSpeedKmh,
                                   maximumTrustedSpeedAccuracy: CLLocationSpeedAccuracy = maximumTrustedSpeedAccuracyMetersPerSecond,
                                   largeJumpDistance: CLLocationDistance = largeJumpDistance,
                                   largeJumpMinimumElapsed: TimeInterval = largeJumpMinimumElapsed,
                                   largeJumpConfirmationRadius: CLLocationDistance = largeJumpConfirmationRadius) -> AcceptanceDecision {
        let metrics = acceptanceMetrics(
            for: location,
            previousAcceptedLocation: previousAcceptedLocation,
            maximumHorizontalAccuracy: maximumHorizontalAccuracy,
            maximumImplausibleSpeedKmh: maximumImplausibleSpeedKmh,
            maximumTrustedGPSSpeedKmh: maximumTrustedGPSSpeedKmh,
            maximumTrustedSpeedAccuracy: maximumTrustedSpeedAccuracy,
            largeJumpDistance: largeJumpDistance,
            largeJumpMinimumElapsed: largeJumpMinimumElapsed,
            largeJumpConfirmationRadius: largeJumpConfirmationRadius
        )

        guard location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0 else {
            return .reject(reason: .invalidAccuracy, metrics: metrics)
        }

        if maximumHorizontalAccuracy.isFinite,
           maximumHorizontalAccuracy >= 0,
           location.horizontalAccuracy > maximumHorizontalAccuracy {
            return .reject(reason: .accuracyTooPoor, metrics: metrics)
        }

        guard previousAcceptedLocation != nil,
              let distance = metrics.distanceMeters,
              let elapsed = metrics.elapsedSeconds else {
            return .accept(metrics)
        }

        if distance >= speedSpikeMinimumDistance,
           elapsed > 0,
           elapsed <= speedSpikeMaximumElapsed,
           let derivedSpeedKmh = metrics.derivedSpeedKmh,
           derivedSpeedKmh > maximumImplausibleSpeedKmh,
           !hasTrustedGPSSpeed(location,
                               maximumTrustedSpeedKmh: maximumTrustedGPSSpeedKmh,
                               maximumTrustedSpeedAccuracy: maximumTrustedSpeedAccuracy) {
            return .reject(reason: .implausibleSpeed, metrics: metrics)
        }

        if distance >= largeJumpDistance,
           elapsed >= largeJumpMinimumElapsed,
           !hasTrustedGPSSpeed(location,
                               maximumTrustedSpeedKmh: maximumTrustedGPSSpeedKmh,
                               maximumTrustedSpeedAccuracy: maximumTrustedSpeedAccuracy) {
            return .deferForConfirmation(metrics)
        }

        return .accept(metrics)
    }

    static func confirmsLargeJump(candidate: CLLocation,
                                  pendingCandidate: CLLocation,
                                  radiusMeters: CLLocationDistance = largeJumpConfirmationRadius) -> Bool {
        guard radiusMeters.isFinite,
              radiusMeters >= 0 else {
            return false
        }
        let distance = candidate.distance(from: pendingCandidate)
        return distance.isFinite && distance <= radiusMeters
    }

    static func returnsToPreviousAcceptedLocation(candidate: CLLocation,
                                                  previousAcceptedLocation: CLLocation,
                                                  radiusMeters: CLLocationDistance = largeJumpConfirmationRadius) -> Bool {
        confirmsLargeJump(candidate: candidate, pendingCandidate: previousAcceptedLocation, radiusMeters: radiusMeters)
    }

    static func submissionDeduplicationKey(for location: CLLocation) -> SubmissionDeduplicationKey? {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let timestamp = location.timestamp.timeIntervalSince1970
        guard latitude.isFinite,
              longitude.isFinite,
              timestamp.isFinite else {
            return nil
        }

        return SubmissionDeduplicationKey(
            timestampSeconds: Int64(timestamp.rounded(.down)),
            latitudeMicrodegrees: Int64((latitude * 1_000_000).rounded()),
            longitudeMicrodegrees: Int64((longitude * 1_000_000).rounded())
        )
    }

    static func shouldSubmitLocationForUpload(_ location: CLLocation,
                                              lastSubmittedKey: SubmissionDeduplicationKey?) -> Bool {
        guard let candidateKey = submissionDeduplicationKey(for: location),
              let lastSubmittedKey else {
            return true
        }

        return candidateKey != lastSubmittedKey
    }

    private static func acceptanceMetrics(for location: CLLocation,
                                          previousAcceptedLocation: CLLocation?,
                                          maximumHorizontalAccuracy: CLLocationAccuracy,
                                          maximumImplausibleSpeedKmh: Double,
                                          maximumTrustedGPSSpeedKmh: Double,
                                          maximumTrustedSpeedAccuracy: CLLocationSpeedAccuracy,
                                          largeJumpDistance: CLLocationDistance,
                                          largeJumpMinimumElapsed: TimeInterval,
                                          largeJumpConfirmationRadius: CLLocationDistance) -> AcceptanceMetrics {
        let distance = previousAcceptedLocation.map { location.distance(from: $0) }
        let elapsed = previousAcceptedLocation.map { location.timestamp.timeIntervalSince($0.timestamp) }
        let derivedSpeed = derivedSpeedKmh(distanceMeters: distance, elapsedSeconds: elapsed)
        return AcceptanceMetrics(
            distanceMeters: distance?.isFinite == true ? distance : nil,
            elapsedSeconds: elapsed?.isFinite == true ? elapsed : nil,
            derivedSpeedKmh: derivedSpeed,
            gpsSpeedKmh: location.speed >= 0 && location.speed.isFinite ? location.speed * 3.6 : nil,
            gpsSpeedAccuracyMetersPerSecond: location.speedAccuracy >= 0 && location.speedAccuracy.isFinite ? location.speedAccuracy : nil,
            previousHorizontalAccuracy: previousAcceptedLocation?.horizontalAccuracy,
            horizontalAccuracy: location.horizontalAccuracy,
            maximumHorizontalAccuracy: maximumHorizontalAccuracy,
            maximumImplausibleSpeedKmh: maximumImplausibleSpeedKmh,
            maximumTrustedGPSSpeedKmh: maximumTrustedGPSSpeedKmh,
            maximumTrustedSpeedAccuracyMetersPerSecond: maximumTrustedSpeedAccuracy,
            largeJumpDistanceMeters: largeJumpDistance,
            largeJumpMinimumElapsedSeconds: largeJumpMinimumElapsed,
            largeJumpConfirmationRadiusMeters: largeJumpConfirmationRadius
        )
    }

    private static func derivedSpeedKmh(distanceMeters: CLLocationDistance?,
                                        elapsedSeconds: TimeInterval?) -> Double? {
        guard let distanceMeters,
              let elapsedSeconds,
              distanceMeters.isFinite,
              elapsedSeconds.isFinite,
              distanceMeters >= 0,
              elapsedSeconds > 0 else {
            return nil
        }
        return (distanceMeters / elapsedSeconds) * 3.6
    }

    private static func hasTrustedGPSSpeed(_ location: CLLocation,
                                           maximumTrustedSpeedKmh: Double,
                                           maximumTrustedSpeedAccuracy: CLLocationSpeedAccuracy) -> Bool {
        guard maximumTrustedSpeedKmh.isFinite,
              maximumTrustedSpeedAccuracy.isFinite,
              location.speed >= 0,
              location.speed.isFinite,
              location.speed * 3.6 <= maximumTrustedSpeedKmh,
              location.speedAccuracy >= 0,
              location.speedAccuracy.isFinite,
              location.speedAccuracy <= maximumTrustedSpeedAccuracy else {
            return false
        }
        return true
    }
}
