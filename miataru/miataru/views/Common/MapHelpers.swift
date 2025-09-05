/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MapHelpers.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import MapKit
import SwiftUI
import CoreLocation

// Helper function for MapStyle
@available(iOS 17.0, *)
func mapStyleFromSettings(_ mapType: Int) -> MapStyle {
    switch mapType {
    case 2:
        return .hybrid(elevation: .automatic)
    case 3:
        return .imagery(elevation: .automatic)
    default:
        return .standard(elevation: .automatic)
    }
}

// Helper function for zoom level (in km)
func spanForZoomLevel(_ zoomLevel: Int) -> MKCoordinateSpan {
    // 1° latitude ≈ 111 km
    let km = Double(zoomLevel)
    let delta = km / 111.0
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
}

// Helper function to calculate current zoom level from span
func currentZoomLevelFromSpan(_ span: MKCoordinateSpan) -> Int {
    // Average of latitude and longitude delta
    let avgDelta = (span.latitudeDelta + span.longitudeDelta) / 2.0
    // Convert back to km: 1° ≈ 111 km
    let km = avgDelta * 111.0
    return Int(round(km))
}

/// Returns a relative time string for a date (e.g. "2 minutes ago" or "now")
func relativeTimeString(
    from date: Date?,
    to now: Date = Date(),
    unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full,
    timeConsideredNow: TimeInterval = 10
) -> String {
    guard let date = date else { return "–" }
    let diff = now.timeIntervalSince(date)
    if date > now {
        return NSLocalizedString("relative_time_now", comment: "Indicates that the location update just happened or is happening right now in a relative time on the map marker.")
    } else if diff < timeConsideredNow {
        return NSLocalizedString("relative_time_now", comment: "Indicates that the location update just happened or is happening right now in a relative time on the map marker.")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = unitsStyle
    return formatter.localizedString(for: date, relativeTo: now)
}

/// Splits a polyline at the given distance from its start and returns the
/// traversed and remaining segments plus the interpolated coordinate.
extension MKPolyline {
    func split(at distance: CLLocationDistance) -> (MKPolyline, MKPolyline, CLLocationCoordinate2D)? {
        guard pointCount > 1 else { return nil }

        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))

        var traveled: [CLLocationCoordinate2D] = [coords[0]]
        var remaining: [CLLocationCoordinate2D] = coords
        var accumulated: CLLocationDistance = 0

        for i in 1..<coords.count {
            let start = MKMapPoint(coords[i - 1])
            let end = MKMapPoint(coords[i])
            let segment = start.distance(to: end)

            if accumulated + segment >= distance {
                let ratio = segment > 0 ? (distance - accumulated) / segment : 0
                let interp = CLLocationCoordinate2D(
                    latitude: coords[i - 1].latitude + (coords[i].latitude - coords[i - 1].latitude) * ratio,
                    longitude: coords[i - 1].longitude + (coords[i].longitude - coords[i - 1].longitude) * ratio
                )
                traveled.append(interp)
                remaining[0] = interp
                let traveledPolyline = MKPolyline(coordinates: traveled, count: traveled.count)
                let remainingPolyline = MKPolyline(coordinates: remaining, count: remaining.count)
                return (traveledPolyline, remainingPolyline, interp)
            }

            traveled.append(coords[i])
            remaining.remove(at: 0)
            accumulated += segment
        }

        return nil
    }
}

// MARK: - Route Ghost Calculator
/// Computes a ghost/predicted position along a route, optionally weighting by known device speed.
/// If speed is provided (in m/s) and timestamp is available, the progress is adjusted from time
/// since last device update and capped to [0,1]. Falls back to MKRoute.expectedTravelTime otherwise.
struct RouteGhostCalculator {
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

        let useSpeed = (knownDeviceSpeed ?? 0) > 0 ? max(0, knownDeviceSpeed ?? 0) : 0
        let distanceFromDevice: CLLocationDistance
        if useSpeed > 0 {
            // Distance advanced since last update using speed
            distanceFromDevice = min(totalDistance, max(0, elapsed * useSpeed))
        } else {
            // Fallback: use expectedTravelTime proportion if available
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
