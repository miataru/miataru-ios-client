import Testing
import MapKit
import CoreLocation
@testable import miataru

@Suite("RouteCacheStore tests")
struct RouteCacheStoreTests {

    private func route(from coords: [CLLocationCoordinate2D]) -> MKRoute {
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        let distance = length(of: poly)
        return FakeRoute(polyline: poly, distance: distance, expectedTravelTime: 60)
    }

    @Test("Set and get cached route by key")
    func testSetGet() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.005)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: true,
            route: route,
            userCoordinate: CLLocationCoordinate2D(latitude: 0.001, longitude: 0),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.005),
            userTimestamp: Date(),
            deviceTimestamp: Date()
        )
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: true)
        #expect(got != nil)
        #expect(got?.route.distance == route.distance)
    }

    @Test("isValid returns true when both endpoints moved less than threshold and on-route")
    func testIsValidWithinThresholdOnRoute() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: false,
            route: route,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.009),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        let valid = cache.isValid(
            cached: got,
            currentUserCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0012),
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0088),
            threshold: 100, // ~100m
            offRouteThreshold: 25
        )
        #expect(valid == true)
    }

    @Test("isValid returns false when either endpoint moved beyond threshold")
    func testIsValidBeyondThreshold() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: true,
            route: route,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.002),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.008),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: true)!
        // Move device far away (> threshold)
        let valid = cache.isValid(
            cached: got,
            currentUserCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0025),
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.0200),
            threshold: 100, // 100m
            offRouteThreshold: 25
        )
        #expect(valid == false)
    }

    @Test("isValid returns false when user is off route beyond offRouteThreshold")
    func testIsValidOffRouteInvalidation() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: false,
            route: route,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.009),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        // Choose a point ~200m north of the route
        let invalid = cache.isValid(
            cached: got,
            currentUserCoordinate: CLLocationCoordinate2D(latitude: 0.002, longitude: 0.005),
            currentDeviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.009),
            threshold: 100,
            offRouteThreshold: 25
        )
        #expect(invalid == false)
    }

    @Test("Keys are isolated by transportType")
    func testKeyIsolationByTransportType() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let routeA = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.004)
        ])
        let routeB = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0.006),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.012)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: true,
            route: routeA,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.003),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        cache.set(
            for: deviceId,
            transportType: 3,
            isRouteReversed: true,
            route: routeB,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.007),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.011),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let gotA = cache.get(for: deviceId, transportType: 2, isRouteReversed: true)
        let gotB = cache.get(for: deviceId, transportType: 3, isRouteReversed: true)
        #expect(gotA?.route.distance == routeA.distance)
        #expect(gotB?.route.distance == routeB.distance)
    }

    @Test("Keys are isolated by isRouteReversed")
    func testKeyIsolationByRouteDirection() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let routeForward = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.005)
        ])
        let routeReverse = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0.005),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.010)
        ])
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: false,
            route: routeForward,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.001),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.004),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: true,
            route: routeReverse,
            userCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.006),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0.009),
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let gotForward = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)
        let gotReverse = cache.get(for: deviceId, transportType: 2, isRouteReversed: true)
        #expect(gotForward?.route.distance == routeForward.distance)
        #expect(gotReverse?.route.distance == routeReverse.distance)
    }

    @Test("clear(for:) removes only the specified device's entries")
    func testClearRemovesOnlySpecifiedDevice() async throws {
        let cache = RouteCacheStore.shared
        let deviceA = "TEST_DEVICE_A_\(UUID().uuidString)"
        let deviceB = "TEST_DEVICE_B_\(UUID().uuidString)"
        let routeA = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.003)
        ])
        let routeB = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0.004),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.008)
        ])
        cache.set(for: deviceA, transportType: 2, isRouteReversed: true, route: routeA, userCoordinate: .init(latitude: 0, longitude: 0.001), deviceCoordinate: .init(latitude: 0, longitude: 0.002), userTimestamp: nil, deviceTimestamp: nil)
        cache.set(for: deviceB, transportType: 2, isRouteReversed: true, route: routeB, userCoordinate: .init(latitude: 0, longitude: 0.005), deviceCoordinate: .init(latitude: 0, longitude: 0.007), userTimestamp: nil, deviceTimestamp: nil)
        cache.clear(for: deviceA)
        let gotA = cache.get(for: deviceA, transportType: 2, isRouteReversed: true)
        let gotB = cache.get(for: deviceB, transportType: 2, isRouteReversed: true)
        #expect(gotA == nil)
        #expect(gotB != nil)
    }

    @Test("clear(for:) removes all variants (transport and direction) for a device")
    func testClearRemovesAllVariantsForDevice() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let r1 = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.003)])
        let r2 = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0.003), CLLocationCoordinate2D(latitude: 0, longitude: 0.006)])
        cache.set(for: deviceId, transportType: 1, isRouteReversed: false, route: r1, userCoordinate: .init(latitude: 0, longitude: 0.001), deviceCoordinate: .init(latitude: 0, longitude: 0.002), userTimestamp: nil, deviceTimestamp: nil)
        cache.set(for: deviceId, transportType: 1, isRouteReversed: true, route: r2, userCoordinate: .init(latitude: 0, longitude: 0.004), deviceCoordinate: .init(latitude: 0, longitude: 0.005), userTimestamp: nil, deviceTimestamp: nil)
        cache.set(for: deviceId, transportType: 2, isRouteReversed: false, route: r1, userCoordinate: .init(latitude: 0, longitude: 0.001), deviceCoordinate: .init(latitude: 0, longitude: 0.002), userTimestamp: nil, deviceTimestamp: nil)
        cache.set(for: deviceId, transportType: 2, isRouteReversed: true, route: r2, userCoordinate: .init(latitude: 0, longitude: 0.004), deviceCoordinate: .init(latitude: 0, longitude: 0.005), userTimestamp: nil, deviceTimestamp: nil)
        cache.clear(for: deviceId)
        #expect(cache.get(for: deviceId, transportType: 1, isRouteReversed: false) == nil)
        #expect(cache.get(for: deviceId, transportType: 1, isRouteReversed: true) == nil)
        #expect(cache.get(for: deviceId, transportType: 2, isRouteReversed: false) == nil)
        #expect(cache.get(for: deviceId, transportType: 2, isRouteReversed: true) == nil)
    }

    @Test("isValid returns false at the boundary when movement equals threshold")
    func testIsValidBoundaryEqualThresholdIsInvalid() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ])
        let cachedUser = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        let cachedDevice = CLLocationCoordinate2D(latitude: 0, longitude: 0.009)
        cache.set(
            for: deviceId,
            transportType: 2,
            isRouteReversed: false,
            route: route,
            userCoordinate: cachedUser,
            deviceCoordinate: cachedDevice,
            userTimestamp: nil,
            deviceTimestamp: nil
        )
        let currentUser = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let threshold = CLLocation(latitude: cachedUser.latitude, longitude: cachedUser.longitude)
            .distance(from: CLLocation(latitude: currentUser.latitude, longitude: currentUser.longitude))
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        let valid = cache.isValid(
            cached: got,
            currentUserCoordinate: currentUser,
            currentDeviceCoordinate: cachedDevice,
            threshold: threshold,
            offRouteThreshold: nil
        )
        #expect(valid == false)
    }

    @Test("Default validity ignores off-route when offRouteThreshold is nil")
    func testIsValidDefaultIgnoresOffRoute() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        // Route along equator, but user far north; movement small -> valid if offRouteThreshold is nil
        let route = route(from: [
            CLLocationCoordinate2D(latitude: 0, longitude: 0),
            CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        ])
        let cachedUser = CLLocationCoordinate2D(latitude: 1.0, longitude: 0.001)
        let currentUser = CLLocationCoordinate2D(latitude: 1.0002, longitude: 0.001)
        cache.set(for: deviceId, transportType: 2, isRouteReversed: false, route: route, userCoordinate: cachedUser, deviceCoordinate: .init(latitude: 0, longitude: 0.009), userTimestamp: nil, deviceTimestamp: nil)
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        let valid = cache.isValid(cached: got, currentUserCoordinate: currentUser, currentDeviceCoordinate: .init(latitude: 0, longitude: 0.009), threshold: 500, offRouteThreshold: nil)
        #expect(valid == true)
    }

    @Test("Single-point route is never considered off-route in validity check")
    func testIsValidSinglePointRouteNotOffRoute() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        // Single-point route
        let single = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0)])
        cache.set(for: deviceId, transportType: 2, isRouteReversed: false, route: single, userCoordinate: .init(latitude: 0.5, longitude: 0.5), deviceCoordinate: .init(latitude: 0, longitude: 0), userTimestamp: nil, deviceTimestamp: nil)
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        let valid = cache.isValid(cached: got, currentUserCoordinate: .init(latitude: 0.5001, longitude: 0.5), currentDeviceCoordinate: .init(latitude: 0, longitude: 0), threshold: 1000, offRouteThreshold: 25)
        #expect(valid == true)
    }

    @Test("get returns nil for missing key or mismatched parameters")
    func testGetReturnsNilForMissingKey() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.005)])
        cache.set(for: deviceId, transportType: 2, isRouteReversed: true, route: route, userCoordinate: .init(latitude: 0, longitude: 0.001), deviceCoordinate: .init(latitude: 0, longitude: 0.004), userTimestamp: nil, deviceTimestamp: nil)
        #expect(cache.get(for: "UNKNOWN_\(UUID().uuidString)", transportType: 2, isRouteReversed: true) == nil)
        #expect(cache.get(for: deviceId, transportType: 3, isRouteReversed: true) == nil)
        #expect(cache.get(for: deviceId, transportType: 2, isRouteReversed: false) == nil)
    }

    @Test("Setting the same key twice overwrites the cached route")
    func testOverwriteUpdatesCachedRoute() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route1 = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.002)])
        let route2 = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.008)])
        cache.set(for: deviceId, transportType: 2, isRouteReversed: true, route: route1, userCoordinate: .init(latitude: 0, longitude: 0.0005), deviceCoordinate: .init(latitude: 0, longitude: 0.0015), userTimestamp: nil, deviceTimestamp: nil)
        cache.set(for: deviceId, transportType: 2, isRouteReversed: true, route: route2, userCoordinate: .init(latitude: 0, longitude: 0.0005), deviceCoordinate: .init(latitude: 0, longitude: 0.0015), userTimestamp: nil, deviceTimestamp: nil)
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: true)
        #expect(got?.route.distance == route2.distance)
    }

    @Test("isValid returns true with very large threshold despite large movement")
    func testIsValidWithLargeThresholdTrue() async throws {
        let cache = RouteCacheStore.shared
        let deviceId = "TEST_DEVICE_\(UUID().uuidString)"
        let route = route(from: [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 0.01)])
        cache.set(for: deviceId, transportType: 2, isRouteReversed: false, route: route, userCoordinate: .init(latitude: 0, longitude: 0), deviceCoordinate: .init(latitude: 0, longitude: 0.01), userTimestamp: nil, deviceTimestamp: nil)
        let got = cache.get(for: deviceId, transportType: 2, isRouteReversed: false)!
        // Move user ~0.2° in lon (~22km at equator) but set a huge threshold
        let valid = cache.isValid(cached: got, currentUserCoordinate: .init(latitude: 0, longitude: 0.2), currentDeviceCoordinate: .init(latitude: 0, longitude: 0.01), threshold: 1_000_000, offRouteThreshold: nil)
        #expect(valid == true)
    }

    // MARK: - Helpers
    private func length(of poly: MKPolyline) -> CLLocationDistance {
        guard poly.pointCount > 1 else { return 0 }
        let pts = poly.points()
        var sum: CLLocationDistance = 0
        for i in 0..<(poly.pointCount - 1) {
            sum += pts[i].distance(to: pts[i + 1])
        }
        return sum
    }
}

// Reuse the FakeRoute shim from RouteGhostCalculatorTests
private final class FakeRoute: MKRoute {
    private let _polyline: MKPolyline
    private let _distance: CLLocationDistance
    private let _expectedTravelTime: TimeInterval

    init(polyline: MKPolyline, distance: CLLocationDistance, expectedTravelTime: TimeInterval) {
        self._polyline = polyline
        self._distance = distance
        self._expectedTravelTime = expectedTravelTime
        super.init()
    }

    override var polyline: MKPolyline { _polyline }
    override var distance: CLLocationDistance { _distance }
    override var expectedTravelTime: TimeInterval { _expectedTravelTime }
}
