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

    @Test("Refresh when user is off route regardless of target movement")
    func refreshWhenUserOffRoute() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: true,
            hasRoute: true,
            isUserOffRoute: true,
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: 11.0),
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: 11.0),
            targetMovementThreshold: 100
        )
        #expect(shouldRefresh == true)
    }

    @Test("No refresh if target did not move beyond threshold")
    func noRefreshWhenTargetDidNotMove() async throws {
        let shouldRefresh = NavigationRouteRefreshPolicy.shouldRefreshRoute(
            isAutoRouteUpdateEnabled: true,
            hasRoute: true,
            isUserOffRoute: false,
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0001, longitude: 11.0001),
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0000, longitude: 11.0000),
            targetMovementThreshold: 1000 // ~> small move should be below 1km
        )
        #expect(shouldRefresh == false)
    }

    @Test("hasTargetMovedSignificantly returns false for missing coordinates")
    func hasTargetMovedSignificantlyMissing() async throws {
        // Missing current
        let missingCurrent = NavigationRouteRefreshPolicy.hasTargetMovedSignificantly(
            currentDeviceCoordinate: nil,
            lastRouteDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: 11.0),
            threshold: 10
        )
        #expect(missingCurrent == false)
        // Missing last
        let missingLast = NavigationRouteRefreshPolicy.hasTargetMovedSignificantly(
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 49.0, longitude: 11.0),
            lastRouteDeviceCoordinate: nil,
            threshold: 10
        )
        #expect(missingLast == false)
    }
}
