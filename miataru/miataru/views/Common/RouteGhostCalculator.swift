/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * RouteGhostCalculator.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import Foundation
import MapKit
import CoreLocation

// MARK: - Route Ghost Calculator
/// Computes a ghost/predicted position along a route, optionally weighting by known device speed.
/// If speed is provided (in m/s) and timestamp is available, the progress is adjusted from time
/// since last device update and capped to [0,1]. Falls back to MKRoute.expectedTravelTime otherwise.
/// Speed values below the threshold are ignored to filter out GPS noise from stationary devices.
struct RouteGhostCalculator {
    /// Minimum speed threshold in m/s to consider device as moving.
    /// Values below this threshold are treated as GPS noise from stationary devices.
    /// Default: 1.5 m/s (5.4 km/h) - reasonable threshold to filter out GPS drift.
    static let speedThreshold: Double = 1.5 // m/s
    /// Calculates the ghost coordinate and polylines for completed/remaining segments.
    /// - Parameters:
    ///   - route: The MKRoute to traverse.
    ///   - deviceTimestamp: The last known timestamp of the device location.
    ///   - knownDeviceSpeed: Optional speed in meters per second. If provided and > 0, used to compute distance.
    ///   - now: Reference time (defaults to Date()).
    /// - Returns: (donePolyline, todoPolyline, ghostCoordinate, progress [0,1]) or nil if cannot compute.
    static func ghost(for route: MKRoute, deviceTimestamp: Date?, knownDeviceSpeed: Double?, now: Date = Date()) -> (MKPolyline, MKPolyline, CLLocationCoordinate2D, Double)? {
        guard route.distance > 0 else { return nil }
        let elapsed = deviceTimestamp.map { now.timeIntervalSince($0) } ?? 0
        let totalDistance = route.distance

        // Only use speed if it's above the threshold to filter out GPS noise from stationary devices
        // GPS can show 2-4 km/h even for stationary devices due to accuracy limitations
        let useSpeed = (knownDeviceSpeed ?? 0) >= speedThreshold ? max(0, knownDeviceSpeed ?? 0) : 0
        let distanceFromDevice: CLLocationDistance
        if useSpeed > 0 {
            // Distance advanced since last update using speed (device is actually moving)
            distanceFromDevice = min(totalDistance, max(0, elapsed * useSpeed))
        } else {
            // Fallback: use expectedTravelTime proportion if available (device appears stationary)
            let expected = route.expectedTravelTime
            let progress = expected > 0 ? max(0, min(1, elapsed / expected)) : 0
            distanceFromDevice = totalDistance * progress
        }

        let splitDistance = max(totalDistance - distanceFromDevice, 0)
        guard let (todo, done, ghost) = route.polyline.split(at: splitDistance) else { return nil }
        let progressValue = max(0, min(1, distanceFromDevice / totalDistance))
        return (done, todo, ghost, progressValue)
    }
}
