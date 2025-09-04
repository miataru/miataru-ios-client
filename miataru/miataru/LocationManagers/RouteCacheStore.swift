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

    struct RouteKey: Hashable {
        let deviceId: String
        let transportType: Int
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

    func get(for deviceId: String, transportType: Int) -> CachedRoute? {
        cache[RouteKey(deviceId: deviceId, transportType: transportType)]
    }

    func set(for deviceId: String,
             transportType: Int,
             route: MKRoute,
             userCoordinate: CLLocationCoordinate2D,
             deviceCoordinate: CLLocationCoordinate2D,
             userTimestamp: Date?,
             deviceTimestamp: Date?) {
        let key = RouteKey(deviceId: deviceId, transportType: transportType)
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
                 threshold: CLLocationDistance? = nil) -> Bool {
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
        return userDistance < limit && deviceDistance < limit
    }

    func clear(for deviceId: String) {
        cache = cache.filter { $0.key.deviceId != deviceId }
    }
}


