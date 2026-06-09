/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SmartFrequentBackgroundPolicy.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

enum SmartFrequentBackgroundPolicy {
    enum RuntimePhase: String, Codable, Equatable {
        case waiting
        case probing
        case confirmedActive
    }

    enum ActivationEvidenceKind: String, Equatable {
        case regionExit
        case trustedGPSSpeed
        case trustedDerivedSpeed
        case insufficient
    }

    enum WatchdogAction: String, Equatable {
        case ignore
        case wait
        case reassert
        case deactivate
    }

    enum InactivityTimerAction: Equatable {
        case none
        case schedule(Date)
        case expired
    }

    struct ActivationEvidence: Equatable {
        let kind: ActivationEvidenceKind
        let speedKmh: Double?
        let distanceMeters: CLLocationDistance?
        let elapsedSeconds: TimeInterval?
        let speedAccuracyMetersPerSecond: CLLocationSpeedAccuracy?
        let reason: String

        var activates: Bool {
            kind != .insufficient
        }

        static func regionExit(radiusMeters: CLLocationDistance) -> ActivationEvidence {
            ActivationEvidence(
                kind: .regionExit,
                speedKmh: nil,
                distanceMeters: radiusMeters,
                elapsedSeconds: nil,
                speedAccuracyMetersPerSecond: nil,
                reason: "Exited Smart wake region."
            )
        }

        static func insufficient(_ reason: String,
                                 speedKmh: Double? = nil,
                                 distanceMeters: CLLocationDistance? = nil,
                                 elapsedSeconds: TimeInterval? = nil,
                                 speedAccuracyMetersPerSecond: CLLocationSpeedAccuracy? = nil) -> ActivationEvidence {
            ActivationEvidence(
                kind: .insufficient,
                speedKmh: speedKmh,
                distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
                reason: reason
            )
        }
    }

    static let exitFenceIdentifier = "miataru.smartFrequentExitFence"
    static let defaultExitFenceRadius: CLLocationDistance = 150
    static let minimumDerivedSpeedElapsed: TimeInterval = 5
    static let maximumTrustedSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy = 2
    static let maximumActivationSpeedKmh: Double = 200
    static let runtimeWatchdogInterval: TimeInterval = 75
    static let maximumRuntimeRecoveryAttempts = 2
    static let maximumUsableLocationAccuracy: CLLocationAccuracy = 300

    static func newestExitFenceAnchor(from candidates: [CLLocation?]) -> CLLocation? {
        candidates
            .compactMap { $0 }
            .filter { isUsableForFenceAnchor($0) }
            .max { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.horizontalAccuracy > rhs.horizontalAccuracy
                }
                return lhs.timestamp < rhs.timestamp
            }
    }

    static func shouldUsePersistedSeed(now: Date,
                                       seedTimestamp: Date,
                                       inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0,
              now.timeIntervalSince1970.isFinite,
              seedTimestamp.timeIntervalSince1970.isFinite else {
            return false
        }

        let age = now.timeIntervalSince(seedTimestamp)
        return age >= 0 && age < inactivityWindow
    }

    static func seedLocation(latitude: Double,
                             longitude: Double,
                             altitude: Double,
                             horizontalAccuracy: Double,
                             verticalAccuracy: Double,
                             course: Double,
                             speed: Double,
                             timestamp: Date,
                             now: Date,
                             inactivityWindow: TimeInterval) -> CLLocation? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard latitude.isFinite,
              longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate),
              horizontalAccuracy.isFinite,
              horizontalAccuracy >= 0,
              shouldUsePersistedSeed(
                now: now,
                seedTimestamp: timestamp,
                inactivityWindow: inactivityWindow
              ) else {
            return nil
        }

        return CLLocation(
            coordinate: coordinate,
            altitude: altitude.isFinite ? altitude : 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy.isFinite ? verticalAccuracy : -1,
            course: course.isFinite ? course : -1,
            speed: speed.isFinite ? speed : -1,
            timestamp: timestamp
        )
    }

    static func speedKmh(for location: CLLocation,
                         previousLocation: CLLocation?,
                         detectionMode: SmartFrequentBackgroundSpeedDetectionMode) -> Double? {
        if location.speed >= 0, location.speed.isFinite {
            return location.speed * 3.6
        }

        guard detectionMode == .hybrid,
              let previousLocation,
              isUsableForDerivedSpeed(location),
              isUsableForDerivedSpeed(previousLocation) else {
            return nil
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsed > 0, elapsed <= 30 * 60 else {
            return nil
        }

        let distance = location.distance(from: previousLocation)
        guard distance.isFinite, distance >= 0 else {
            return nil
        }

        return (distance / elapsed) * 3.6
    }

    static func exitFenceRadius(frequentDistanceFilterMeters: Int,
                                maximumRegionMonitoringDistance: CLLocationDistance) -> CLLocationDistance {
        let desiredRadius = max(
            defaultExitFenceRadius,
            CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        )
        guard maximumRegionMonitoringDistance.isFinite,
              maximumRegionMonitoringDistance > 0 else {
            return desiredRadius
        }
        return min(desiredRadius, maximumRegionMonitoringDistance)
    }

    static func shouldMaintainExitFence(trackAndReportLocation: Bool,
                                        isTracking: Bool,
                                        authorizationStatus: CLAuthorizationStatus,
                                        deviceKeyAuthBlocked: Bool,
                                        smartEnabled: Bool,
                                        manualFrequentEnabled: Bool,
                                        smartRuntimeActive _: Bool,
                                        regionMonitoringAvailable: Bool) -> Bool {
        trackAndReportLocation &&
        isTracking &&
        authorizationStatus == .authorizedAlways &&
        !deviceKeyAuthBlocked &&
        smartEnabled &&
        !manualFrequentEnabled &&
        regionMonitoringAvailable
    }

    static func activationEvidence(for location: CLLocation,
                                   previousLocation: CLLocation?,
                                   detectionMode: SmartFrequentBackgroundSpeedDetectionMode,
                                   thresholdKmh: Int,
                                   frequentDistanceFilterMeters: Int,
                                   isStartupBatch: Bool,
                                   regionExitRadiusMeters: CLLocationDistance? = nil) -> ActivationEvidence {
        if let regionExitRadiusMeters {
            return .regionExit(radiusMeters: regionExitRadiusMeters)
        }

        let normalizedThreshold = Double(SmartFrequentBackgroundSpeedThreshold.normalized(thresholdKmh))
        let gpsSpeedKmh = gpsSpeedKmh(for: location)
        let displacement = displacementEvidence(
            from: previousLocation,
            to: location,
            frequentDistanceFilterMeters: frequentDistanceFilterMeters
        )

        if let gpsSpeedKmh,
           gpsSpeedKmh >= normalizedThreshold,
           gpsSpeedKmh <= maximumActivationSpeedKmh {
            let speedAccuracy = location.speedAccuracy
            let speedAccuracyTrusted = speedAccuracy.isFinite &&
            speedAccuracy >= 0 &&
            speedAccuracy <= maximumTrustedSpeedAccuracyMetersPerSecond

            if speedAccuracyTrusted && (!isStartupBatch || displacement.isTrusted) {
                return ActivationEvidence(
                    kind: .trustedGPSSpeed,
                    speedKmh: gpsSpeedKmh,
                    distanceMeters: displacement.distanceMeters,
                    elapsedSeconds: displacement.elapsedSeconds,
                    speedAccuracyMetersPerSecond: speedAccuracy,
                    reason: "GPS speed accuracy is trusted."
                )
            }

            if !isStartupBatch && displacement.isTrusted {
                return ActivationEvidence(
                    kind: .trustedGPSSpeed,
                    speedKmh: gpsSpeedKmh,
                    distanceMeters: displacement.distanceMeters,
                    elapsedSeconds: displacement.elapsedSeconds,
                    speedAccuracyMetersPerSecond: speedAccuracy.isFinite ? speedAccuracy : nil,
                    reason: "GPS speed was confirmed by displacement."
                )
            }
        }

        guard detectionMode == .hybrid,
              let derivedSpeedKmh = displacement.speedKmh else {
            return .insufficient(
                "No trusted Smart activation evidence.",
                speedKmh: gpsSpeedKmh,
                distanceMeters: displacement.distanceMeters,
                elapsedSeconds: displacement.elapsedSeconds,
                speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil
            )
        }

        guard derivedSpeedKmh >= normalizedThreshold,
              derivedSpeedKmh <= maximumActivationSpeedKmh,
              displacement.isTrusted else {
            return .insufficient(
                "Derived speed or displacement did not pass Smart quality thresholds.",
                speedKmh: derivedSpeedKmh,
                distanceMeters: displacement.distanceMeters,
                elapsedSeconds: displacement.elapsedSeconds,
                speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil
            )
        }

        return ActivationEvidence(
            kind: .trustedDerivedSpeed,
            speedKmh: derivedSpeedKmh,
            distanceMeters: displacement.distanceMeters,
            elapsedSeconds: displacement.elapsedSeconds,
            speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil,
            reason: "Derived speed is backed by trusted displacement."
        )
    }

    static func shouldActivate(speedKmh: Double?,
                               thresholdKmh: Int) -> Bool {
        guard let speedKmh,
              speedKmh.isFinite,
              speedKmh >= 0,
              speedKmh <= maximumActivationSpeedKmh else {
            return false
        }
        return speedKmh >= Double(SmartFrequentBackgroundSpeedThreshold.normalized(thresholdKmh))
    }

    static func canActivate(now: Date,
                            locationTimestamp: Date,
                            previousLocationUpdateAt: Date?,
                            inactivityWindow: TimeInterval,
                            evidenceKind: ActivationEvidenceKind = .trustedDerivedSpeed) -> Bool {
        guard inactivityWindow > 0 else { return false }
        guard now.timeIntervalSince(locationTimestamp) < inactivityWindow else {
            return false
        }

        switch evidenceKind {
        case .regionExit, .trustedGPSSpeed:
            return true
        case .trustedDerivedSpeed:
            guard let previousLocationUpdateAt else { return false }
            return now.timeIntervalSince(previousLocationUpdateAt) < inactivityWindow
        case .insufficient:
            return false
        }
    }

    static func shouldDeactivate(now: Date,
                                 lastLocationUpdateAt: Date?,
                                 lastRelevantMovementAt: Date?,
                                 inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0 else { return true }
        guard let lastLocationUpdateAt,
              now.timeIntervalSince(lastLocationUpdateAt) < inactivityWindow,
              let lastRelevantMovementAt else {
            return false
        }
        return now.timeIntervalSince(lastRelevantMovementAt) >= inactivityWindow
    }

    static func inactivityTimerAction(now: Date,
                                      lastLocationUpdateAt: Date?,
                                      lastRelevantMovementAt: Date?,
                                      inactivityWindow: TimeInterval) -> InactivityTimerAction {
        guard inactivityWindow > 0,
              inactivityWindow.isFinite,
              let lastLocationUpdateAt,
              let lastRelevantMovementAt,
              now.timeIntervalSince(lastLocationUpdateAt) < inactivityWindow else {
            return .none
        }

        let timeout = lastRelevantMovementAt.addingTimeInterval(inactivityWindow)
        return timeout <= now ? .expired : .schedule(timeout)
    }

    static func nextInactivityTimeout(lastLocationUpdateAt: Date?,
                                      lastRelevantMovementAt: Date?,
                                      inactivityWindow: TimeInterval) -> Date? {
        guard inactivityWindow > 0 else { return nil }
        return lastRelevantMovementAt?.addingTimeInterval(inactivityWindow)
    }

    static func movementDistanceThreshold(frequentDistanceFilterMeters: Int,
                                          from previousLocation: CLLocation?,
                                          to location: CLLocation) -> CLLocationDistance {
        let movementThreshold = CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        let accuracyThresholds = [previousLocation?.horizontalAccuracy, location.horizontalAccuracy]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 >= 0 }
        let accuracyNoiseThreshold = accuracyThresholds.max() ?? 0
        return max(movementThreshold, accuracyNoiseThreshold)
    }

    static func shouldConfirmMovement(distanceMeters: CLLocationDistance?,
                                      thresholdMeters: CLLocationDistance) -> Bool {
        guard let distanceMeters,
              distanceMeters.isFinite,
              thresholdMeters.isFinite,
              thresholdMeters >= 0 else {
            return false
        }
        return distanceMeters >= thresholdMeters
    }

    static func watchdogAction(phase: RuntimePhase,
                               smartEnabled: Bool,
                               manualFrequentEnabled: Bool,
                               lastFrequentCallbackAt: Date?,
                               runtimeStartedAt: Date?,
                               recoveryAttemptCount: Int,
                               now: Date,
                               interval: TimeInterval = runtimeWatchdogInterval,
                               maximumRecoveryAttempts: Int = maximumRuntimeRecoveryAttempts) -> WatchdogAction {
        guard phase != .waiting,
              smartEnabled,
              !manualFrequentEnabled,
              interval > 0 else {
            return .ignore
        }

        let reference = lastFrequentCallbackAt ?? runtimeStartedAt ?? now
        guard now.timeIntervalSince(reference) >= interval else {
            return .wait
        }

        return recoveryAttemptCount < maximumRecoveryAttempts ? .reassert : .deactivate
    }

    private struct DisplacementEvidence {
        let distanceMeters: CLLocationDistance?
        let elapsedSeconds: TimeInterval?
        let speedKmh: Double?
        let isTrusted: Bool
    }

    private static func gpsSpeedKmh(for location: CLLocation) -> Double? {
        guard location.speed >= 0,
              location.speed.isFinite else {
            return nil
        }
        return location.speed * 3.6
    }

    private static func displacementEvidence(from previousLocation: CLLocation?,
                                             to location: CLLocation,
                                             frequentDistanceFilterMeters: Int) -> DisplacementEvidence {
        guard let previousLocation,
              isUsableForDerivedSpeed(location),
              isUsableForDerivedSpeed(previousLocation) else {
            return DisplacementEvidence(
                distanceMeters: nil,
                elapsedSeconds: nil,
                speedKmh: nil,
                isTrusted: false
            )
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        let distance = location.distance(from: previousLocation)
        guard elapsed.isFinite,
              distance.isFinite,
              elapsed >= minimumDerivedSpeedElapsed,
              elapsed <= 30 * 60,
              distance >= 0 else {
            return DisplacementEvidence(
                distanceMeters: distance.isFinite ? distance : nil,
                elapsedSeconds: elapsed.isFinite ? elapsed : nil,
                speedKmh: nil,
                isTrusted: false
            )
        }

        let movementThreshold = CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        let combinedAccuracy = max(0, location.horizontalAccuracy) + max(0, previousLocation.horizontalAccuracy)
        let noiseAdjustedThreshold = max(movementThreshold, combinedAccuracy * 1.25)
        let isTrusted = distance >= noiseAdjustedThreshold
        return DisplacementEvidence(
            distanceMeters: distance,
            elapsedSeconds: elapsed,
            speedKmh: (distance / elapsed) * 3.6,
            isTrusted: isTrusted
        )
    }

    private static func isUsableForDerivedSpeed(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        location.timestamp.timeIntervalSince1970.isFinite &&
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= maximumUsableLocationAccuracy
    }

    private static func isUsableForFenceAnchor(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        CLLocationCoordinate2DIsValid(coordinate) &&
        location.timestamp.timeIntervalSince1970.isFinite &&
        location.horizontalAccuracy.isFinite &&
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= maximumUsableLocationAccuracy
    }
}

struct SmartFrequentBackgroundRuntimeMarker: Codable, Equatable {
    let phase: SmartFrequentBackgroundPolicy.RuntimePhase
    let confirmedAt: Date
    let lastRelevantMovementAt: Date?
    let activationNotificationDelivered: Bool
}

struct SmartFrequentBackgroundRuntimeMarkerStore {
    private static let markerKey = "miataru_smartFrequentBackgroundRuntimeMarker"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SmartFrequentBackgroundRuntimeMarker? {
        guard let data = defaults.data(forKey: Self.markerKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let marker = try? decoder.decode(SmartFrequentBackgroundRuntimeMarker.self, from: data),
              marker.phase == .confirmedActive else {
            clear()
            return nil
        }
        return marker
    }

    func save(_ marker: SmartFrequentBackgroundRuntimeMarker) {
        guard marker.phase == .confirmedActive else {
            clear()
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(marker) {
            defaults.set(data, forKey: Self.markerKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.markerKey)
    }

    func consume() -> SmartFrequentBackgroundRuntimeMarker? {
        let marker = load()
        clear()
        return marker
    }
}
