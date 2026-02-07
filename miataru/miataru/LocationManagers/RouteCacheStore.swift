/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * RouteCacheStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-09-04.
 */

import Foundation
import MapKit
import CoreLocation

final class RouteCacheStore: ObservableObject {
    static let shared = RouteCacheStore()

    /// Cache key. isRouteReversed: false = reversed route (user→device), true = non-reversed (device→user).
    struct RouteKey: Hashable {
        let deviceId: String
        let transportType: Int
        let isRouteReversed: Bool
    }

    struct CachedRoute {
        let route: MKRoute
        let userCoordinate: CLLocationCoordinate2D
        let deviceCoordinate: CLLocationCoordinate2D
        let userTimestamp: Date?
        let deviceTimestamp: Date?
    }

    @Published private var cache: [RouteKey: CachedRoute] = [:]

    private let defaultDistanceThreshold: CLLocationDistance = 100 // meters

    func get(for deviceId: String, transportType: Int, isRouteReversed: Bool) -> CachedRoute? {
        cache[RouteKey(deviceId: deviceId, transportType: transportType, isRouteReversed: isRouteReversed)]
    }

    func set(for deviceId: String,
             transportType: Int,
             isRouteReversed: Bool,
             route: MKRoute,
             userCoordinate: CLLocationCoordinate2D,
             deviceCoordinate: CLLocationCoordinate2D,
             userTimestamp: Date?,
             deviceTimestamp: Date?) {
        let key = RouteKey(deviceId: deviceId, transportType: transportType, isRouteReversed: isRouteReversed)
        let value = CachedRoute(route: route,
                                userCoordinate: userCoordinate,
                                deviceCoordinate: deviceCoordinate,
                                userTimestamp: userTimestamp,
                                deviceTimestamp: deviceTimestamp)
        cache[key] = value
    }

    func isValid(cached: CachedRoute,
                 currentUserCoordinate: CLLocationCoordinate2D,
                 currentDeviceCoordinate: CLLocationCoordinate2D,
                 threshold: CLLocationDistance? = nil,
                 offRouteThreshold: CLLocationDistance? = nil) -> Bool {
        let limit = threshold ?? defaultDistanceThreshold

        let previousUserLocation = CLLocation(latitude: cached.userCoordinate.latitude,
                                              longitude: cached.userCoordinate.longitude)
        let currentUserLocation = CLLocation(latitude: currentUserCoordinate.latitude,
                                             longitude: currentUserCoordinate.longitude)
        let userDistance = previousUserLocation.distance(from: currentUserLocation)

        let previousDeviceLocation = CLLocation(latitude: cached.deviceCoordinate.latitude,
                                                longitude: cached.deviceCoordinate.longitude)
        let currentDeviceLocation = CLLocation(latitude: currentDeviceCoordinate.latitude,
                                               longitude: currentDeviceCoordinate.longitude)
        let deviceDistance = previousDeviceLocation.distance(from: currentDeviceLocation)

        // Cache is valid only if both ends moved less than the threshold
        guard userDistance < limit && deviceDistance < limit else {
            return false
        }
        guard let offRouteLimit = offRouteThreshold else {
            return true
        }
        return !isOffRoute(route: cached.route, userCoordinate: currentUserCoordinate, threshold: offRouteLimit)
    }

    private func isOffRoute(route: MKRoute,
                            userCoordinate: CLLocationCoordinate2D,
                            threshold: CLLocationDistance) -> Bool {
        let polyline = route.polyline
        guard polyline.pointCount > 1 else { return false }

        let userPoint = MKMapPoint(userCoordinate)
        let points = polyline.points()
        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(polyline.pointCount - 1) {
            let distance = distanceFromPoint(userPoint, toSegmentStart: points[index], end: points[index + 1])
            minDistance = min(minDistance, distance)
            if minDistance <= threshold {
                return false
            }
        }
        return minDistance > threshold
    }

    private func distanceFromPoint(_ point: MKMapPoint,
                                   toSegmentStart start: MKMapPoint,
                                   end: MKMapPoint) -> CLLocationDistance {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return point.distance(to: start)
        }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let clamped = max(0, min(1, t))
        let projection = MKMapPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
        return point.distance(to: projection)
    }

    func clear(for deviceId: String) {
        cache = cache.filter { $0.key.deviceId != deviceId }
    }
}


