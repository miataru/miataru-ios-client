import MapKit

/// Helper to determine on which screen edge an off-screen coordinate lies.
/// Returns `nil` if the coordinate is inside the current screen region.
struct OffscreenDeviceEdgeHelper {
    static func edge(for coordinate: CLLocationCoordinate2D,
                     in region: MKCoordinateRegion,
                     screenSize: CGSize,
                     heading: Double) -> Edge? {
        let center = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        let pointUnrotated = coordinateToScreenPoint(coordinate,
                                                      region: region,
                                                      screenSize: screenSize,
                                                      center: center)
        let point = rotate(point: pointUnrotated, around: center, degrees: -heading)

        let visibilityMargin: CGFloat = 20
        let isOutside =
            point.x < visibilityMargin ||
            point.x > screenSize.width - visibilityMargin ||
            point.y < visibilityMargin ||
            point.y > screenSize.height - visibilityMargin
        guard isOutside else { return nil }

        let dx = point.x - center.x
        let dy = point.y - center.y
        let halfWidth = screenSize.width / 2
        let halfHeight = screenSize.height / 2

        if abs(dx) / halfWidth > abs(dy) / halfHeight {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .bottom : .top
        }
    }

    private static func coordinateToScreenPoint(_ coordinate: CLLocationCoordinate2D,
                                                 region: MKCoordinateRegion,
                                                 screenSize: CGSize,
                                                 center: CGPoint) -> CGPoint {
        let latDelta = max(region.span.latitudeDelta, 1e-9)
        let lonDelta = max(region.span.longitudeDelta, 1e-9)

        let dLon = deltaLongitude(coordinate.longitude, region.center.longitude)
        let dLat = coordinate.latitude - region.center.latitude

        let xRatio = CGFloat(dLon / lonDelta).clamped(to: -4...4)
        let yRatio = CGFloat(dLat / latDelta).clamped(to: -4...4)

        let x = center.x + xRatio * screenSize.width
        let y = center.y - yRatio * screenSize.height
        return CGPoint(x: x, y: y)
    }

    private static func rotate(point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let cosA = cos(radians)
        let sinA = sin(radians)
        let x = translatedX * cosA - translatedY * sinA + center.x
        let y = translatedX * sinA + translatedY * cosA + center.y
        return CGPoint(x: x, y: y)
    }

    private static func deltaLongitude(_ lon: CLLocationDegrees, _ center: CLLocationDegrees) -> CLLocationDegrees {
        var d = lon - center
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
