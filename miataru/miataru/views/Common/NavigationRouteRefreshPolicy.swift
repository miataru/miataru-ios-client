/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationRouteRefreshPolicy.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-02-26.
 */

import Foundation
import CoreLocation

enum NavigationRouteRefreshPolicy {
    static func shouldRefreshRoute(
        isAutoRouteUpdateEnabled: Bool,
        hasRoute: Bool,
        isUserOffRoute: Bool,
        currentDeviceCoordinate: CLLocationCoordinate2D?,
        lastRouteDeviceCoordinate: CLLocationCoordinate2D?,
        targetMovementThreshold: CLLocationDistance
    ) -> Bool {
        guard isAutoRouteUpdateEnabled else { return false }
        if !hasRoute { return true }
        if isUserOffRoute { return true }
        return hasTargetMovedSignificantly(
            currentDeviceCoordinate: currentDeviceCoordinate,
            lastRouteDeviceCoordinate: lastRouteDeviceCoordinate,
            threshold: targetMovementThreshold
        )
    }

    static func hasTargetMovedSignificantly(
        currentDeviceCoordinate: CLLocationCoordinate2D?,
        lastRouteDeviceCoordinate: CLLocationCoordinate2D?,
        threshold: CLLocationDistance
    ) -> Bool {
        guard let currentDeviceCoordinate, let lastRouteDeviceCoordinate else { return false }
        let previousLocation = CLLocation(latitude: lastRouteDeviceCoordinate.latitude, longitude: lastRouteDeviceCoordinate.longitude)
        let currentLocation = CLLocation(latitude: currentDeviceCoordinate.latitude, longitude: currentDeviceCoordinate.longitude)
        return previousLocation.distance(from: currentLocation) >= threshold
    }
}
