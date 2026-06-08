/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_LocationStatusView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import CoreLocation
import UIKit

struct iPhone_LocationStatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var backgroundManager = LocationManager.shared
    @ObservedObject private var routeCounter = RouteRequestCounter.shared
    @ObservedObject private var widgetRequestCounter = WidgetRequestCounter.shared
    @ObservedObject private var apiRequestCounter = APIRequestCounter.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isFlushingQueuedLocationUpdates = false
    @State private var showingLocationDiagnosticsSheet = false
    // Legacy @AppStorage fields removed in favor of RouteRequestCounter
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
            HStack {
                Text(NSLocalizedString("Version", comment: "Label for app version on location status screen"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(appVersionText)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .contentShape(Rectangle())
            .onTapGesture(count: 3) {
                showingLocationDiagnosticsSheet = true
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("location_status_version_section")
            // Status-Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("Location Tracking Status", comment: "Header for location tracking status section"))
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(trackingModeText)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Tracking Toggle
                Toggle("location_track", isOn: $settings.trackAndReportLocation)
                    .labelsHidden()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            if settings.allowedDeviceListEnabled {
                AllowedDeviceListStatusCard()
            }

            PermissionStatusView(status: locationManager.authorizationStatus)
            
            // Hinweistext für Hintergrund-Tracking
            if isInBackground {
                Text(backgroundLocationHintText)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
            
            // Detaillierte Informationen
            if settings.trackAndReportLocation {
                VStack(spacing: 12) {
                    // Aktuelle Location
                    if let location = locationManager.currentLocation {
                        LocationInfoRow(
                            title: NSLocalizedString("Current location", comment: "Current position display in Location Tracking Details"),
                            value: String(format: "%.6f, %.6f",
                                        location.coordinate.latitude, 
                                        location.coordinate.longitude),
                            icon: "location.fill"
                        )
                        
                        LocationInfoRow(
                            title: NSLocalizedString("Accuracy", comment: "Accuracy display in Location Tracking Details"),
                            value: String(format: "%.1f m", location.horizontalAccuracy),
                            icon: "target"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Altitude (sea level)", comment: "Altitude above sea level display in Location Tracking Details"),
                            value: altitudeText(for: location),
                            icon: "arrow.up.and.down.circle"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Route requests", comment: "Number of route requests counter in Location Tracking Details"),
                            value: String(routeCounter.count),
                            icon: "map"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Widget requests (today)", comment: "Number of widget-initiated requests today in Location Tracking Details"),
                            value: String(widgetRequestCounter.countToday),
                            icon: "square.on.square"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Updated location calls (today)", comment: "Number of UpdateLocation calls today in Location Tracking Details"),
                            value: String(apiRequestCounter.updatedLocationCallsToday),
                            icon: "arrow.up.circle"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("GetVisitorHistory calls (today)", comment: "Number of GetVisitorHistory calls today in Location Tracking Details"),
                            value: String(apiRequestCounter.getVisitorHistoryCallsToday),
                            icon: "person.2"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("GetLocation calls (today)", comment: "Number of GetLocation calls today in Location Tracking Details"),
                            value: String(apiRequestCounter.getLocationCallsToday),
                            icon: "location"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("GetLocationHistory calls (today)", comment: "Number of GetLocationHistory calls today in Location Tracking Details"),
                            value: String(apiRequestCounter.getLocationHistoryCallsToday),
                            icon: "clock.arrow.circlepath"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Speed", comment: "Speed display in Location Tracking Details"),
                            value: speedText(for: location),
                            icon: "speedometer"
                        )

                        LocationInfoRow(
                            title: NSLocalizedString("Battery level", comment: "Battery level display in Location Tracking Details"),
                            value: batteryLevelText,
                            icon: "battery.100"
                        )
                    }

                    LocationInfoRow(
                        title: NSLocalizedString("Queued location updates", comment: "Number of locally queued UpdateLocation records waiting to be sent"),
                        value: String(locationManager.pendingLocationUpdateCount),
                        icon: "tray.and.arrow.up"
                    )

                    if locationManager.pendingLocationUpdateCount > 1 {
                        Button {
                            flushQueuedLocationUpdates()
                        } label: {
                            Label(
                                "location_update_outbox_flush_button",
                                systemImage: isFlushingQueuedLocationUpdates ? "arrow.clockwise" : "paperplane"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isFlushingQueuedLocationUpdates)
                        .accessibilityIdentifier("location_status_flush_outbox_button")
                    }
                    
                    // Letzte Updates
                    if let lastUpdate = locationManager.lastUpdateTime {
                        LocationInfoRow(
                            title: NSLocalizedString("Last GPS update", comment: "Last GPS update"),
                            value: formatDate(lastUpdate),
                            icon: "clock"
                        )
                    }
                    
                    if let lastServerUpdate = locationManager.lastServerUpdate {
                        LocationInfoRow(
                            title: NSLocalizedString("Last server update", comment: "Last Server-Update status line in Location Tracking details"),
                            value: formatDate(lastServerUpdate),
                            icon: "network"
                        )
                    }
                    
                    // Server-Status
                    ServerStatusRow(status: locationManager.serverUpdateStatus)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Background Status
            BackgroundStatusCard()
            
            // Log der letzten Updates
            if !updateLog.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("Recent location updates:", comment: "Header for recent location updates log"))
                        .font(.caption)
                    ForEach(updateLog, id: \ .timestamp) { entry in
                        HStack {
                            Text(formatDate(entry.timestamp))
                                .font(.caption2)
                            Text(entry.mode)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            Button {
                UserDefaults.standard.hasCompletedOnboarding = false
                appState.presentFullOnboarding(skipPostUpdate: true)
            } label: {
                Text("Show Onboarding Wizard Again")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .accessibilityIdentifier("settings_show_onboarding_again_button")
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 10)
        }
        .sheet(isPresented: $showingLocationDiagnosticsSheet) {
            NavigationStack {
                ScrollView {
                    LocationDiagnosticsCard()
                        .padding()
                }
                .accessibilityIdentifier("location_diagnostics_sheet")
                .navigationTitle("Location diagnostics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingLocationDiagnosticsSheet = false
                        }
                        .accessibilityIdentifier("location_diagnostics_done_button")
                    }
                }
            }
        }
        .accessibilityIdentifier("screen_location_tracking_details")
        .onAppear {
            refreshAllStatistics()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshAllStatistics()
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshAllStatistics()
        }
    }
    
    /// Refreshes route, widget, and API statistics so displayed daily counts stay correct.
    private func refreshAllStatistics() {
        routeCounter.checkAndResetIfNeeded()
        widgetRequestCounter.updateCount()
        apiRequestCounter.updateCounts()
    }

    private func flushQueuedLocationUpdates() {
        guard !isFlushingQueuedLocationUpdates else { return }
        isFlushingQueuedLocationUpdates = true
        Task {
            await LocationManager.shared.flushPendingLocationUpdatesNow()
            await MainActor.run {
                refreshAllStatistics()
                isFlushingQueuedLocationUpdates = false
            }
        }
    }
    
    // MARK: - Computed Properties
    private var statusIcon: String {
        if !settings.trackAndReportLocation {
            return "location.slash"
        }
        
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? "location.fill" : "location"
        case .authorizedWhenInUse:
            return "location"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location.slash"
        @unknown default:
            return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        if !settings.trackAndReportLocation {
            return .gray
        }
        
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? .green : .orange
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        @unknown default:
            return .red
        }
    }
    
    private var statusText: String {
        if !settings.trackAndReportLocation {
            return NSLocalizedString("Location tracking deactivated", comment: "Location Tracking Status statusText")
        }
        
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? NSLocalizedString("Tracking inactive (fore- & background)", comment: "Location Tracking Status statusText") : NSLocalizedString("Permission granted, but not active", comment: "Location Tracking Status statusText")
        case .authorizedWhenInUse:
            return NSLocalizedString("Only allowed when app in foregrond", comment: "Location Tracking Status statusText")
        case .denied:
            return NSLocalizedString("Location access denied", comment: "Location Tracking Status statusText")
        case .restricted:
            return NSLocalizedString("Location access restricted", comment: "Location Tracking Status statusText")
        case .notDetermined:
            return NSLocalizedString("Permission not determined", comment: "Location Tracking Status statusText")
        @unknown default:
            return NSLocalizedString("Location services not available", comment: "Location Tracking Status statusText")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var appVersionText: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return String(format: "%@ (%@ %@)", version, NSLocalizedString("Build", comment: "Build number label"), build)
    }
    
    // Tracking-Modus-Text
    private var trackingModeText: String {
        trackingModeText(for: locationManager.currentBackgroundTrackingDisplayMode)
    }
    
    // Ist die App im Hintergrund?
    private var isInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    private var backgroundLocationHintText: String {
        switch locationManager.currentBackgroundTrackingDisplayMode {
        case .manualFrequent, .smartFrequent:
            let format = NSLocalizedString("frequent_background_location_updates_active_hint_format", comment: "Hint shown when frequent background updates are active")
            return String(format: format, settings.frequentBackgroundLocationDistanceFilter)
        case .smartWaiting:
            return NSLocalizedString("smart_frequent_background_waiting_hint", comment: "Hint shown when smart frequent background updates are waiting for movement")
        case .significantChange, .foregroundLive:
            return NSLocalizedString("Location updates in the background use the battery-saving standard mode.", comment: "Hint for battery-saving standard background location update behavior")
        }
    }
    
    // Log der letzten Updates (Dummy-Implementierung, sollte mit echten Daten aus LocationManager ersetzt werden)
    private var updateLog: [LocationManager.UpdateLogEntry] {
        locationManager.updateLog
    }

    private func speedText(for location: CLLocation) -> String {
        let metersPerSecond = location.speed
        if metersPerSecond >= 0 {
            let kilometersPerHour = metersPerSecond * 3.6
            return String(format: "%.1f km/h", kilometersPerHour)
        } else {
            return NSLocalizedString("Unknown", comment: "Unknown speed value in Location Tracking Details")
        }
    }

    private func trackingModeText(for mode: LocationManager.BackgroundTrackingDisplayMode) -> String {
        switch mode {
        case .foregroundLive:
            return NSLocalizedString("Tracking mode: Live (GPS)", comment: "Tracking mode text for foreground mode")
        case .manualFrequent:
            let format = NSLocalizedString("tracking_mode_manual_frequent_background_updates_format", comment: "Tracking mode text for manually enabled frequent background updates")
            return String(format: format, settings.frequentBackgroundLocationDistanceFilter)
        case .smartFrequent:
            let format = NSLocalizedString("tracking_mode_smart_frequent_background_updates_format", comment: "Tracking mode text for smart frequent background updates")
            return String(format: format, settings.frequentBackgroundLocationDistanceFilter)
        case .smartWaiting:
            return NSLocalizedString("tracking_mode_smart_waiting", comment: "Tracking mode text when smart frequent background updates are waiting")
        case .significantChange:
            return NSLocalizedString("tracking_mode_battery_saving_standard", comment: "Tracking mode text for battery-saving standard background mode")
        }
    }

    private var batteryLevelText: String {
        let device = UIDevice.current
        let wasMonitoringEnabled = device.isBatteryMonitoringEnabled
        if !wasMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        defer { if !wasMonitoringEnabled { device.isBatteryMonitoringEnabled = false } }
        let level = device.batteryLevel
        if level < 0 {
            return NSLocalizedString("Unknown", comment: "Unknown battery level in Location Tracking Details")
        }
        let percent = Int(level * 100)
        return "\(percent) %"
    }

    private func altitudeText(for location: CLLocation) -> String {
        let verticalAccuracy = location.verticalAccuracy
        if verticalAccuracy >= 0 {
            return String(format: "%.1f m", location.altitude)
        } else {
            return NSLocalizedString("Unknown", comment: "Unknown altitude value in Location Tracking Details")
        }
    }
}

// MARK: - Daily reset helpers
extension iPhone_LocationStatusView {}

// MARK: - Supporting Views
struct LocationInfoRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct ServerStatusRow: View {
    let status: LocationManager.ServerUpdateStatus
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            Text(NSLocalizedString("Miataru server status", comment: "Server Status Row"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
    }
    
    private var statusIcon: String {
        switch status {
        case .idle:
            return "circle"
        case .updating:
            return "arrow.clockwise"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .updating:
            return .blue
        case .success:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var statusText: String {
        switch status {
        case .idle:
            return NSLocalizedString("Ready", comment: "statusText LocationTracking Status")
        case .updating:
            return NSLocalizedString("Sending...", comment: "statusText LocationTracking Status")
        case .success:
            return NSLocalizedString("Successful", comment: "statusText LocationTracking Status")
        case .failed(let error):
            return NSLocalizedString("Error: \(error)", comment: "statusText LocationTracking Status")
        }
    }
}

struct PermissionStatusView: View {
    let status: CLAuthorizationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("location_permission_state_title")
                .font(.headline)
            
            HStack {
                Image(systemName: permissionIcon)
                    .foregroundColor(permissionColor)
                
                Text(permissionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if status != .authorizedAlways {
                Text("always_location_permission_required_message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("always_location_permission_required_steps")
                    .font(.caption2)
                    .foregroundColor(status == .denied || status == .restricted ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityIdentifier("location_status_location_access_control_card")
    }
    
    private var permissionIcon: String {
        switch status {
        case .authorizedAlways:
            return "checkmark.shield.fill"
        case .authorizedWhenInUse:
            return "checkmark.shield"
        case .denied, .restricted:
            return "xmark.shield.fill"
        case .notDetermined:
            return "questionmark.shield"
        @unknown default:
            return "exclamationmark.shield"
        }
    }
    
    private var permissionColor: Color {
        switch status {
        case .authorizedAlways:
            return .green
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        @unknown default:
            return .red
        }
    }
    
    private var permissionText: String {
        switch status {
        case .authorizedAlways:
            return NSLocalizedString("Full permissions granted", comment: "permission text in Location Tracking Status")
        case .authorizedWhenInUse:
            return NSLocalizedString("Only allowed when app in foregrond", comment: "permission text in Location Tracking Status")
        case .denied:
            return NSLocalizedString("Location access denied", comment: "permission text in Location Tracking Status")
        case .restricted:
            return NSLocalizedString("Location access restricted", comment: "permission text in Location Tracking Status")
        case .notDetermined:
            return NSLocalizedString("Permission not determined", comment: "permission text in Location Tracking Status")
        @unknown default:
            return NSLocalizedString("Location services not available", comment: "permission text in Location Tracking Status")
        }
    }
}

struct BackgroundStatusCard: View {
    @ObservedObject private var backgroundManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text(NSLocalizedString("background_status_header", comment: "Header for background location status card"))
                    .font(.headline)
                Spacer()
            }
            
            statusRow(
                title: NSLocalizedString("background_updates_label", comment: "Label for number of background updates"),
                value: "\(backgroundManager.backgroundUpdateCount)",
                icon: "arrow.clockwise.circle.fill"
            )

            statusRow(
                title: NSLocalizedString("location_update_count_foreground_live_label", comment: "Label for foreground live location update count"),
                value: "\(backgroundManager.locationUpdateModeCounts.foregroundLive)",
                icon: "location.fill"
            )

            statusRow(
                title: NSLocalizedString("location_update_count_significant_change_label", comment: "Label for significant-change location update count"),
                value: "\(backgroundManager.locationUpdateModeCounts.significantChange)",
                icon: "leaf.fill"
            )

            statusRow(
                title: NSLocalizedString("location_update_count_smart_frequent_label", comment: "Label for smart frequent location update count"),
                value: "\(backgroundManager.locationUpdateModeCounts.smartFrequent)",
                icon: "sparkles"
            )

            statusRow(
                title: NSLocalizedString("location_update_count_manual_frequent_label", comment: "Label for manually frequent location update count"),
                value: "\(backgroundManager.locationUpdateModeCounts.manualFrequent)",
                icon: "hand.tap.fill"
            )
            
            if let lastUpdate = backgroundManager.lastBackgroundUpdate {
                statusRow(
                    title: NSLocalizedString("last_background_update_label", comment: "Label for timestamp of the last background update"),
                    value: formatTime(lastUpdate),
                    icon: "clock.fill"
                )
            }

            statusRow(
                title: NSLocalizedString("background_tracking_mode_title", comment: "Label for current background tracking mode"),
                value: backgroundTrackingModeText,
                icon: "slider.horizontal.3"
            )

            if settings.frequentBackgroundLocationUpdatesEnabled {
                statusRow(
                    title: NSLocalizedString("background_tracking_expires_at_label", comment: "Label for frequent background tracking expiration time"),
                    value: backgroundTrackingExpirationText,
                    icon: "timer"
                )
            }

            if settings.smartFrequentBackgroundLocationUpdatesEnabled {
                statusRow(
                    title: NSLocalizedString("smart_frequent_background_last_activation_label", comment: "Label for the latest smart frequent activation reason"),
                    value: backgroundManager.smartFrequentBackgroundLastActivationReason ?? NSLocalizedString("smart_frequent_background_no_activation_yet", comment: "No smart frequent activation has happened yet"),
                    icon: "bolt.fill"
                )

                statusRow(
                    title: NSLocalizedString("smart_frequent_background_last_movement_label", comment: "Label for the latest relevant smart frequent movement"),
                    value: smartMovementText,
                    icon: "speedometer"
                )

                statusRow(
                    title: NSLocalizedString("smart_frequent_background_next_timeout_label", comment: "Label for the next smart frequent inactivity timeout"),
                    value: smartTimeoutText,
                    icon: "hourglass"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }

    private var backgroundTrackingModeText: String {
        switch backgroundManager.currentBackgroundTrackingDisplayMode {
        case .foregroundLive:
            return NSLocalizedString("background_tracking_mode_foreground_live", comment: "Background status text for foreground live mode")
        case .manualFrequent:
            let format = NSLocalizedString("background_tracking_mode_frequent_format", comment: "Background status text for frequent update mode")
            return String(format: format, settings.frequentBackgroundLocationDistanceFilter)
        case .smartFrequent:
            let format = NSLocalizedString("background_tracking_mode_smart_frequent_format", comment: "Background status text for smart frequent update mode")
            return String(format: format, settings.frequentBackgroundLocationDistanceFilter)
        case .smartWaiting:
            return NSLocalizedString("background_tracking_mode_smart_waiting", comment: "Background status text for smart frequent waiting mode")
        case .significantChange:
            return NSLocalizedString("background_tracking_mode_significant_change", comment: "Background status text for significant-change mode")
        }
    }

    private var backgroundTrackingExpirationText: String {
        guard let expiresAt = settings.frequentBackgroundLocationUpdatesExpiresAt else {
            return NSLocalizedString("background_tracking_expires_never", comment: "Frequent background tracking never expires")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: expiresAt)
    }

    private var smartMovementText: String {
        guard let date = backgroundManager.smartFrequentBackgroundLastRelevantMovementAt else {
            return NSLocalizedString("smart_frequent_background_no_movement_yet", comment: "No smart frequent movement has been recorded yet")
        }
        return formatTime(date)
    }

    private var smartTimeoutText: String {
        guard let date = backgroundManager.smartFrequentBackgroundNextInactivityTimeoutAt else {
            return NSLocalizedString("smart_frequent_background_no_timeout_pending", comment: "No smart frequent inactivity timeout is pending")
        }
        return formatTime(date)
    }
}

struct LocationDiagnosticsCard: View {
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var diagnosticsLog = LocationDiagnosticsLogStore.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("Location diagnostics")
                    .font(.headline)
                Spacer()
                Toggle("Location diagnostics logging", isOn: $settings.locationDiagnosticsLoggingEnabled)
                    .labelsHidden()
                    .accessibilityIdentifier("location_diagnostics_logging_toggle")
            }

            Text("Records selected location-tracking decisions for later export. Existing entries remain until cleared.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            statusRow(
                title: NSLocalizedString("location_diagnostics_entries_title", comment: "Number of entries in the location diagnostics log"),
                value: "\(diagnosticsLog.entries.count) / \(LocationDiagnosticsLogStore.defaultMaxEntries) (+\(diagnosticsLog.coalescedCounts.count) summaries)",
                icon: "list.bullet.rectangle"
            )

            statusRow(
                title: "Oldest evidence",
                value: oldestEvidenceText,
                icon: "calendar"
            )

            statusRow(
                title: "Current expected mode",
                value: locationManager.backgroundTrackingForensicState.currentExpectedMode ?? "unknown",
                icon: "location"
            )

            statusRow(
                title: "Last background callback",
                value: optionalTime(locationManager.backgroundTrackingForensicState.lastBackgroundCallbackAt),
                icon: "arrow.down.circle"
            )

            statusRow(
                title: "Last background upload",
                value: optionalTime(locationManager.backgroundTrackingForensicState.lastBackgroundUploadAt),
                icon: "arrow.up.circle"
            )

            if let latestGap = latestGapEntry {
                statusRow(
                    title: "Latest background gap",
                    value: "\(latestGap.result) - \(formatTime(latestGap.timestamp))",
                    icon: latestGap.level == .warning ? "exclamationmark.triangle" : "moon"
                )
            }

            if let latestEntry = diagnosticsLog.entries.last {
                statusRow(
                    title: NSLocalizedString("location_diagnostics_last_event_title", comment: "Title for the latest location diagnostics event"),
                    value: "\(latestEntry.event): \(latestEntry.result)",
                    icon: "clock"
                )
            }

            if let rearmStatus = locationManager.lastSignificantChangeRearmStatus {
                statusRow(
                    title: NSLocalizedString("location_diagnostics_rearm_title", comment: "Title for the significant-change location monitor re-arm status"),
                    value: rearmStatusText(rearmStatus),
                    icon: rearmStatus.result == .attempted ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle"
                )
            }

            HStack {
                Button {
                    exportDiagnostics()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(diagnosticsLog.entries.isEmpty)
                .accessibilityIdentifier("location_diagnostics_export_button")

                Button(role: .destructive) {
                    diagnosticsLog.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(diagnosticsLog.entries.isEmpty)
                .accessibilityIdentifier("location_diagnostics_clear_button")
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if !diagnosticsLog.entries.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent diagnostics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(recentDiagnosticEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(formatTime(entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(entry.event)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(entry.result)
                                    .font(.caption2)
                                    .foregroundColor(color(for: entry.level))
                            }
                            Text(entry.summary)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let failedCheck = entry.checks.first(where: { !$0.passed }) {
                                Text(failedCheck.detail)
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if let reason = entry.reason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ActivityView(activityItems: [exportURL])
            }
        }
    }

    @ViewBuilder
    private func statusRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }

    private func exportDiagnostics() {
        do {
            exportURL = try diagnosticsLog.writeTemporaryExportFile()
            exportError = nil
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var recentDiagnosticEntries: [LocationDiagnosticsLogEntry] {
        Array(diagnosticsLog.entries.suffix(40))
            .sorted { lhs, rhs in
                if lhs.retentionClass != rhs.retentionClass {
                    return lhs.retentionClass == .critical
                }
                return lhs.timestamp > rhs.timestamp
            }
            .prefix(20)
            .map { $0 }
    }

    private var latestGapEntry: LocationDiagnosticsLogEntry? {
        diagnosticsLog.entries.last { $0.event == "backgroundTrackingGap" || $0.event == "foregroundRecoveryBurst" }
    }

    private var oldestEvidenceText: String {
        guard let oldest = diagnosticsLog.entries.map(\.timestamp).min() else {
            return "none"
        }
        return formatTime(oldest)
    }

    private func rearmStatusText(_ status: LocationSignificantChangeRearmStatus) -> String {
        "\(status.result.rawValue) - \(status.reason) - \(formatTime(status.timestamp))"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func optionalTime(_ date: Date?) -> String {
        guard let date else { return "none" }
        return formatTime(date)
    }

    private func color(for level: LocationDiagnosticsLogLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
#Preview {
    iPhone_LocationStatusView()
} 
