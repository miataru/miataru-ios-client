/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_VisitorHistoryView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-19.
 */

import SwiftUI
import MiataruAPIClient
import CoreLocation
import UIKit

// Helper struct for sheet(item:) presentation
struct DeviceIDItem: Identifiable {
    let id: String
    let deviceID: String
}

@MainActor
final class VisitorHistoryViewModel: ObservableObject {
    @Published var visitors: [MiataruVisitor] = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    private let settings = SettingsManager.shared
    private var lastRefresh: Date?
    
    var sortedVisitors: [MiataruVisitor] {
        visitors.sorted { $0.TimeStampDate > $1.TimeStampDate }
    }

    func refreshIfNeeded(isVisible: Bool, force: Bool = false) async {
        if force {
            lastRefresh = Date()
            await loadVisitorHistory(showLoading: false)
            return
        }

        guard await shouldRefresh(isVisible: isVisible) else {
            return
        }

        lastRefresh = Date()
        await loadVisitorHistory(showLoading: false)
    }
    
    func loadVisitorHistory(showLoading: Bool = true) async {
        guard let url = URL(string: settings.miataruServerURL) else {
            errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
            return
        }
        
        if showLoading {
            isLoading = true
        }
        errorMessage = nil
        
        do {
            let ourDeviceId = thisDeviceIDManager.shared.deviceID
            // Request with nil amount to get all available from server
            APIRequestCounter.shared.record(.getVisitorHistory)
            let response = try await MiataruAPIClient.getVisitorHistoryWithConfig(
                serverURL: url,
                forDeviceID: ourDeviceId,
                deviceKey: settings.deviceKey,
                amount: nil
            )
            self.visitors = response.MiataruVisitors
            self.isLoading = false
        } catch {
            if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                self.errorMessage = authMessage
            } else {
                self.errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
            }
            self.isLoading = false
            debugLog("[VisitorHistoryViewModel] Failed to load visitor history: \(error)")
        }
    }

    private func shouldRefresh(isVisible: Bool) async -> Bool {
        guard settings.autoRefreshDeviceList,
              isVisible else {
            return false
        }

        let isActive = UIApplication.shared.applicationState == .active
        guard isActive else {
            return false
        }

        let interval = Double(settings.outsideMapUpdateInterval)
        let now = Date()

        if let last = lastRefresh, now.timeIntervalSince(last) < interval {
            return false
        }

        return true
    }
}

struct VisitorHistoryStateView<Content: View>: View {
    @ObservedObject var viewModel: VisitorHistoryViewModel
    let content: ([MiataruVisitor]) -> Content
    
    var body: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding()
        } else if let error = viewModel.errorMessage {
            VStack(spacing: 16) {
                Text(error)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button(NSLocalizedString("visitor_history_retry", comment: "Button to retry loading visitor history")) {
                    Task {
                        await viewModel.loadVisitorHistory()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity)
        } else if viewModel.visitors.isEmpty {
            VStack(spacing: 8) {
                Text(NSLocalizedString("visitor_history_empty", comment: "Empty state message when no visitors have accessed the device"))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else {
            content(viewModel.sortedVisitors)
        }
    }
}

struct VisitorHistorySection: View {
    @ObservedObject var viewModel: VisitorHistoryViewModel
    @ObservedObject var deviceStore: KnownDeviceStore
    @ObservedObject var ignoredStore = IgnoredVisitorDeviceStore.shared
    @Binding var pendingDeviceItem: DeviceIDItem?
    let isLandscape: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: isLandscape ? 12 : 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text(NSLocalizedString("visitor_history_title", comment: "Title for visitor history screen"))
            }
            .font(isLandscape ? .headline : .title3)
            
            VisitorHistoryStateView(viewModel: viewModel) { visitors in
                LazyVStack(spacing: 8) {
                    ForEach(visitors, id: \.uniqueID) { visitor in
                        VisitorHistoryRow(
                            visitor: visitor,
                            knownDevice: deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() },
                            isIgnored: ignoredStore.isIgnored(deviceID: visitor.DeviceID),
                            onAddDevice: {
                                pendingDeviceItem = DeviceIDItem(id: visitor.DeviceID, deviceID: visitor.DeviceID)
                            },
                            onIgnore: {
                                ignoredStore.addIgnored(deviceID: visitor.DeviceID)
                            },
                            onUnignore: {
                                ignoredStore.removeIgnored(deviceID: visitor.DeviceID)
                            }
                        )
                        if visitor.uniqueID != visitors.last?.uniqueID {
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct iPhone_VisitorHistoryView: View {
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @StateObject private var viewModel = VisitorHistoryViewModel()
    @ObservedObject private var ignoredStore = IgnoredVisitorDeviceStore.shared
    @State private var pendingDeviceItem: DeviceIDItem? = nil
    
    var body: some View {
        List {
            VisitorHistoryStateView(viewModel: viewModel) { visitors in
                ForEach(visitors, id: \.uniqueID) { visitor in
                    VisitorHistoryRow(
                        visitor: visitor,
                        knownDevice: deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() },
                        isIgnored: ignoredStore.isIgnored(deviceID: visitor.DeviceID),
                        onAddDevice: {
                            pendingDeviceItem = DeviceIDItem(id: visitor.DeviceID, deviceID: visitor.DeviceID)
                        },
                        onIgnore: {
                            ignoredStore.addIgnored(deviceID: visitor.DeviceID)
                        },
                        onUnignore: {
                            ignoredStore.removeIgnored(deviceID: visitor.DeviceID)
                        }
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("visitor_history_title", comment: "Title for visitor history screen"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadVisitorHistory(showLoading: false)
        }
        .onAppear {
            if viewModel.visitors.isEmpty {
                Task {
                    await viewModel.loadVisitorHistory(showLoading: true)
                }
            }
        }
        .sheet(item: $pendingDeviceItem) { item in
            iPhone_AddDeviceView(
                store: deviceStore,
                isPresented: Binding(
                    get: { pendingDeviceItem != nil },
                    set: { if !$0 { pendingDeviceItem = nil } }
                ),
                prefillDeviceID: item.deviceID
            )
            .onDisappear {
                // Refresh visitor history after adding device to show updated name
                Task {
                    await viewModel.loadVisitorHistory(showLoading: false)
                }
            }
        }
    }
}

struct VisitorHistoryRow: View {
    let visitor: MiataruVisitor
    let knownDevice: KnownDevice?
    let isIgnored: Bool
    let onAddDevice: () -> Void
    let onIgnore: () -> Void
    let onUnignore: () -> Void
    
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            // Device color indicator (similar to DeviceRowView)
            if let device = knownDevice {
                if let batteryLevel = cache.getLocation(for: visitor.DeviceID)?.batteryLevel {
                    DeviceBatterySymbol(
                        batteryLevel: batteryLevel,
                        deviceColor: Color(device.DeviceColor ?? UIColor.gray),
                        size: 16
                    )
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.adjustedDeviceColor(Color(device.DeviceColor ?? UIColor.gray), for: colorScheme))
                            .frame(width: 16, height: 16)
                            .shadow(radius: 4)
                    }
                    .frame(width: 16, height: 16)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 4)
                }
                .frame(width: 16, height: 16)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Device name
                HStack(spacing: 4) {
                    if let device = knownDevice {
                        Text(device.DeviceName)
                            .font(.headline)
                            .foregroundColor(colorScheme == .light ? .black : .white)
                    } else {
                        Text(visitor.DeviceID)
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    
                    if isIgnored {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel(Text("visitor_history_ignored_indicator"))
                    }
                }
                
                if knownDevice != nil {
                    // Subtitle: Last seen with timezone (like DeviceRowView)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let subtitle = subtitleText(now: context.date)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if knownDevice == nil {
                    if let primaryUnknownSubtitleText {
                        Text(primaryUnknownSubtitleText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if let secondaryUnknownLocationText {
                        Text(secondaryUnknownLocationText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(unknownVisitAgeText(now: context.date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    // Distance (separate line)
                    let distance = distanceText()
                    Text(distance)
                        .font(.caption2)
                        .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Placemark (like DeviceRowView)
                    let place = placemarkText()
                    Text(place)
                        .font(.caption2)
                        .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .onAppear {
                // Trigger geocoding if needed
                cache.enqueueGeocodingIfNeeded(for: visitor.DeviceID)
                Task {
                    await fetchSloganIfNeeded()
                }
            }
            
            Spacer()
            
            if knownDevice == nil {
                Menu {
                    Button(role: .none) {
                        onAddDevice()
                    } label: {
                        Label("unknown_visitor_add_and_allow", systemImage: "plus.circle")
                    }
                    
                    if isIgnored {
                        Button(role: .none) {
                            onUnignore()
                        } label: {
                            Label("visitor_history_unignore", systemImage: "eye")
                        }
                    } else {
                        Button(role: .destructive) {
                            onIgnore()
                        } label: {
                            Label("allowed_device_list_ignore_button", systemImage: "eye.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: knownDevice == nil ? 84 : 56)
    }
    
    private var visitorSlogan: String? {
        guard let slogan = sloganCache.slogan(for: visitor.DeviceID), !slogan.isEmpty else { return nil }
        return slogan
    }

    private var visitorLocationText: String? {
        if let cached = cache.getLocation(for: visitor.DeviceID) {
            if let locality = cached.locality, let country = cached.country {
                return "\(locality), \(country)"
            }
            if let locality = cached.locality {
                return locality
            }
            if let country = cached.country {
                return country
            }
        }

        if let placemark = cache.getPlacemark(for: visitor.DeviceID) {
            if let locality = placemark.locality, let country = placemark.country {
                return "\(locality), \(country)"
            }
            if let locality = placemark.locality {
                return locality
            }
            if let country = placemark.country {
                return country
            }
        }

        return nil
    }

    private var primaryUnknownSubtitleText: String? {
        visitorSlogan ?? visitorLocationText
    }

    private var secondaryUnknownLocationText: String? {
        guard visitorSlogan != nil else { return nil }
        return visitorLocationText
    }
    
    /// Returns the subtitle string for the visitor row: last seen with timezone and exact date/time
    private func subtitleText(now: Date) -> String {
        let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
        // Relative time using the same helper as DeviceRowView
        let relativeTime = relativeTimeString(from: visitor.TimeStampDate, to: now, unitsStyle: .abbreviated)
        // Add timezone offset if available
        let timezoneOffset = timezoneOffsetString(deviceTimeZone: cache.getTimeZone(for: visitor.DeviceID))
        let relativeTimeWithOffset = timezoneOffset != nil ? "\(relativeTime) (\(timezoneOffset!))" : relativeTime
        
        // Format exact date/time as (hh:mm • dth Month yyyy) - internationalized
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.locale = Locale(identifier: "en_US_POSIX") // Time format is consistent across locales
        let timeString = timeFormatter.string(from: visitor.TimeStampDate)
        
        let currentLocale = Locale.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMMM yyyy"
        dateFormatter.locale = currentLocale
        var dateString = dateFormatter.string(from: visitor.TimeStampDate)
        
        // Add ordinal suffix only for English locales (st, nd, rd, th)
        if currentLocale.language.languageCode?.identifier == "en" {
            // Extract the day number from the formatted date string
            let calendar = Calendar.current
            let day = calendar.component(.day, from: visitor.TimeStampDate)
            let ordinalSuffix = ordinalSuffix(for: day)
            
            // Find the first occurrence of the day number and add ordinal suffix
            // Match day number followed by a space (to avoid matching year)
            if let range = dateString.range(of: "\\b\(day) ", options: .regularExpression) {
                dateString.replaceSubrange(range, with: "\(day)\(ordinalSuffix) ")
            }
        }
        
        let separator = NSLocalizedString("device_row_separator", comment: "Separator between last seen and distance in device row subtitle")
        let exactDateTime = "\(timeString) \(separator) \(dateString)"
        
        return "\(lastSeen): \(relativeTimeWithOffset) (\(exactDateTime))"
    }

    private func unknownVisitAgeText(now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: visitor.TimeStampDate, relativeTo: now)
    }
    
    /// Returns the distance text for the visitor row (separate line)
    private func distanceText() -> String {
        let distanceLabel = NSLocalizedString("device_row_distance", comment: "Label for the distance to the device in the device list row")
        
        guard let visitorCached = cache.getLocation(for: visitor.DeviceID),
              let myCached = cache.getLocation(for: thisDeviceIDManager.shared.deviceID) else {
            let unknown = NSLocalizedString("device_row_unknown", comment: "Default value for unknown distance")
            return "\(distanceLabel): \(unknown)"
        }
        
        let visitorLoc = CLLocation(latitude: visitorCached.latitude, longitude: visitorCached.longitude)
        let myLoc = CLLocation(latitude: myCached.latitude, longitude: myCached.longitude)
        let distance = visitorLoc.distance(from: myLoc) // in meters
        
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
        
        return "\(distanceLabel): \(formattedDistance)"
    }
    
    /// Returns the placemark text (like DeviceRowView)
    private func placemarkText() -> String {
        var placemarkText = ""
        
        // Get placemark from cache
        if let cached = cache.getLocation(for: visitor.DeviceID) {
            if let country = cached.country, let locality = cached.locality {
                placemarkText = "\(locality), \(country)"
            } else if let placemark = cache.getPlacemark(for: visitor.DeviceID),
                      let country = placemark.country, let locality = placemark.locality {
                placemarkText = "\(locality), \(country)"
            }
            
            // Add altitude if available
            if let altitude = cached.altitude {
                let (altitudeValue, altitudeUnit) = formatAltitude(altitude)
                let altitudeLabel = NSLocalizedString("altitude_label", comment: "Altitude label/abbreviation for display in device row")
                if !placemarkText.isEmpty {
                    placemarkText += " (\(altitudeLabel): \(altitudeValue) \(altitudeUnit))"
                } else {
                    placemarkText = "\(altitudeLabel): \(altitudeValue) \(altitudeUnit)"
                }
            }
        }
        
        return placemarkText
    }
    
    /// Returns the ordinal suffix (st, nd, rd, th) for a day number
    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31:
            return "st"
        case 2, 22:
            return "nd"
        case 3, 23:
            return "rd"
        default:
            return "th"
        }
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

    @MainActor
    private func fetchSloganIfNeeded() async {
        guard knownDevice == nil else { return }
        guard let serverURL = URL(string: settings.miataruServerURL) else { return }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }

        await sloganCache.refreshSloganIfStale(
            for: visitor.DeviceID,
            serverURL: serverURL,
            requestingDeviceID: thisDeviceIDManager.shared.deviceID,
            requestingDeviceKey: deviceKey,
            minimumRefreshInterval: 300
        )
    }
}
