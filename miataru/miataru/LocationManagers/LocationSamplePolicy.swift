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

    struct SubmissionDeduplicationKey: Equatable {
        let timestampSeconds: Int64
        let latitudeMicrodegrees: Int64
        let longitudeMicrodegrees: Int64
    }

    static let maximumFutureSkew: TimeInterval = 60
    static let maximumAge: TimeInterval = 10 * 60

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
}
