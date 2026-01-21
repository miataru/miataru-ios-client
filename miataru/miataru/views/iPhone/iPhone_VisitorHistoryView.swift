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

struct iPhone_VisitorHistoryView: View {
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var visitors: [MiataruVisitor] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showAddDeviceSheet = false
    @State private var pendingDeviceID: String? = nil
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button(NSLocalizedString("visitor_history_retry", comment: "Button to retry loading visitor history")) {
                        Task {
                            await loadVisitorHistory()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if visitors.isEmpty {
                VStack(spacing: 8) {
                    Text(NSLocalizedString("visitor_history_empty", comment: "Empty state message when no visitors have accessed the device"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ForEach(sortedVisitors, id: \.uniqueID) { visitor in
                    VisitorHistoryRow(
                        visitor: visitor,
                        knownDevice: deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() },
                        onAddDevice: {
                            pendingDeviceID = visitor.DeviceID
                            showAddDeviceSheet = true
                        }
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("visitor_history_title", comment: "Title for visitor history screen"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadVisitorHistory()
        }
        .onAppear {
            if visitors.isEmpty {
                Task {
                    await loadVisitorHistory()
                }
            }
        }
        .sheet(isPresented: $showAddDeviceSheet, onDismiss: {
            pendingDeviceID = nil
            // Refresh visitor history after adding device to show updated name
            Task {
                await loadVisitorHistory()
            }
        }) {
            if let deviceID = pendingDeviceID {
                iPhone_AddDeviceView(
                    store: deviceStore,
                    isPresented: $showAddDeviceSheet,
                    prefillDeviceID: deviceID
                )
            }
        }
        .onReceive(deviceStore.$devices) { _ in
            // Refresh when devices are added/updated to show updated names
            if !visitors.isEmpty {
                // Trigger view update by accessing sortedVisitors
                _ = sortedVisitors
            }
        }
    }
    
    private var sortedVisitors: [MiataruVisitor] {
        visitors.sorted { $0.TimeStampDate > $1.TimeStampDate }
    }
    
    private func loadVisitorHistory() async {
        guard let url = URL(string: settings.miataruServerURL) else {
            await MainActor.run {
                errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let ourDeviceId = thisDeviceIDManager.shared.deviceID
            // Request with nil amount to get all available from server
            let response = try await MiataruAPIClient.getVisitorHistoryWithConfig(
                serverURL: url,
                forDeviceID: ourDeviceId,
                amount: nil
            )
            
            await MainActor.run {
                // #region agent log
                let currentTime = Date()
                let visitorTimestamps = response.MiataruVisitors.map { [
                    "deviceID": $0.DeviceID,
                    "timeStamp": $0.TimeStamp,
                    "timeStampDate": $0.TimeStampDate.timeIntervalSince1970,
                    "secondsAgo": currentTime.timeIntervalSince($0.TimeStampDate)
                ] }
                let logData: [String: Any] = [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "D",
                    "location": "iPhone_VisitorHistoryView.swift:112",
                    "message": "Visitor history loaded",
                    "data": [
                        "currentTime": currentTime.timeIntervalSince1970,
                        "visitorCount": response.MiataruVisitors.count,
                        "availableVisitorHistory": response.MiataruServerConfig.AvailableVisitorHistory,
                        "maximumVisitorHistory": response.MiataruServerConfig.MaximumNumberOfVisitorHistory,
                        "visitors": visitorTimestamps
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    let logPath = URL(fileURLWithPath: "/Users/bietiekay/code/miataru-ios-app/miataru/.cursor/debug.log")
                    if let fileHandle = try? FileHandle(forWritingTo: logPath) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write((jsonString + "\n").data(using: .utf8)!)
                        fileHandle.closeFile()
                    } else {
                        try? (jsonString + "\n").write(to: logPath, atomically: true, encoding: .utf8)
                    }
                }
                // #endregion
                self.visitors = response.MiataruVisitors
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = NSLocalizedString("visitor_history_error", comment: "Error message when visitor history fails to load")
                self.isLoading = false
            }
            debugLog("[iPhone_VisitorHistoryView] Failed to load visitor history: \(error)")
        }
    }
}

struct VisitorHistoryRow: View {
    let visitor: MiataruVisitor
    let knownDevice: KnownDevice?
    let onAddDevice: () -> Void
    
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
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
                if let device = knownDevice {
                    Text(device.DeviceName)
                        .font(.headline)
                        .foregroundColor(colorScheme == .light ? .black : .white)
                } else {
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("unknown_device_label", comment: "Label for unknown/unrecognized device"))
                            .font(.headline)
                            .foregroundColor(colorScheme == .light ? .black : .white)
                        Text(shortenedDeviceID(visitor.DeviceID))
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Subtitle: Last seen with timezone (like DeviceRowView)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let subtitle = subtitleText(now: context.date)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                // Placemark (like DeviceRowView)
                let place = placemarkText()
                Text(place)
                    .font(.caption)
                    .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .onAppear {
                // Trigger geocoding if needed
                cache.enqueueGeocodingIfNeeded(for: visitor.DeviceID)
            }
            
            Spacer()
            
            if knownDevice == nil {
                Button(action: onAddDevice) {
                    Text(NSLocalizedString("add_device_action", comment: "Button label to add an unknown device"))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(NSLocalizedString("add_device_action", comment: "Button label to add an unknown device"))
                .accessibilityHint(NSLocalizedString("add_device_accessibility_hint", comment: "Accessibility hint for add device button"))
            }
        }
        .padding(.vertical, 4)
        .frame(height: 56)
    }
    
    private func shortenedDeviceID(_ deviceID: String) -> String {
        guard deviceID.count > 10 else { return deviceID }
        let start = String(deviceID.prefix(6))
        let end = String(deviceID.suffix(4))
        return "\(start)...\(end)"
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
}
