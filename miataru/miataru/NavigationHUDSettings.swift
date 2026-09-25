import Foundation
import Combine
import CoreLocation
import MapKit

struct NavigationHUDProjection {
    let route: [CGPoint]
    let user: CGPoint?
    let remote: CGPoint?
    let userHeadingVector: CGVector?

    static func project(
        routeCoordinates: [CLLocationCoordinate2D],
        userCoordinate: CLLocationCoordinate2D?,
        remoteCoordinate: CLLocationCoordinate2D?,
        size: CGSize,
        alignForward: Bool = false,
        headingDegrees: CLLocationDirection? = nil,
        allowsRouteTangentFallback: Bool = true
    ) -> NavigationHUDProjection {
        let validHeadingDegrees = headingDegrees.flatMap { $0.isFinite ? $0 : nil }
        var mapRoute = routeCoordinates.map(MKMapPoint.init)
        var transform: (MKMapPoint) -> MKMapPoint = { $0 }
        if alignForward, mapRoute.count > 1 {
            let userPoint = userCoordinate.map(MKMapPoint.init) ?? mapRoute[0]
            let nearestIndex = mapRoute.indices.min {
                let left = mapRoute[$0], right = mapRoute[$1]
                let leftDistance = (left.x - userPoint.x) * (left.x - userPoint.x) + (left.y - userPoint.y) * (left.y - userPoint.y)
                let rightDistance = (right.x - userPoint.x) * (right.x - userPoint.x) + (right.y - userPoint.y) * (right.y - userPoint.y)
                return leftDistance < rightDistance
            } ?? 0
            let headingStartIndex = min(nearestIndex, mapRoute.count - 2)
            let headingStart = mapRoute[headingStartIndex]
            let headingEnd = mapRoute[headingStartIndex + 1]
            let dx = headingEnd.x - headingStart.x
            let dy = headingEnd.y - headingStart.y
            let angle = -Double.pi / 2 - atan2(dy, dx)
            let cosine = cos(angle)
            let sine = sin(angle)
            transform = { point in
                let x = point.x - userPoint.x
                let y = point.y - userPoint.y
                return MKMapPoint(x: x * cosine - y * sine, y: x * sine + y * cosine)
            }
            mapRoute = mapRoute.map(transform)
        }
        var mapPoints = mapRoute
        let userIndex = mapPoints.count
        if let userCoordinate { mapPoints.append(transform(MKMapPoint(userCoordinate))) }
        let headingIndex = mapPoints.count
        if let userCoordinate, let validHeadingDegrees {
            mapPoints.append(transform(MKMapPoint(Self.coordinate(from: userCoordinate, bearing: validHeadingDegrees, distance: 35))))
        }
        let remoteIndex = mapPoints.count
        if let remoteCoordinate { mapPoints.append(transform(MKMapPoint(remoteCoordinate))) }
        guard !mapPoints.isEmpty else { return NavigationHUDProjection(route: [], user: nil, remote: nil, userHeadingVector: nil) }
        if alignForward {
            let anchor = userCoordinate == nil ? mapRoute[0] : mapPoints[userIndex]
            let forwardExtent = max(mapRoute.map { max(0, anchor.y - $0.y) }.max() ?? 0, 1)
            let behindExtent = max(mapRoute.map { max(0, $0.y - anchor.y) }.max() ?? 0, 1)
            let lateralExtent = max(mapRoute.map { abs($0.x - anchor.x) }.max() ?? 0, 1)
            let lateralScale = max(1, size.width - 72) / (2 * lateralExtent)
            func perspectivePoint(_ point: MKMapPoint) -> CGPoint {
                let forward = max(0, anchor.y - point.y)
                let behind = max(0, point.y - anchor.y)
                let progress = min(1, sqrt(forward / forwardExtent))
                let nearScale = 1 - 0.35 * progress
                let x = size.width / 2 + (point.x - anchor.x) * lateralScale * nearScale
                let y = size.height * 0.78 - progress * size.height * 0.64
                    + sqrt(min(1, behind / behindExtent)) * size.height * 0.12
                return CGPoint(x: min(size.width - 24, max(24, x)), y: min(size.height - 24, max(24, y)))
            }
            let projected = mapPoints.map(perspectivePoint)
            let userScreenPoint = userCoordinate == nil ? nil : CGPoint(x: size.width / 2, y: size.height * 0.78)
            return NavigationHUDProjection(
                route: Array(projected.prefix(mapRoute.count)),
                user: userScreenPoint,
                remote: remoteCoordinate == nil ? nil : projected[remoteIndex],
                userHeadingVector: Self.headingVector(
                    projected: projected,
                    route: mapRoute,
                    userMapPoint: userCoordinate.map { transform(MKMapPoint($0)) },
                    userIndex: userIndex,
                    headingIndex: validHeadingDegrees == nil ? nil : headingIndex,
                    allowsRouteTangentFallback: allowsRouteTangentFallback,
                    userScreenPoint: userScreenPoint
                )
            )
        }
        let xs = mapPoints.map(\.x), ys = mapPoints.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let width = max(maxX - minX, 1), height = max(maxY - minY, 1)
        let inset: CGFloat = 38
        let scale = min(max(1, size.width - inset * 2) / width, max(1, size.height - inset * 2) / height)
        let contentWidth = width * scale, contentHeight = height * scale
        let left = (size.width - contentWidth) / 2, top = (size.height - contentHeight) / 2
        let projected = mapPoints.map { CGPoint(x: left + ($0.x - minX) * scale, y: top + ($0.y - minY) * scale) }
        return NavigationHUDProjection(
            route: Array(projected.prefix(mapRoute.count)),
            user: userCoordinate == nil ? nil : projected[userIndex],
            remote: remoteCoordinate == nil ? nil : projected[remoteIndex],
            userHeadingVector: Self.headingVector(
                projected: projected,
                route: mapRoute,
                userMapPoint: userCoordinate.map { transform(MKMapPoint($0)) },
                userIndex: userIndex,
                headingIndex: validHeadingDegrees == nil ? nil : headingIndex,
                allowsRouteTangentFallback: allowsRouteTangentFallback,
                userScreenPoint: userCoordinate == nil ? nil : projected[userIndex]
            )
        )
    }

    private static func headingVector(
        projected: [CGPoint],
        route: [MKMapPoint],
        userMapPoint: MKMapPoint?,
        userIndex: Int,
        headingIndex: Int?,
        allowsRouteTangentFallback: Bool,
        userScreenPoint: CGPoint?
    ) -> CGVector? {
        guard let userScreenPoint else { return nil }
        if let headingIndex, projected.indices.contains(headingIndex) {
            let endpoint = projected[headingIndex]
            return CGVector(dx: endpoint.x - userScreenPoint.x, dy: endpoint.y - userScreenPoint.y)
        }
        guard allowsRouteTangentFallback, route.count > 1, let userMapPoint else { return nil }
        var bestSegment = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for index in 0..<(route.count - 1) {
            let start = route[index], end = route[index + 1]
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared == 0 ? 0 : min(1, max(0, ((userMapPoint.x - start.x) * dx + (userMapPoint.y - start.y) * dy) / lengthSquared))
            let x = start.x + dx * fraction, y = start.y + dy * fraction
            let distance = (x - userMapPoint.x) * (x - userMapPoint.x) + (y - userMapPoint.y) * (y - userMapPoint.y)
            if distance < bestDistance {
                bestDistance = distance
                bestSegment = index
            }
        }
        let start = projected[bestSegment], end = projected[bestSegment + 1]
        let vector = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        guard hypot(vector.dx, vector.dy) > 1 else { return nil }
        return vector
    }

    private static func coordinate(
        from coordinate: CLLocationCoordinate2D,
        bearing degrees: CLLocationDirection,
        distance: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let angularDistance = distance / earthRadius
        let bearing = degrees * .pi / 180
        let latitude1 = coordinate.latitude * .pi / 180
        let longitude1 = coordinate.longitude * .pi / 180
        let latitude2 = asin(sin(latitude1) * cos(angularDistance) + cos(latitude1) * sin(angularDistance) * cos(bearing))
        let longitude2 = longitude1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(latitude1),
            cos(angularDistance) - sin(latitude1) * sin(latitude2)
        )
        return CLLocationCoordinate2D(latitude: latitude2 * 180 / .pi, longitude: longitude2 * 180 / .pi)
    }
}

enum NavigationHUDFocusRoute {
    static func coordinates(
        route: [CLLocationCoordinate2D],
        userCoordinate: CLLocationCoordinate2D?,
        lookAheadMeters: CLLocationDistance = 900,
        lookBehindMeters: CLLocationDistance = 60
    ) -> [CLLocationCoordinate2D] {
        guard route.count > 1, let userCoordinate else { return [] }
        let points = route.map(MKMapPoint.init)
        let user = MKMapPoint(userCoordinate)
        let metersPerPoint = MKMetersPerMapPointAtLatitude(userCoordinate.latitude)
        guard metersPerPoint > 0 else { return [] }

        var closestSegment = 0
        var closestFraction = 0.0
        var closestDistanceSquared = Double.greatestFiniteMagnitude
        var cumulative = [0.0]
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared == 0 ? 0 : min(1, max(0, ((user.x - start.x) * dx + (user.y - start.y) * dy) / lengthSquared))
            let candidate = MKMapPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
            let distanceSquared = (candidate.x - user.x) * (candidate.x - user.x) + (candidate.y - user.y) * (candidate.y - user.y)
            if distanceSquared < closestDistanceSquared {
                closestDistanceSquared = distanceSquared
                closestSegment = index
                closestFraction = fraction
            }
            cumulative.append(cumulative[index] + start.distance(to: end))
        }

        let segmentStart = points[closestSegment]
        let segmentEnd = points[closestSegment + 1]
        let current = MKMapPoint(
            x: segmentStart.x + (segmentEnd.x - segmentStart.x) * closestFraction,
            y: segmentStart.y + (segmentEnd.y - segmentStart.y) * closestFraction
        )
        let currentDistance = cumulative[closestSegment] + segmentStart.distance(to: segmentEnd) * closestFraction
        guard sqrt(closestDistanceSquared) * metersPerPoint <= 3_000 else { return [] }
        let lowerBound = max(0, currentDistance - lookBehindMeters)
        let upperBound = min(cumulative.last ?? currentDistance, currentDistance + lookAheadMeters)

        var result: [CLLocationCoordinate2D] = []
        func point(at distance: CLLocationDistance) -> MKMapPoint {
            guard let segment = (0..<(points.count - 1)).first(where: { distance <= cumulative[$0 + 1] }) else { return points.last! }
            let segmentLength = cumulative[segment + 1] - cumulative[segment]
            let fraction = segmentLength == 0 ? 0 : min(1, max(0, (distance - cumulative[segment]) / segmentLength))
            return MKMapPoint(
                x: points[segment].x + (points[segment + 1].x - points[segment].x) * fraction,
                y: points[segment].y + (points[segment + 1].y - points[segment].y) * fraction
            )
        }
        result.append(point(at: lowerBound).coordinate)
        if lowerBound <= currentDistance { result.append(current.coordinate) }
        for index in 1..<(cumulative.count - 1) where cumulative[index] > currentDistance && cumulative[index] < upperBound {
            result.append(points[index].coordinate)
        }
        result.append(point(at: upperBound).coordinate)
        return result
    }
}

struct NavigationHUDHeading: Equatable {
    enum Source: Equatable { case compass, course }

    let degrees: CLLocationDirection
    let source: Source

    static func resolve(
        compassDegrees: CLLocationDirection?,
        compassIsValid: Bool,
        courseDegrees: CLLocationDirection?,
        speed: CLLocationSpeed?,
        locationAge: TimeInterval?
    ) -> NavigationHUDHeading? {
        if compassIsValid, let compassDegrees, compassDegrees.isFinite {
            return NavigationHUDHeading(degrees: compassDegrees, source: .compass)
        }
        guard let courseDegrees, courseDegrees.isFinite, courseDegrees >= 0,
              let speed, speed.isFinite, speed >= 1,
              let locationAge, locationAge >= 0, locationAge <= 15 else { return nil }
        return NavigationHUDHeading(degrees: courseDegrees, source: .course)
    }
}

enum NavigationHUDAngle {
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    static func shortestDelta(from start: Double, to end: Double) -> Double {
        let delta = normalized(end) - normalized(start)
        return (delta + 540).truncatingRemainder(dividingBy: 360) - 180
    }
}

enum NavigationHUDPalette: String, CaseIterable, Identifiable {
    case white
    case red
    case yellow

    var id: String { rawValue }

    var optionTitle: String {
        let key: String
        switch self {
        case .white: key = "navigation_hud_palette_white_option"
        case .red: key = "navigation_hud_palette_red_option"
        case .yellow: key = "navigation_hud_palette_yellow_option"
        }
        return String(localized: String.LocalizationValue(key), table: "MapNavigationHistory")
    }
}

@MainActor
final class NavigationHUDSettings: ObservableObject {
    static let shared = NavigationHUDSettings(defaults: .standard)

    private let defaults: UserDefaults
    private let prefix = "navigation_hud_"

    @Published var palette: NavigationHUDPalette {
        didSet { defaults.set(palette.rawValue, forKey: prefix + "palette") }
    }
    @Published var isMirrored: Bool {
        didSet { defaults.set(isMirrored, forKey: prefix + "mirrored") }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        palette = NavigationHUDPalette(rawValue: defaults.string(forKey: "navigation_hud_palette") ?? "white") ?? .white
        isMirrored = defaults.bool(forKey: "navigation_hud_mirrored")
    }
}

@MainActor
final class NavigationHUDSession: ObservableObject {
    static let shared = NavigationHUDSession()
    @Published private(set) var isActive = false

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
    }
}
