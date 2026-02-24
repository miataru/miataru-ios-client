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
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var backgroundManager = LocationManager.shared
    @ObservedObject private var routeCounter = RouteRequestCounter.shared
    @ObservedObject private var widgetRequestCounter = WidgetRequestCounter.shared
    @ObservedObject private var apiRequestCounter = APIRequestCounter.shared
    @ObservedObject private var settings = SettingsManager.shared
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
            
            // Hinweistext für Hintergrund-Tracking
            if isInBackground {
                Text(NSLocalizedString("Location updates in the background are only detected when they are significant (>500m).", comment: "Hint for background location update behavior"))
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
            
            // Berechtigungs-Status
            PermissionStatusView(status: locationManager.authorizationStatus)
            
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
            }
            .padding()
        }
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 10)
        }
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
        if isInBackground {
            return NSLocalizedString("Tracking mode: Battery saving (only significant movements)", comment: "Tracking mode text for background mode")
        } else {
            return NSLocalizedString("Tracking mode: Live (GPS)", comment: "Tracking mode text for foreground mode")
        }
    }
    
    // Ist die App im Hintergrund?
    private var isInBackground: Bool {
        UIApplication.shared.applicationState == .background
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
            Text("Permission state")
                .font(.headline)
            
            HStack {
                Image(systemName: permissionIcon)
                    .foregroundColor(permissionColor)
                
                Text(permissionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if status == .denied || status == .restricted {
                Text("Open app settings in iOS to change location permission state.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.purple)
                Text(NSLocalizedString("background_status_header", comment: "Header for background location status card"))
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Text(NSLocalizedString("background_updates_label", comment: "Label for number of background updates"))
                Spacer()
                Text("\(backgroundManager.backgroundUpdateCount)", comment: "Number of background updates")
                    .foregroundColor(.secondary)
            }
            
            if let lastUpdate = backgroundManager.lastBackgroundUpdate {
                HStack {
                    Text(NSLocalizedString("last_background_update_label", comment: "Label for timestamp of the last background update"))
                    Spacer()
                    Text(formatTime(lastUpdate))
                        .foregroundColor(.secondary)
                }
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
}
#Preview {
    iPhone_LocationStatusView()
} 
