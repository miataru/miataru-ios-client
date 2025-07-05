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
        .background(.thinMaterial)
        .cornerRadius(4)
    }

    func distanceForWidth(region: MKCoordinateRegion, width: CGFloat) -> CLLocationDistance {
        // Berechne die Distanz, die 'width' Punkte auf der Karte abdecken
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
                // Lokalisiert: Kilometer-Einheit für Maßstabsleiste
                let format = NSLocalizedString("scalebar_kilometers", comment: "Scale bar: display distance in kilometers")
                return String(format: format, distance / 1000)
            } else {
                // Lokalisiert: Meter-Einheit für Maßstabsleiste
                let format = NSLocalizedString("scalebar_meters", comment: "Scale bar: display distance in meters")
                return String(format: format, distance)
            }
        } else {
            // Imperial: Meilen und Fuß
            let distanceInFeet = distance / 0.3048
            let distanceInMiles = distance / 1609.34
            if distanceInFeet > 528 { // Mehr als 1/10 Meile
                // Lokalisiert: Meilen-Einheit für Maßstabsleiste
                let format = NSLocalizedString("scalebar_miles", comment: "Scale bar: display distance in miles")
                return String(format: format, distanceInMiles)
            } else {
                // Lokalisiert: Fuß-Einheit für Maßstabsleiste
                let format = NSLocalizedString("scalebar_feet", comment: "Scale bar: display distance in feet")
                return String(format: format, distanceInFeet)
            }
        }
    }
} 