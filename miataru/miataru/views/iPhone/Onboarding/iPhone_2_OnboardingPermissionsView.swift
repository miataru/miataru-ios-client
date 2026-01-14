/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_2_OnboardingPermissionsView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import CoreLocation

struct iPhone_2_OnboardingLocationPermissionView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showSettingsAlert = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Location Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("mapandpin")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Location Access")
                            .font(.headline)
                        Text("Miataru needs your location to provide core app functionality, such as sharing your position with trusted contacts.")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        (
                            Text("You do not have to allow location access as you can use basic functions like seeing other device locations without sharing your own location. You can swipe left to continue without enabling the location sharing.\nTo give Miataru the permission please enable the toggle and answer the following dialog with. '")
                            + Text("Allow While Using App").bold()
                            + Text("'.")
                        )
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    }
                }
                HStack(spacing: 12) {
                    Text("Location Tracking")
                    Toggle("", isOn: Binding(
                        get: { settings.trackAndReportLocation },
                        set: { newValue in
                            if newValue {
                                // Check if permission was previously denied
                                let currentStatus = locationManager.authorizationStatus
                                if currentStatus == .denied || currentStatus == .restricted {
                                    // Show alert before opening Settings
                                    showSettingsAlert = true
                                } else {
                                    // Permission not determined or already granted, request normally
                                    settings.trackAndReportLocation = newValue
                                    locationManager.requestLocationPermission()
                                }
                            } else {
                                settings.trackAndReportLocation = newValue
                            }
                        }
                    ))
                    .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .alert(NSLocalizedString("location_permission_open_settings_title", comment: "Alert title when redirecting to Settings for location permission"), isPresented: $showSettingsAlert) {
                    Button(NSLocalizedString("cancel", comment: "Cancel button"), role: .cancel) {
                        // User cancelled, keep toggle off
                        settings.trackAndReportLocation = false
                    }
                    Button(NSLocalizedString("location_permission_open_settings_button", comment: "Button to open Settings for location permission")) {
                        // User confirmed, open Settings
                        settings.trackAndReportLocation = true
                        LocationManager.shared.openAppSettings()
                    }
                } message: {
                    Text(NSLocalizedString("location_permission_open_settings_message", comment: "Explanation message when redirecting to Settings for location permission"))
                }
            }
            Text("").padding(.bottom,16)
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
    
    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Allowed (Always)"
        case .authorizedWhenInUse: return "Allowed (When In Use)"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }
    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .gray
        @unknown default: return .gray
        }
    }
}

#Preview {
    iPhone_2_OnboardingLocationPermissionView()
} 
