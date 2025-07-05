import SwiftUI
import MapKit

struct MapScaleBar: View {
    let region: MKCoordinateRegion
    let width: CGFloat

    var body: some View {
        let distance = distanceForWidth(region: region, width: width)
        let label = distanceLabel(for: distance)
        HStack(spacing: 2) {
            Rectangle()
                .frame(width: width, height: 2)
                .foregroundColor(.primary)
                .cornerRadius(2)
            Text(label)
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    func distanceForWidth(region: MKCoordinateRegion, width: CGFloat) -> CLLocationDistance {
        // Calculate the distance that 'width' points cover on the map
        let mapViewWidth = UIScreen.main.bounds.width
        let span = region.span
        let center = region.center
        let loc1 = CLLocation(latitude: center.latitude, longitude: center.longitude - span.longitudeDelta / 2 * Double(width / mapViewWidth))
        let loc2 = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta / 2 * Double(width / mapViewWidth))
        return loc1.distance(from: loc2)
    }

    func distanceLabel(for distance: CLLocationDistance) -> String {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        if usesMetric {
            if distance > 1000 {
                // Localized: Kilometer unit for scale bar
                let format = NSLocalizedString("scalebar_kilometers", comment: "Scale bar: display distance in kilometers")
                return String(format: format, distance / 1000)
            } else {
                // Localized: Meter unit for scale bar
                let format = NSLocalizedString("scalebar_meters", comment: "Scale bar: display distance in meters")
                return String(format: format, distance)
            }
        } else {
            // Imperial: miles and feet
            let distanceInFeet = distance / 0.3048
            let distanceInMiles = distance / 1609.34
            if distanceInFeet > 528 { // More than 1/10 mile
                // Localized: Miles unit for scale bar
                let format = NSLocalizedString("scalebar_miles", comment: "Scale bar: display distance in miles")
                return String(format: format, distanceInMiles)
            } else {
                // Localized: Feet unit for scale bar
                let format = NSLocalizedString("scalebar_feet", comment: "Scale bar: display distance in feet")
                return String(format: format, distanceInFeet)
            }
        }
    }
}

#if DEBUG
import SwiftUI

#Preview {
    let center = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405)
    // 10 verschiedene Zoom-Levels von sehr nah bis weit entfernt
    let latitudeDeltas: [CLLocationDegrees] = [0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2]
    VStack(alignment: .leading, spacing: 16) {
        ForEach(latitudeDeltas, id: \.self) { delta in
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom (latitudeDelta): \(String(format: "%.4f", delta))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                MapScaleBar(
                    region: MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
                    ),
                    width: 120
                )
            }
        }
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue.opacity(0.2), .purple.opacity(0.2), .orange.opacity(0.2)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .previewLayout(.sizeThatFits)
}
#endif 
