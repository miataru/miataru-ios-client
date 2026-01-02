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
    ///   - deviceTimestamp: The last known timestamp of the remote device location.
    ///   - knownDeviceSpeed: Optional remote device speed in meters per second.
    ///   - userTimestamp: The last known timestamp of the local device location.
    ///   - knownUserSpeed: Optional local device speed in meters per second.
    ///   - now: Reference time (defaults to Date()).
    ///   - isRouteReversed: Whether the route is reversed (device at start vs end).
    /// - Returns: (donePolyline, todoPolyline, ghostCoordinate, progress [0,1]) or nil if cannot compute.
    static func ghost(for route: MKRoute, deviceTimestamp: Date?, knownDeviceSpeed: Double?, userTimestamp: Date?, knownUserSpeed: Double?, now: Date = Date(), isRouteReversed: Bool = false) -> (MKPolyline, MKPolyline, CLLocationCoordinate2D, Double)? {
        guard route.distance > 0 else { return nil }
        let totalDistance = route.distance
        
        // Only use speeds above the threshold to filter out GPS noise from stationary devices
        let deviceSpeed = usableSpeed(knownDeviceSpeed)
        let userSpeed = usableSpeed(knownUserSpeed)
        
        // Pick the fastest available speed; choose its corresponding timestamp for elapsed time
        let chosenSpeed: Double?
        let chosenTimestamp: Date?
        if let deviceSpeed, let userSpeed {
            if deviceSpeed >= userSpeed {
                chosenSpeed = deviceSpeed
                chosenTimestamp = deviceTimestamp
            } else {
                chosenSpeed = userSpeed
                chosenTimestamp = userTimestamp
            }
        } else if let deviceSpeed {
            chosenSpeed = deviceSpeed
            chosenTimestamp = deviceTimestamp
        } else if let userSpeed {
            chosenSpeed = userSpeed
            chosenTimestamp = userTimestamp
        } else {
            chosenSpeed = nil
            chosenTimestamp = nil
        }
        
        let fallbackElapsed: TimeInterval
        if let deviceTimestamp {
            fallbackElapsed = now.timeIntervalSince(deviceTimestamp)
        } else if let userTimestamp {
            fallbackElapsed = now.timeIntervalSince(userTimestamp)
        } else {
            fallbackElapsed = 0
        }
        
        let distanceFromDevice: CLLocationDistance
        if let speed = chosenSpeed {
            if let ts = chosenTimestamp {
                let elapsed = max(0, now.timeIntervalSince(ts))
                distanceFromDevice = min(totalDistance, max(0, elapsed * speed))
            } else {
                // Without a timestamp we cannot project using speed; fall back to travel time
                let expected = route.expectedTravelTime
                let progress = expected > 0 ? max(0, min(1, fallbackElapsed / expected)) : 0
                distanceFromDevice = totalDistance * progress
            }
        } else {
            // Fallback: use expectedTravelTime proportion if available (device appears stationary)
            let expected = route.expectedTravelTime
            let progress = expected > 0 ? max(0, min(1, fallbackElapsed / expected)) : 0
            distanceFromDevice = totalDistance * progress
        }

        // Ghost calculation should ALWAYS be from the device's perspective
        // The device is always at the start of its journey, regardless of route direction
        // When isRouteReversed = true: device at start of polyline, travels forward
        // When isRouteReversed = false: device at end of polyline, travels forward (backward along polyline)
        let splitDistance: CLLocationDistance
        if isRouteReversed {
            // Device at start, travels forward: split at distanceFromDevice from start
            splitDistance = max(0, min(totalDistance, distanceFromDevice))
        } else {
            // Device at end, travels forward from its position (backward along polyline)
            // Split at distance from start: totalDistance - distanceFromDevice
            splitDistance = max(0, min(totalDistance, totalDistance - distanceFromDevice))
        }
        
        guard let (splitStartToSplit, splitSplitToEnd, ghost) = route.polyline.split(at: splitDistance) else { return nil }
        let progressValue = max(0, min(1, distanceFromDevice / totalDistance))
        
        // Return (done, todo, ghost, progress) from the device's perspective:
        // - done = segment device has already traveled from its starting position
        // - todo = segment device still needs to travel
        if isRouteReversed {
            // Device at start, travels forward along polyline
            // done = start to ghost, todo = ghost to end
            return (splitStartToSplit, splitSplitToEnd, ghost, progressValue)
        } else {
            // Device at end, travels forward from its position (backward along polyline)
            // From device's perspective at end:
            // - done = segment from end to ghost (which is splitSplitToEnd, reversed)
            // - todo = segment from ghost to start (which is splitStartToSplit)
            // Since device travels backward, we swap the segments
            return (splitSplitToEnd, splitStartToSplit, ghost, progressValue)
        }
    }

    private static func usableSpeed(_ speed: Double?) -> Double? {
        guard let speed, speed.isFinite else { return nil }
        return speed >= speedThreshold ? speed : nil
    }
}
