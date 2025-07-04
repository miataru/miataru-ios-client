import SwiftUI
import MapKit

struct iPhone_PinWithAccuracyView: View {
    let coordinate: CLLocationCoordinate2D
    let accuracy: Double?
    let region: MKCoordinateRegion
    let color: UIColor?
    var body: some View {
        ZStack {
            if let accuracy = accuracy, accuracy > 0 {
                let diameter = min(CGFloat(accuracy / region.metersPerPoint()), 300)
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: diameter, height: diameter)
            }
            iPhone_PinView(color: Color(color ?? UIColor.blue))
                .offset(y: -24)
        }
    }
}

// Hilfs-Extension für die Umrechnung Meter -> Punkt auf der Map
extension MKCoordinateRegion {
    func metersPerPoint() -> Double {
        // Annäherung: 1 Punkt = x Meter auf der aktuellen Zoomstufe
        // 1° Breitengrad = ca. 111.000 Meter
        let mapWidthInMeters = self.span.longitudeDelta * 111_000.0 * cos(self.center.latitude * .pi / 180)
        let mapWidthInPoints: Double =  UIScreen.main.bounds.width
        return mapWidthInMeters / mapWidthInPoints
    }
} 
