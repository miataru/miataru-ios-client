/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationRouteRefreshPolicyTests.swift
 * miataruTests
 *
 * Created by Daniel Kirstenpfad on 2026-02-26.
 */

import Testing
import CoreLocation
@testable import miataru

struct NavigationRouteRefreshPolicyTests {
    @Test("Refresh when target moved while user is on route")
    func refreshWhenTargetMovedOnRoute() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: true,
            hasRoute: true,
            isUserOffRoute: false,
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.895, longitude: 11.020),
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.893, longitude: 11.020),
            targetMovementThreshold: 100
        )

        #expect(shouldRefresh == true)
    }

    @Test("No refresh when auto update is disabled")
    func noRefreshWhenAutoUpdateDisabled() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: false,
            hasRoute: true,
            isUserOffRoute: true,
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.895, longitude: 11.020),
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.893, longitude: 11.020),
            targetMovementThreshold: 100
        )

        #expect(shouldRefresh == false)
    }

    @Test("Refresh when no route exists")
    func refreshWhenNoRouteExists() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: true,
            hasRoute: false,
            isUserOffRoute: false,
            currentDeviceCoordinate: nil,
            lastRouteDeviceCoordinate: nil,
            targetMovementThreshold: 100
        )

        #expect(shouldRefresh == true)
    }

    @Test("No refresh when on route and target movement is below threshold")
    func noRefreshWhenTargetMovementBelowThreshold() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: true,
            hasRoute: true,
            isUserOffRoute: false,
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.8931, longitude: 11.0200),
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.8930, longitude: 11.0200),
            targetMovementThreshold: 100
        )

        #expect(shouldRefresh == false)
    }
}
