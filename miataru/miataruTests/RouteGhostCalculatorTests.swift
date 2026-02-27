import Testing
import MapKit
import CoreLocation
@testable import miataru

@Suite("RouteGhostCalculator tests")
struct RouteGhostCalculatorTests {

    private func route(from coords: [CLLocationCoordinate2D], expectedTravelTime: TimeInterval = 60) -> MKRoute {
        // Build an MKRoute by creating an MKPolyline and wrapping it in an MKRoute via MKRoute-like shim
        // Since MKRoute's initializers are not public, create a lightweight subclass that mirrors distance and polyline.
        // We'll compute distance from the polyline points and set expectedTravelTime via KVC.
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        let distance = length(of: poly)
        let route = FakeRoute(polyline: poly, distance: distance, expectedTravelTime: expectedTravelTime)
        return route
    }

    @Test("Ghost progresses with primary speed and timestamp (non-reversed: user primary)")
    func testGhostProgressWithUserSpeed() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 120)
        let userCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let deviceCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.008)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // User is primary when isRouteReversed=false
        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: now.addingTimeInterval(-1),
            knownDeviceSpeed: 20, // ignored because non-reversed
            userTimestamp: now.addingTimeInterval(-5),
            knownUserSpeed: 5, // m/s
            now: now,
            isRouteReversed: false
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            #expect(progress > 0.0)
            #expect(progress <= 1.0)
        }
    }

    @Test("Ghost uses expectedTravelTime fallback when speeds are below threshold")
    func testGhostFallbackExpectedTravelTime() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 100)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: b,
            userCoordinate: a,
            deviceTimestamp: now.addingTimeInterval(-50),
            knownDeviceSpeed: 0.1, // below threshold
            userTimestamp: now.addingTimeInterval(-50),
            knownUserSpeed: 0.0, // below threshold
            now: now,
            isRouteReversed: false
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            // ~50/100 seconds => ~0.5 progress (allow tolerance)
            #expect(progress > 0.3 && progress < 0.7)
        }
    }

    @Test("Ghost bases from device when reversed route")
    func testGhostReversedUsesDeviceAsBase() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 120)
        let userCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let deviceCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.004)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: now.addingTimeInterval(-10),
            knownDeviceSpeed: 3.0, // m/s
            userTimestamp: now.addingTimeInterval(-10),
            knownUserSpeed: 10.0, // ignored because reversed
            now: now,
            isRouteReversed: true
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            #expect(progress > 0)
        }
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

// A tiny shim to stand in for MKRoute so we can supply polyline, distance, and expectedTravelTime deterministically
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
