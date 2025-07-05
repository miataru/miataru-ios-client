import MapKit
import SwiftUI

// Hilfsfunktion für MapStyle
@available(iOS 17.0, *)
func mapStyleFromSettings(_ mapType: Int) -> MapStyle {
    switch mapType {
    case 2:
        return .hybrid(elevation: .automatic)
    case 3:
        return .imagery(elevation: .automatic)
    default:
        return .standard(elevation: .automatic)
    }
}

// Hilfsfunktion für Zoom-Level (in km)
func spanForZoomLevel(_ zoomLevel: Int) -> MKCoordinateSpan {
    // 1° Breitengrad ≈ 111 km
    let km = Double(zoomLevel)
    let delta = km / 111.0
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
}

// Hilfsfunktion um aktuellen Zoom-Level aus Span zu berechnen
func currentZoomLevelFromSpan(_ span: MKCoordinateSpan) -> Int {
    // Durchschnitt aus latitude und longitude delta
    let avgDelta = (span.latitudeDelta + span.longitudeDelta) / 2.0
    // Umrechnung zurück zu km: 1° ≈ 111 km
    let km = avgDelta * 111.0
    return Int(round(km))
} 
