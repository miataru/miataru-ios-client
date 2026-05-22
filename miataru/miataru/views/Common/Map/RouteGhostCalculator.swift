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
/// since last device update and capped to [0,1], starting from the traveler's last known position
/// along the route rather than always from the route origin. Falls back to MKRoute.expectedTravelTime
/// otherwise. Speed values below the threshold are ignored to filter out GPS noise from stationary devices.
struct RouteGhostCalculator {
    /// Minimum speed threshold in m/s to consider device as moving.
    /// Values below this threshold are treated as GPS noise from stationary devices.
    /// Default: 1.5 m/s (5.4 km/h) - reasonable threshold to filter out GPS drift.
    static let speedThreshold: Double = 1.5 // m/s
    /// Calculates the ghost coordinate and polylines for completed/remaining segments.
    /// - Parameters:
    ///   - route: The MKRoute to traverse.
    ///   - deviceCoordinate: Latest known coordinate of the remote device.
    ///   - userCoordinate: Latest known coordinate of the local device.
    ///   - deviceTimestamp: The last known timestamp of the remote device location.
    ///   - knownDeviceSpeed: Optional remote device speed in meters per second.
    ///   - userTimestamp: The last known timestamp of the local device location.
    ///   - knownUserSpeed: Optional local device speed in meters per second.
    ///   - now: Reference time (defaults to Date()).
    ///   - isRouteFromDeviceToUser: true = standard route (device → user). false = reversed route (user → device).
    /// - Returns: (donePolyline, todoPolyline, ghostCoordinate, progress [0,1]) or nil if cannot compute.
    static func ghost(
        for route: MKRoute,
        deviceCoordinate: CLLocationCoordinate2D?,
        userCoordinate: CLLocationCoordinate2D?,
        deviceTimestamp: Date?,
        knownDeviceSpeed: Double?,
        userTimestamp: Date?,
        knownUserSpeed: Double?,
        now: Date = Date(),
        isRouteFromDeviceToUser: Bool = true
    ) -> (MKPolyline, MKPolyline, CLLocationCoordinate2D, Double)? {
        let totalDistance = route.polyline.geometryDistance
        guard totalDistance > 0 else { return nil }
        
        // Only use speeds above the threshold to filter out GPS noise from stationary devices
        let deviceSpeed = usableSpeed(knownDeviceSpeed)
        let userSpeed = usableSpeed(knownUserSpeed)
        
        // Use the speed/timestamp of the active traveler (device or user) to keep progress
        // aligned to route direction.
        let primarySpeed = isRouteFromDeviceToUser ? deviceSpeed : userSpeed
        let primaryTimestamp = isRouteFromDeviceToUser ? deviceTimestamp : userTimestamp
        let secondaryTimestamp = isRouteFromDeviceToUser ? userTimestamp : deviceTimestamp
        
        let fallbackElapsed: TimeInterval
        if let primaryTimestamp {
            fallbackElapsed = now.timeIntervalSince(primaryTimestamp)
        } else if let secondaryTimestamp {
            fallbackElapsed = now.timeIntervalSince(secondaryTimestamp)
        } else {
            fallbackElapsed = 0
        }

        // Determine the base distance along the route from its start to the traveler's
        // last known position on the route. This ensures projected progress starts from
        // the current device/user location instead of always from the route origin.
        let baseCoordinate: CLLocationCoordinate2D? = {
            if isRouteFromDeviceToUser {
                return deviceCoordinate
            } else {
                return userCoordinate
            }
        }()

        let baseDistanceFromStart: CLLocationDistance = {
            guard let baseCoordinate else { return 0 }
            let basePoint = MKMapPoint(baseCoordinate)
            if let remaining = route.polyline.remainingDistance(toEndFrom: basePoint) {
                // Clamp to [0, totalDistance] to guard against numerical drift.
                let fromStart = max(0, min(totalDistance, totalDistance - remaining))
                return fromStart
            }
            return 0
        }()

        let distanceFromStart: CLLocationDistance
        if let speed = primarySpeed {
            if let ts = primaryTimestamp {
                let elapsed = max(0, now.timeIntervalSince(ts))
                let projected = max(0, elapsed * speed)
                distanceFromStart = min(totalDistance, max(0, baseDistanceFromStart + projected))
            } else {
                // Without a timestamp we cannot project using speed; fall back to travel time
                let expected = route.expectedTravelTime
                let progressDelta = expected > 0 ? max(0, min(1, fallbackElapsed / expected)) : 0
                distanceFromStart = min(totalDistance, max(0, baseDistanceFromStart + totalDistance * progressDelta))
            }
        } else {
            // Fallback: use expectedTravelTime proportion if available (start appears stationary)
            let expected = route.expectedTravelTime
            let progressDelta = expected > 0 ? max(0, min(1, fallbackElapsed / expected)) : 0
            distanceFromStart = min(totalDistance, max(0, baseDistanceFromStart + totalDistance * progressDelta))
        }

        // Ghost calculation follows the active route direction (start -> end).
        let splitDistance = max(0, min(totalDistance, distanceFromStart))
        
        guard let (splitStartToSplit, splitSplitToEnd, ghost) = route.polyline.split(at: splitDistance) else { return nil }
        let progressValue = max(0, min(1, distanceFromStart / totalDistance))
        
        // Return (done, todo, ghost, progress) from route start to end.
        return (splitStartToSplit, splitSplitToEnd, ghost, progressValue)
    }

    private static func usableSpeed(_ speed: Double?) -> Double? {
        guard let speed, speed.isFinite else { return nil }
        return speed >= speedThreshold ? speed : nil
    }
}

enum RouteGhostPresentationPolicy {
    static func shouldShowGhost(
        isRouteFromDeviceToUser: Bool,
        progress: Double,
        minimumProgress: Double,
        routeStartDate: Date?,
        expectedTravelTime: TimeInterval,
        now: Date
    ) -> Bool {
        guard isRouteFromDeviceToUser else { return false }
        guard progress > minimumProgress, progress < 1 else { return false }
        guard expectedTravelTime > 0, let routeStartDate else { return true }
        return now.timeIntervalSince(routeStartDate) < expectedTravelTime
    }
}

private extension MKPolyline {
    var geometryDistance: CLLocationDistance {
        guard pointCount > 1 else { return 0 }
        let points = points()
        var distance: CLLocationDistance = 0
        for index in 0..<(pointCount - 1) {
            distance += points[index].distance(to: points[index + 1])
        }
        return distance
    }
}
