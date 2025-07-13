import SwiftUI
import CoreLocation
import MapKit // For CLLocationCoordinate2D

// Import relativeTimeString from MapHelpers
// If module import is not available, copy the function here

struct iPhone_DeviceRowView: View {
    @ObservedObject var device: KnownDevice
    @ObservedObject var cache: DeviceLocationCacheStore // <-- hinzugefügt
    // For live updates, you could use @ObservedObject for the cache, but for now, fetch on render
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(device.DeviceColor ?? UIColor.gray))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.DeviceName)
                    .font(.headline)
                    .foregroundColor(.primary)
                // Subtitle: last seen + distance
                if let subtitle = subtitleText() {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    /// Returns the subtitle string for the device row: last seen + distance
    private func subtitleText() -> String? {
        guard let cached = cache.getLocation(for: device.DeviceID) else {
            let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
            let never = NSLocalizedString("device_row_never", comment: "Default value for never seen device")
            let separator = NSLocalizedString("device_row_separator", comment: "Separator between last seen and distance in device row subtitle")
            let distanceLabel = NSLocalizedString("device_row_distance", comment: "Label for the distance to the device in the device list row")
            let unknown = NSLocalizedString("device_row_unknown", comment: "Default value for unknown distance")
            return "\(lastSeen): \(never) \(separator) \(distanceLabel): \(unknown)"
        }
        // Relative time
        let now = Date()
        let relativeTime = relativeTimeString(from: cached.timestamp, to: now, unitsStyle: .abbreviated)
        // Distance calculation
        guard let myCached = cache.getLocation(for: thisDeviceIDManager.shared.deviceID) else { // <-- cache statt .shared
            let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
            return "\(lastSeen): \(relativeTime)"
        }
        let deviceLoc = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        let myLoc = CLLocation(latitude: myCached.latitude, longitude: myCached.longitude)
        let distance = deviceLoc.distance(from: myLoc) // in meters
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        let formattedDistance: String
        if usesMetric {
            let meterUnit = NSLocalizedString("device_row_meter_unit", comment: "Unit for meters in device row distance display")
            let kilometerUnit = NSLocalizedString("device_row_kilometer_unit", comment: "Unit for kilometers in device row distance display")
            if distance < 1000 {
                formattedDistance = String(format: "%.0f %@", distance, meterUnit)
            } else {
                formattedDistance = String(format: "%d %@", Int(round(distance / 1000)), kilometerUnit)
            }
        } else {
            let feetUnit = NSLocalizedString("device_row_feet_unit", comment: "Unit for feet in device row distance display (imperial)")
            let milesUnit = NSLocalizedString("device_row_miles_unit", comment: "Unit for miles in device row distance display (imperial)")
            let distanceInFeet = distance / 0.3048
            let distanceInMiles = distance / 1609.34
            if distanceInFeet > 528 { // More than 1/10 mile
                formattedDistance = String(format: "%.2f %@", distanceInMiles, milesUnit)
            } else {
                formattedDistance = String(format: "%.0f %@", distanceInFeet, feetUnit)
            }
        }
        let separator = NSLocalizedString("device_row_separator", comment: "Separator between last seen and distance in device row subtitle")
        let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
        let distanceLabel = NSLocalizedString("device_row_distance", comment: "Label for the distance to the device in the device list row")
        return "\(lastSeen): \(relativeTime) \(separator) \(distanceLabel): \(formattedDistance)"
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 200, 200, 200)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// extension KnownDevice: Identifiable {
//     public var id: String { DeviceID }
// }

#Preview {
    @Previewable @State var device = KnownDevice(name: "Testgerät", deviceID: "12345", color: .blue)
    iPhone_DeviceRowView(device: device, cache: DeviceLocationCacheStore.shared) // <-- cache übergeben
} 

