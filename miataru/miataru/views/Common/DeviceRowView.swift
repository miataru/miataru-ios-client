/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceRowView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI
import CoreLocation
import MapKit // For CLLocationCoordinate2D
import Combine

// Import relativeTimeString from MapHelpers
// If module import is not available, copy the function here

struct DeviceRowView: View {
    @ObservedObject var device: KnownDevice
    @ObservedObject var cache: DeviceLocationCacheStore
    @State private var isGeocoding = false
    @ObservedObject private var settings = SettingsManager.shared
    @State private var displayedCachedLocation: CachedDeviceLocation? = nil
    @State private var locationUpdateCancellable: AnyCancellable? = nil
    // For live updates, you could use @ObservedObject for the cache, but for now, fetch on render
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            if let batteryLevel = displayedCachedLocation?.batteryLevel {
                DeviceBatterySymbol(
                    batteryLevel: batteryLevel,
                    deviceColor: Color(device.DeviceColor ?? UIColor.gray),
                    size: 16
                )
            } else {
                ZStack {
                    Circle()
                        .fill(Color(device.DeviceColor ?? UIColor.gray))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 4)
                }
                .frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.DeviceName)
                    .font(.headline)
                    .foregroundColor(colorScheme == .light ? .black : .white)
                // Subtitle: last seen + distance (always render)
                let subtitle = subtitleText(from: displayedCachedLocation)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.identity)
                    .animation(nil, value: subtitle)
                // Placemark (always render)
                let place = placemarkText(from: displayedCachedLocation)
                Text(place)
                    .font(.caption)
                    .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.identity)
                    .animation(nil, value: place)
            }
            .transaction { t in t.animation = nil }
            .onAppear {
                if displayedCachedLocation == nil {
                    displayedCachedLocation = cache.getLocation(for: device.DeviceID)
                }
                setupThrottledLocationSubscription()
                DeviceLocationCacheStore.shared.enqueueGeocodingIfNeeded(for: device.DeviceID)
            }
            .onDisappear {
                locationUpdateCancellable?.cancel()
                locationUpdateCancellable = nil
            }
            .onChange(of: settings.mapUpdateInterval) { _, _ in
                setupThrottledLocationSubscription()
            }
            .onChange(of: displayedCachedLocation?.timestamp) { _, _ in
                DeviceLocationCacheStore.shared.enqueueGeocodingIfNeeded(for: device.DeviceID)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName))
        .accessibilityValue(Text(subtitleText(from: displayedCachedLocation)))
    }
    
    /// Returns the subtitle string for the device row: last seen + distance
    private func subtitleText(from cached: CachedDeviceLocation?) -> String {
        guard let cached = cached else {
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
        guard let myCached = cache.getLocation(for: thisDeviceIDManager.shared.deviceID) else {
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

    private func placemarkText(from cached: CachedDeviceLocation?) -> String {
        var placemarkText = ""
        
        // Prefer snapshot's existing placemark (prevents flicker when location changes but geocode not finished)
        if let country = cached?.country, let locality = cached?.locality {
            placemarkText = "\(locality), \(country)"
        } else if let placemark = cache.getPlacemark(for: device.DeviceID), let country = placemark.country, let locality = placemark.locality {
            placemarkText = "\(locality), \(country)"
        }
        
        // Add altitude if available
        if let altitude = cached?.altitude {
            let (altitudeValue, altitudeUnit) = formatAltitude(altitude)
            let altitudeLabel = NSLocalizedString("altitude_label", comment: "Altitude label/abbreviation for display in device row")
            if !placemarkText.isEmpty {
                placemarkText += " (\(altitudeLabel): \(altitudeValue) \(altitudeUnit))"
            } else {
                placemarkText = "\(altitudeLabel): \(altitudeValue) \(altitudeUnit)"
            }
        }
        
        return placemarkText
    }
    
    private func formatAltitude(_ altitudeInMeters: Double) -> (String, String) {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        
        if usesMetric {
            let altitudeValue = String(format: "%.0f", altitudeInMeters)
            let altitudeUnit = NSLocalizedString("altitude_meters", comment: "Altitude in meters")
            return (altitudeValue, altitudeUnit)
        } else {
            // Convert meters to feet (1 meter = 3.28084 feet)
            let altitudeInFeet = altitudeInMeters * 3.28084
            let altitudeValue = String(format: "%.0f", altitudeInFeet)
            let altitudeUnit = NSLocalizedString("altitude_feet", comment: "Altitude in feet")
            return (altitudeValue, altitudeUnit)
        }
    }

    private func startGeocodingIfNeeded() {
        guard !isGeocoding else { return }
        guard cache.getPlacemark(for: device.DeviceID) == nil else { return }
        guard let cached = displayedCachedLocation ?? cache.getLocation(for: device.DeviceID) else { return }
        isGeocoding = true
        let location = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let pm = placemarks?.first
            DispatchQueue.main.async {
                isGeocoding = false
                if let pm = pm {
                    let country = pm.country
                    let locality = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea
                    cache.setPlacemark(for: device.DeviceID, country: country, locality: locality)
                }
            }
        }
    }

    private func setupThrottledLocationSubscription() {
        locationUpdateCancellable?.cancel()
        let interval = max(1.0, Double(settings.mapUpdateInterval))
        locationUpdateCancellable = cache.$locations
            .map { _ in cache.getLocation(for: device.DeviceID) }
            .removeDuplicates { lhs, rhs in
                lhs?.latitude == rhs?.latitude &&
                lhs?.longitude == rhs?.longitude &&
                lhs?.accuracy == rhs?.accuracy &&
                lhs?.timestamp == rhs?.timestamp &&
                lhs?.batteryLevel == rhs?.batteryLevel &&
                lhs?.altitude == rhs?.altitude &&
                lhs?.country == rhs?.country &&
                lhs?.locality == rhs?.locality
            }
            .throttle(for: .seconds(interval), scheduler: RunLoop.main, latest: true)
            .sink { newValue in
                displayedCachedLocation = newValue
            }
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
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, (int >> 0) & 0xFF)
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
    @Previewable @State var device = KnownDevice(name: "Test Device", deviceID: "12345", color: .blue)
    DeviceRowView(device: device, cache: DeviceLocationCacheStore.shared)
}
