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

/// Returns a formatted speed string (e.g. "45 km/h"). When `minSpeedKmh` is set (default 10),
/// returns nil if speed is at or below that threshold; use 0 to show any positive speed (e.g. in history).
func mapSpeedLabelText(speedMetersPerSecond: Double?, minSpeedKmh: Double = 10) -> String? {
    guard let speedMetersPerSecond, speedMetersPerSecond > 0 else { return nil }
    let speedKilometersPerHour = speedMetersPerSecond * 3.6
    guard speedKilometersPerHour > minSpeedKmh else { return nil }

    let usesMetric: Bool
    if #available(iOS 16.0, *) {
        usesMetric = Locale.current.measurementSystem == .metric
    } else {
        usesMetric = Locale.current.usesMetricSystem
    }

    let value: Double
    if usesMetric {
        value = speedKilometersPerHour
    } else {
        value = speedKilometersPerHour / 1.609344
    }

    let numberFormatter = NumberFormatter()
    numberFormatter.locale = .current
    numberFormatter.maximumFractionDigits = 0
    numberFormatter.minimumFractionDigits = 0
    guard let numberString = numberFormatter.string(from: NSNumber(value: value)) else {
        return nil
    }

    let unitString = usesMetric ? "km/h" : "mph"
    return "\(numberString) \(unitString)"
}

/// Returns a formatted timezone offset string (e.g., "+2" or "-5") comparing device timezone to local timezone
func timezoneOffsetString(deviceTimeZone: TimeZone?) -> String? {
    guard let deviceTimeZone = deviceTimeZone else { return nil }
    let localTimeZone = TimeZone.current
    
    let now = Date()
    let deviceOffset = deviceTimeZone.secondsFromGMT(for: now)
    let localOffset = localTimeZone.secondsFromGMT(for: now)
    let offsetDifference = deviceOffset - localOffset
    
    // Convert seconds to hours
    let hoursDifference = offsetDifference / 3600
    
    // Format as "+2" or "-5" etc.
    if hoursDifference == 0 {
        return nil // Don't show if same timezone
    } else if hoursDifference > 0 {
        return "+\(hoursDifference)"
    } else {
        return "\(hoursDifference)" // Negative sign already included
    }
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

extension MKPolyline {
    func closestDistance(to point: MKMapPoint) -> CLLocationDistance? {
        guard pointCount > 0 else { return nil }
        let points = self.points()
        if pointCount == 1 {
            return point.distance(to: points[0])
        }
        var closest = CLLocationDistance.greatestFiniteMagnitude
        for index in 0..<(pointCount - 1) {
            let start = points[index]
            let end = points[index + 1]
            let distance = distanceFrom(point, toSegmentBetween: start, end)
            if distance < closest {
                closest = distance
            }
        }
        return closest.isFinite ? closest : nil
    }

    private func distanceFrom(_ point: MKMapPoint, toSegmentBetween start: MKMapPoint, _ end: MKMapPoint) -> CLLocationDistance {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return point.distance(to: start)
        }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let clamped = max(0, min(1, t))
        let projected = MKMapPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
        return point.distance(to: projected)
    }
}

extension MKPolyline {
    func remainingDistance(toEndFrom point: MKMapPoint) -> CLLocationDistance? {
        guard pointCount > 0 else { return nil }
        let points = self.points()
        if pointCount == 1 {
            return point.distance(to: points[0])
        }

        var bestIndex: Int?
        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestProjected: MKMapPoint?

        for index in 0..<(pointCount - 1) {
            let start = points[index]
            let end = points[index + 1]
            let (projected, distance) = projectedPoint(from: point, toSegmentBetween: start, end)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
                bestProjected = projected
            }
        }

        guard let bestIndex, let bestProjected else { return nil }
        var remaining = bestProjected.distance(to: points[bestIndex + 1])
        if bestIndex + 1 < pointCount - 1 {
            for index in (bestIndex + 1)..<(pointCount - 1) {
                remaining += points[index].distance(to: points[index + 1])
            }
        }
        return remaining
    }

    private func projectedPoint(from point: MKMapPoint, toSegmentBetween start: MKMapPoint, _ end: MKMapPoint) -> (MKMapPoint, CLLocationDistance) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return (start, point.distance(to: start))
        }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let clamped = max(0, min(1, t))
        let projected = MKMapPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
        return (projected, point.distance(to: projected))
    }
}
