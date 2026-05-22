import Testing
import MapKit
import CoreLocation
@testable import miataru

@Suite("RouteGhostCalculator tests")
struct RouteGhostCalculatorTests {

    private func route(
        from coords: [CLLocationCoordinate2D],
        expectedTravelTime: TimeInterval = 60,
        reportedDistance: CLLocationDistance? = nil
    ) -> MKRoute {
        // Build an MKRoute by creating an MKPolyline and wrapping it in an MKRoute via MKRoute-like shim
        // Since MKRoute's initializers are not public, create a lightweight subclass that mirrors distance and polyline.
        // We'll compute distance from the polyline points and set expectedTravelTime via KVC.
        let poly = MKPolyline(coordinates: coords, count: coords.count)
        let distance = length(of: poly)
        let route = FakeRoute(polyline: poly, distance: reportedDistance ?? distance, expectedTravelTime: expectedTravelTime)
        return route
    }

    @Test("Ghost progresses with device speed and timestamp in standard direction")
    func testGhostProgressWithDeviceSpeedInStandardDirection() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 120)
        let deviceCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let userCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.008)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: now.addingTimeInterval(-5),
            knownDeviceSpeed: 5,
            userTimestamp: now.addingTimeInterval(-100),
            knownUserSpeed: 20,
            now: now,
            isRouteFromDeviceToUser: true
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            #expect(progress > 0.18)
            #expect(progress < 0.35)
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
            deviceCoordinate: a,
            userCoordinate: b,
            deviceTimestamp: now.addingTimeInterval(-50),
            knownDeviceSpeed: 0.1, // below threshold
            userTimestamp: now.addingTimeInterval(-50),
            knownUserSpeed: 0.0, // below threshold
            now: now,
            isRouteFromDeviceToUser: true
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            // ~50/100 seconds => ~0.5 progress (allow tolerance)
            #expect(progress > 0.3 && progress < 0.7)
        }
    }

    @Test("Ghost progresses with user speed and timestamp in reverse direction")
    func testGhostProgressWithUserSpeedInReverseDirection() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 120)
        let userCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let deviceCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.008)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: now.addingTimeInterval(-100),
            knownDeviceSpeed: 20,
            userTimestamp: now.addingTimeInterval(-10),
            knownUserSpeed: 3.0,
            now: now,
            isRouteFromDeviceToUser: false
        )
        #expect(res != nil)
        if let (_, _, _, progress) = res {
            #expect(progress > 0.18)
            #expect(progress < 0.35)
        }
    }

    @Test("Ghost progresses monotonically between timer ticks")
    func testGhostProgressesMonotonicallyBetweenTicks() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let route = route(from: [a, b], expectedTravelTime: 120)
        let deviceCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.001)
        let userCoord = CLLocationCoordinate2D(latitude: 0, longitude: 0.009)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let first = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: start,
            knownDeviceSpeed: 6,
            userTimestamp: start,
            knownUserSpeed: nil,
            now: start.addingTimeInterval(1),
            isRouteFromDeviceToUser: true
        )
        let second = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: start,
            knownDeviceSpeed: 6,
            userTimestamp: start,
            knownUserSpeed: nil,
            now: start.addingTimeInterval(6),
            isRouteFromDeviceToUser: true
        )
        let third = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: deviceCoord,
            userCoordinate: userCoord,
            deviceTimestamp: start,
            knownDeviceSpeed: 6,
            userTimestamp: start,
            knownUserSpeed: nil,
            now: start.addingTimeInterval(11),
            isRouteFromDeviceToUser: true
        )

        #expect(first != nil)
        #expect(second != nil)
        #expect(third != nil)
        if let first, let second, let third {
            #expect(first.3 < second.3)
            #expect(second.3 < third.3)
        }
    }

    @Test("Ghost uses polyline length when reported route distance is larger")
    func testGhostUsesPolylineLengthWhenReportedRouteDistanceIsLarger() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let polylineRoute = route(from: [a, b])
        let reportedDistance = length(of: polylineRoute.polyline) * 2
        let route = route(from: [a, b], expectedTravelTime: 100, reportedDistance: reportedDistance)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: a,
            userCoordinate: b,
            deviceTimestamp: now.addingTimeInterval(-100),
            knownDeviceSpeed: 1_000,
            userTimestamp: nil,
            knownUserSpeed: nil,
            now: now,
            isRouteFromDeviceToUser: true
        )

        #expect(res != nil)
        if let (_, _, ghost, progress) = res {
            #expect(abs(ghost.latitude - b.latitude) < 1e-9)
            #expect(abs(ghost.longitude - b.longitude) < 1e-9)
            #expect(progress == 1)
        }
    }

    @Test("Ghost uses polyline length when reported route distance is smaller")
    func testGhostUsesPolylineLengthWhenReportedRouteDistanceIsSmaller() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let polylineRoute = route(from: [a, b])
        let reportedDistance = length(of: polylineRoute.polyline) * 0.5
        let route = route(from: [a, b], expectedTravelTime: 100, reportedDistance: reportedDistance)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let res = RouteGhostCalculator.ghost(
            for: route,
            deviceCoordinate: a,
            userCoordinate: b,
            deviceTimestamp: now.addingTimeInterval(-100),
            knownDeviceSpeed: 1_000,
            userTimestamp: nil,
            knownUserSpeed: nil,
            now: now,
            isRouteFromDeviceToUser: true
        )

        #expect(res != nil)
        if let (_, _, ghost, progress) = res {
            #expect(abs(ghost.latitude - b.latitude) < 1e-9)
            #expect(abs(ghost.longitude - b.longitude) < 1e-9)
            #expect(progress == 1)
        }
    }

    @Test("Presentation policy uses fresh route start instead of stale sample timestamps")
    func testPresentationPolicyUsesFreshRouteStart() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let shouldShow = RouteGhostPresentationPolicy.shouldShowGhost(
            isRouteFromDeviceToUser: true,
            progress: 0.5,
            minimumProgress: 0.05,
            routeStartDate: now.addingTimeInterval(-1),
            expectedTravelTime: 120,
            now: now
        )

        #expect(shouldShow)
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
