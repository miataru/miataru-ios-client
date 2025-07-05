import MapKit
import SwiftUI

// Helper function for MapStyle
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

// Helper function for zoom level (in km)
func spanForZoomLevel(_ zoomLevel: Int) -> MKCoordinateSpan {
    // 1° latitude ≈ 111 km
    let km = Double(zoomLevel)
    let delta = km / 111.0
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
}

// Helper function to calculate current zoom level from span
func currentZoomLevelFromSpan(_ span: MKCoordinateSpan) -> Int {
    // Average of latitude and longitude delta
    let avgDelta = (span.latitudeDelta + span.longitudeDelta) / 2.0
    // Convert back to km: 1° ≈ 111 km
    let km = avgDelta * 111.0
    return Int(round(km))
}

/// Returns a relative time string for a date (e.g. "2 minutes ago")
func relativeTimeString(from date: Date?) -> String {
    guard let date = date else { return "–" }
    let now = Date()
    let diff = now.timeIntervalSince(date)
    if date > now || abs(diff) < 10 {
        return NSLocalizedString("relative_time_now", comment: "Indicates that the location update just happened or is happening right now in a relative time on the map marker.")
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: now)
} 
