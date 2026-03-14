/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_SettingsView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var showingDeviceKeySheet = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("track_and_history")) {
                    Toggle("location_track", isOn: $settings.trackAndReportLocation)
                    SettingsDescriptionText("explanation_location_track")

                    if settings.trackAndReportLocation {
                        Toggle("save_location_history_to_server", isOn: $settings.saveLocationHistoryOnServer)
                        SettingsDescriptionText("explanation_save_location_history_to_server")

                        Toggle(
                            "unknown_visitor_alerts_toggle",
                            isOn: Binding(
                                get: { settings.unknownVisitorAlertsEnabled },
                                set: { newValue in
                                    updateUnknownVisitorAlerts(newValue)
                                }
                            )
                        )
                        .disabled(isUpdatingUnknownVisitorAlerts)
                        SettingsDescriptionText("explanation_unknown_visitor_alerts_toggle")

                        if settings.unknownVisitorAlertsPermissionDenied {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("unknown_visitor_alerts_permission_denied_message")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Button("unknown_visitor_alerts_open_settings_button") {
                                    LocationManager.shared.openAppSettings()
                                }
                                .font(.caption)
                            }
                        }

                        if !settings.saveLocationHistoryOnServer {
                            Picker("store_history_before_autoremove", selection: $settings.locationDataRetentionTime) {
                                Text("30minutes").tag(30)
                                Text("1hour").tag(60)
                                Text("2hours").tag(120)
                                Text("6hours").tag(360)
                                Text("12hours").tag(720)
                                Text("24hours").tag(1440)
                                Text("7days").tag(10_080)
                            }
                            SettingsDescriptionText("explanation_store_history_before_autoremove")
                        }
                    }

                    Button {
                        showingDeviceKeySheet = true
                    } label: {
                        HStack {
                            Image(systemName: "key.card")
                                .foregroundColor(.blue)
                            Text("manage_your_devicekey")
                        }
                    }
                }

                if !settings.allowedDeviceListEnabled {
                    Section(header: Text("allowed_device_list_section_title")) {
                        AllowedDeviceListSettingsContent()
                    }
                }

                Section(header: Text("app_behaviour")) {
                    Toggle("deactivate_device_lock", isOn: $settings.disableDeviceAutolock)
                    SettingsDescriptionText("explanation_deactivate_device_lock")

                    Toggle("prevent_screen_rotation", isOn: $settings.preventScreenRotation)
                    SettingsDescriptionText("explanation_prevent_screen_rotation")
                }

                Section(header: Text("map_configuration")) {
                    Picker("map_type", selection: $settings.mapType) {
                        Text("default_map").tag(1)
                        Text("hybrid_map").tag(2)
                        Text("sat_map").tag(3)
                    }
                    SettingsDescriptionText("explanation_map_type")

                    Picker("map_zoom_level", selection: $settings.mapZoomLevel) {
                        Text("1km").tag(1)
                        Text("2km").tag(2)
                        Text("5km").tag(5)
                        Text("10km").tag(10)
                        Text("25km").tag(25)
                        Text("50km").tag(50)
                        Text("100km").tag(100)
                    }
                    SettingsDescriptionText("explanation_map_zoom_level")
                }

                Section(header: Text("navigation")) {
                    Picker("transport_mode", selection: $settings.navigationTransportType) {
                        Text("transport_walk").tag(0)
                        Text("transport_car").tag(2)
                        Text("transport_transit").tag(3)
                    }
                    SettingsDescriptionText("explanation_navigation_mode")
                }

                Section(header: Text("server_url")) {
                    TextField("server_url", text: $settings.miataruServerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                    SettingsDescriptionText("explanation_server_url")
                }

                Section(header: Text("advanced_options_and_tracking_status")) {
                    NavigationLink(destination: iPhone_AdvancedOptionsView()) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.blue)
                            Text("advanced_options")
                        }
                        .accessibilityIdentifier("settings_advanced_options_link")
                    }

                    NavigationLink(destination: iPhone_LocationStatusView()
                        .navigationTitle("Location Tracking Details")
                        .navigationBarTitleDisplayMode(.inline)) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Location Tracking Details")
                        }
                        .accessibilityIdentifier("settings_location_tracking_details_link")
                    }
                }
            }
            .navigationTitle("settings")
            .sheet(isPresented: $showingDeviceKeySheet) {
                iPhone_DeviceKeySheetView(showsMismatchWarning: false)
            }
        }
        .accessibilityIdentifier("settings_navigation_view")
    }

    @State private var isUpdatingUnknownVisitorAlerts = false

    private func updateUnknownVisitorAlerts(_ newValue: Bool) {
        isUpdatingUnknownVisitorAlerts = true
        Task { @MainActor in
            await settings.setUnknownVisitorAlertsEnabledFromUser(newValue)
            isUpdatingUnknownVisitorAlerts = false
        }
    }
}

#Preview {
    iPhone_SettingsView()
}
