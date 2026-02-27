import Testing
import MapKit
import CoreLocation
@testable import miataru

@Suite("MKPolyline extension geometry tests")
struct MKPolylineExtensionsTests {

    private func line(from coords: [CLLocationCoordinate2D]) -> MKPolyline {
        MKPolyline(coordinates: coords, count: coords.count)
    }

    @Test("split(at:) splits a simple horizontal segment correctly")
    func testSplitSimple() async throws {
        // Build a horizontal line: (0,0) -> (0,0.002) ~ 222m (approx at equator)
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.002)
        let poly = line(from: [a, b])
        // Halfway distance in map points
        let total = MKMapPoint(a).distance(to: MKMapPoint(b))
        let half = total / 2
        let result = poly.split(at: half)
        #expect(result != nil)
        if let (done, todo, ghost, progress) = result {
            // Done + todo should reconstruct the original length
            let doneLen = length(of: done)
            let todoLen = length(of: todo)
            #expect(abs((doneLen + todoLen) - total) < 1e-3)
            // Ghost should lie on the segment between a and b
            #expect(ghost.latitude >= min(a.latitude, b.latitude) - 1e-6)
            #expect(ghost.latitude <= max(a.latitude, b.latitude) + 1e-6)
            #expect(ghost.longitude >= min(a.longitude, b.longitude) - 1e-6)
            #expect(ghost.longitude <= max(a.longitude, b.longitude) + 1e-6)
            // Progress should be ~0.5
            #expect(abs(progress - 0.5) < 0.05)
        }
    }

    @Test("split(at:) at distance 0 yields start interpolation and zero done length")
    func testSplitAtZero() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let poly = line(from: [a, b])
        let total = MKMapPoint(a).distance(to: MKMapPoint(b))
        let result = poly.split(at: 0)
        #expect(result != nil)
        if let (done, todo, ghost, progress) = result {
            #expect(abs(length(of: done)) < 1e-6)
            #expect(abs(length(of: todo) - total) < 1e-3)
            #expect(abs(ghost.latitude - a.latitude) < 1e-9)
            #expect(abs(ghost.longitude - a.longitude) < 1e-9)
            #expect(progress >= 0 && progress <= 0.01)
        }
    }

    @Test("split(at:) at total length yields end interpolation and zero todo length")
    func testSplitAtTotal() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let poly = line(from: [a, b])
        let total = MKMapPoint(a).distance(to: MKMapPoint(b))
        let result = poly.split(at: total)
        #expect(result != nil)
        if let (done, todo, ghost, progress) = result {
            #expect(abs(length(of: done) - total) < 1e-3)
            #expect(abs(length(of: todo)) < 1e-6)
            #expect(abs(ghost.latitude - b.latitude) < 1e-9)
            #expect(abs(ghost.longitude - b.longitude) < 1e-9)
            #expect(progress >= 0.99 && progress <= 1.0)
        }
    }

    @Test("split(at:) works across multiple segments")
    func testSplitMultiSegment() async throws {
        // Three points along the equator: 0 -> 0.004 -> 0.01
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.004)
        let c = CLLocationCoordinate2D(latitude: 0, longitude: 0.010)
        let poly = line(from: [a, b, c])
        let ab = MKMapPoint(a).distance(to: MKMapPoint(b))
        let bc = MKMapPoint(b).distance(to: MKMapPoint(c))
        let total = ab + bc
        // Split at AB + 50% of BC
        let splitAt = ab + bc / 2
        let result = poly.split(at: splitAt)
        #expect(result != nil)
        if let (done, todo, ghost, progress) = result {
            let doneLen = length(of: done)
            let todoLen = length(of: todo)
            #expect(abs((doneLen + todoLen) - total) < 1e-3)
            // Ghost should be roughly halfway between b and c
            let midBC = CLLocationCoordinate2D(latitude: 0, longitude: (b.longitude + c.longitude) / 2)
            let dGhost = MKMapPoint(ghost).distance(to: MKMapPoint(midBC))
            #expect(dGhost < 10) // within ~10 meters tolerance
            // Progress should be ~ (AB + 0.5*BC) / (AB + BC)
            let expectedProgress = splitAt / total
            #expect(abs(progress - expectedProgress) < 0.02)
        }
    }

    @Test("closestDistance(to:) finds zero for a point on the polyline")
    func testClosestDistanceZeroOnLine() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let poly = line(from: [a, b])
        // Point on the line at 25% between a and b
        let mid = CLLocationCoordinate2D(latitude: 0, longitude: 0.0025)
        let d = poly.closestDistance(to: MKMapPoint(mid))
        #expect(d != nil)
        if let d { #expect(d < 1e-6) }
    }

    @Test("closestDistance(to:) returns perpendicular distance when projection falls within segment")
    func testClosestDistancePerpendicularProjection() async throws {
        // Horizontal line: (0,0) -> (0,0.01)
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let poly = line(from: [a, b])
        // Point 0.001° north of the segment at its middle longitude
        let p = CLLocationCoordinate2D(latitude: 0.001, longitude: 0.005)
        let expected = MKMapPoint(CLLocationCoordinate2D(latitude: 0.001, longitude: 0.005))
            .distance(to: MKMapPoint(CLLocationCoordinate2D(latitude: 0.0, longitude: 0.005)))
        let d = poly.closestDistance(to: MKMapPoint(p))
        #expect(d != nil)
        if let d { #expect(abs(d - expected) < 1.0) } // within ~1m
    }

    @Test("closestDistance(to:) works for single-point polyline")
    func testClosestDistanceSinglePointPolyline() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let poly = line(from: [a])
        let same = MKMapPoint(a)
        let far = MKMapPoint(CLLocationCoordinate2D(latitude: 0.01, longitude: 0.01))
        let dSame = poly.closestDistance(to: same)
        let dFar = poly.closestDistance(to: far)
        #expect(dSame != nil && dFar != nil)
        if let dSame, let dFar {
            #expect(dSame < 1e-6)
            #expect(dFar > 0)
        }
    }

    @Test("remainingDistance(toEndFrom:) decreases as point moves along the polyline")
    func testRemainingDistanceMonotonic() async throws {
        let coords = stride(from: 0.0, through: 0.01, by: 0.002).map { lon in
            CLLocationCoordinate2D(latitude: 0, longitude: lon)
        }
        let poly = line(from: coords)
        let start = MKMapPoint(coords.first!)
        let end = MKMapPoint(coords.last!)
        let total = poly.remainingDistance(toEndFrom: start)!
        let mid = MKMapPoint(CLLocationCoordinate2D(latitude: 0, longitude: 0.006))
        let remainMid = poly.remainingDistance(toEndFrom: mid)!
        let remainEnd = poly.remainingDistance(toEndFrom: end)!
        #expect(total > remainMid)
        #expect(remainMid > remainEnd)
        #expect(remainEnd < 1e-6)
    }

    @Test("remainingDistance(toEndFrom:) equals total when point is before start of polyline")
    func testRemainingDistanceBeforeStart() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let b = CLLocationCoordinate2D(latitude: 0, longitude: 0.01)
        let poly = line(from: [a, b])
        let total = MKMapPoint(a).distance(to: MKMapPoint(b))
        let beforeStart = MKMapPoint(CLLocationCoordinate2D(latitude: 0, longitude: -0.001))
        let remain = poly.remainingDistance(toEndFrom: beforeStart)!
        #expect(abs(remain - total) < 1.0)
    }

    @Test("remainingDistance(toEndFrom:) works for single-point polyline")
    func testRemainingDistanceSinglePointPolyline() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let poly = line(from: [a])
        let far = MKMapPoint(CLLocationCoordinate2D(latitude: 0.01, longitude: 0.01))
        let expected = far.distance(to: MKMapPoint(a))
        let remain = poly.remainingDistance(toEndFrom: far)
        #expect(remain != nil)
        if let remain { #expect(abs(remain - expected) < 1.0) }
    }

    @Test("split(at:) returns nil for degenerate (single-point) polyline")
    func testSplitDegeneratePolyline() async throws {
        let a = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let poly = line(from: [a])
        let result = poly.split(at: 10)
        #expect(result == nil)
    }

    // Helper to compute polyline length in meters from its points
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
