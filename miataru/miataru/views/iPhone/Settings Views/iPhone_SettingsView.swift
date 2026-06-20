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
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var appNavigation = AppNavigationCoordinator.shared
    @State private var showingDeviceKeySheet = false
    @State private var showingTrackingPauseSheet = false
    @State private var showAdvancedOptionsFromNavigationRequest = false
    @State private var serverURLDraft = SettingsManager.shared.miataruServerURL
    @State private var pendingServerURLChange: String?
    @State private var pendingServerURLQueuedCount = 0
    @State private var showingServerURLQueueDialog = false
    @FocusState private var isServerURLFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("track_and_history", tableName: "LocationTracking")) {
                    Toggle(String(localized: "location_track", table: "LocationTracking"), isOn: $settings.trackAndReportLocation)
                    SettingsDescriptionText("explanation_location_track")

                    if trackingPermissionVisibility.showsTrackingDependentSettings {
                        Toggle(String(localized: "save_location_history_to_server", table: "LocationTracking"), isOn: $settings.saveLocationHistoryOnServer)
                        SettingsDescriptionText("explanation_save_location_history_to_server")

                        Toggle(String(localized: "unknown_visitor_alerts_toggle", table: "Devices"),
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
                                Text("unknown_visitor_alerts_permission_denied_message", tableName: "Devices")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Button(String(localized: "unknown_visitor_alerts_open_settings_button", table: "Devices")) {
                                    LocationManager.shared.openAppSettings()
                                }
                                .font(.caption)
                            }
                        }

                        if !settings.saveLocationHistoryOnServer {
                            Picker(String(localized: "store_history_before_autoremove", table: "LocationTracking"), selection: $settings.locationDataRetentionTime) {
                                Text("30minutes", tableName: "Common").tag(30)
                                Text("1hour", tableName: "Common").tag(60)
                                Text("2hours", tableName: "Common").tag(120)
                                Text("6hours", tableName: "Common").tag(360)
                                Text("12hours", tableName: "Common").tag(720)
                                Text("24hours", tableName: "Common").tag(1440)
                                Text("7days", tableName: "Common").tag(10_080)
                            }
                            SettingsDescriptionText("explanation_store_history_before_autoremove")
                        }
                    } else if trackingPermissionVisibility.showsAlwaysPermissionNotice {
                        AlwaysLocationPermissionRequiredNotice()
                    }

                    Button {
                        showingDeviceKeySheet = true
                    } label: {
                        HStack {
                            Image(systemName: "key.card")
                                .foregroundColor(.blue)
                            Text("manage_your_devicekey", tableName: "Devices")
                        }
                    }

                    if settings.trackAndReportLocation {
                        Button {
                            showingTrackingPauseSheet = true
                        } label: {
                            TrackingPauseSettingsRow()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings_tracking_pause_button")
                    }
                }

                if trackingPermissionVisibility.showsTrackingDependentSettings {
                    Section(header: Text("background_location_updates_section_title", tableName: "LocationTracking")) {
                        Toggle(String(localized: "smart_frequent_background_location_updates_title", table: "LocationTracking"), isOn: $settings.smartFrequentBackgroundLocationUpdatesEnabled)
                            .accessibilityIdentifier("settings_smart_frequent_background_location_updates_central_toggle")
                            .disabled(settings.frequentBackgroundLocationUpdatesEnabled)
                        SettingsDescriptionText("smart_frequent_background_location_updates_explanation")
                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            SettingsDescriptionText("smart_frequent_background_locked_by_manual_explanation")
                        }

                        if settings.smartFrequentBackgroundLocationUpdatesEnabled {
                            Toggle(String(localized: "frequent_background_location_updates_title", table: "LocationTracking"), isOn: $settings.frequentBackgroundLocationUpdatesEnabled)
                                .accessibilityIdentifier("settings_frequent_background_location_updates_central_toggle")
                            SettingsDescriptionText("frequent_background_location_updates_manual_explanation")
                            if settings.frequentBackgroundLocationUpdatesEnabled {
                                SettingsWarningText("frequent_background_location_updates_battery_warning")
                            }
                        }
                    }
                }

                if !settings.allowedDeviceListEnabled {
                    Section(header: Text("allowed_device_list_section_title", tableName: "Devices")) {
                        AllowedDeviceListSettingsContent()
                    }
                }

                Section(header: Text("app_behaviour", tableName: "SettingsDiagnostics")) {
                    Toggle(String(localized: "deactivate_device_lock", table: "Devices"), isOn: $settings.disableDeviceAutolock)
                    SettingsDescriptionText("explanation_deactivate_device_lock")

                    Toggle(String(localized: "prevent_screen_rotation", table: "LocationTracking"), isOn: $settings.preventScreenRotation)
                    SettingsDescriptionText("explanation_prevent_screen_rotation")
                }

                Section(header: Text("map_configuration", tableName: "MapNavigationHistory")) {
                    Picker(String(localized: "map_type", table: "MapNavigationHistory"), selection: $settings.mapType) {
                        Text("default_map", tableName: "MapNavigationHistory").tag(1)
                        Text("hybrid_map", tableName: "MapNavigationHistory").tag(2)
                        Text("sat_map", tableName: "MapNavigationHistory").tag(3)
                    }
                    SettingsDescriptionText("explanation_map_type")

                    Picker(String(localized: "map_zoom_level", table: "MapNavigationHistory"), selection: $settings.mapZoomLevel) {
                        Text("1km", tableName: "Common").tag(1)
                        Text("2km", tableName: "Common").tag(2)
                        Text("5km", tableName: "Common").tag(5)
                        Text("10km", tableName: "Common").tag(10)
                        Text("25km", tableName: "Common").tag(25)
                        Text("50km", tableName: "Common").tag(50)
                        Text("100km", tableName: "Common").tag(100)
                    }
                    SettingsDescriptionText("explanation_map_zoom_level")
                }

                Section(header: Text("navigation", tableName: "MapNavigationHistory")) {
                    Picker(String(localized: "transport_mode", table: "MapNavigationHistory"), selection: $settings.navigationTransportType) {
                        Text("transport_walk", tableName: "MapNavigationHistory").tag(0)
                        Text("transport_car", tableName: "MapNavigationHistory").tag(2)
                        Text("transport_transit", tableName: "MapNavigationHistory").tag(3)
                    }
                    SettingsDescriptionText("explanation_navigation_mode")
                }

                Section(header: Text("server_url", tableName: "SettingsDiagnostics")) {
                    TextField(String(localized: "server_url", table: "SettingsDiagnostics"), text: $serverURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .focused($isServerURLFieldFocused)
                        .onSubmit {
                            commitServerURLDraft()
                        }
                    SettingsDescriptionText("explanation_server_url")
                }

                Section(header: Text("advanced_options_and_tracking_status", tableName: "SettingsDiagnostics")) {
                    NavigationLink {
                        iPhone_AdvancedOptionsView()
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.blue)
                            Text("advanced_options", tableName: "SettingsDiagnostics")
                                .accessibilityIdentifier("settings_advanced_options_label")
                        }
                    }
                    .accessibilityIdentifier("settings_advanced_options_link")

                    NavigationLink(destination: iPhone_LocationStatusView()
                        .navigationTitle(String(localized: "Location Tracking Details", table: "LocationTracking"))
                        .navigationBarTitleDisplayMode(.inline)) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Location Tracking Details", tableName: "LocationTracking")
                        }
                    }
                    .accessibilityIdentifier("settings_location_tracking_details_link")
                }
            }
            .navigationDestination(isPresented: $showAdvancedOptionsFromNavigationRequest) {
                iPhone_AdvancedOptionsView()
            }
            .navigationTitle(String(localized: "settings", table: "SettingsDiagnostics"))
            .sheet(isPresented: $showingDeviceKeySheet) {
                iPhone_DeviceKeySheetView(showsMismatchWarning: false)
            }
            .sheet(isPresented: $showingTrackingPauseSheet) {
                TrackingPauseSheet()
            }
            .confirmationDialog(
                String(localized: "location_update_outbox_server_change_title", table: "LocationTracking"),
                isPresented: $showingServerURLQueueDialog,
                titleVisibility: .visible
            ) {
                Button(String(localized: "location_update_outbox_send_to_new_server_button", table: "LocationTracking")) {
                    confirmPendingServerURLChange(sendQueuedUpdates: true)
                }
                Button(String(localized: "location_update_outbox_discard_pending_button", table: "LocationTracking"), role: .destructive) {
                    confirmPendingServerURLChange(sendQueuedUpdates: false)
                }
                Button(String(localized: "cancel", table: "Common"), role: .cancel) {
                    cancelPendingServerURLChange()
                }
            } message: {
                Text(serverURLQueueDialogMessage)
            }
        }
        .accessibilityIdentifier("settings_navigation_view")
        .onAppear {
            handleSettingsNavigationRequest(appNavigation.settingsRequest)
        }
        .onChange(of: isServerURLFieldFocused) { _, isFocused in
            if !isFocused {
                commitServerURLDraft()
            }
        }
        .onChange(of: showingServerURLQueueDialog) { _, isShowing in
            if !isShowing && pendingServerURLChange != nil {
                cancelPendingServerURLChange()
            }
        }
        .onReceive(settings.$miataruServerURL.removeDuplicates()) { newValue in
            if !isServerURLFieldFocused && pendingServerURLChange == nil {
                serverURLDraft = newValue
            }
        }
        .onReceive(appNavigation.$settingsRequest.compactMap { $0 }) { request in
            handleSettingsNavigationRequest(request)
        }
    }

    @State private var isUpdatingUnknownVisitorAlerts = false

    private var trackingPermissionVisibility: TrackingPermissionSettingsVisibility {
        TrackingPermissionSettingsGate.visibility(
            trackAndReportLocation: settings.trackAndReportLocation,
            authorizationStatus: locationManager.authorizationStatus
        )
    }

    private func handleSettingsNavigationRequest(_ request: SettingsNavigationRequest?) {
        guard let request,
              request.destination == .advancedOptions else {
            return
        }

        showAdvancedOptionsFromNavigationRequest = true
        appNavigation.consumeSettingsRequest(request)
    }

    private func updateUnknownVisitorAlerts(_ newValue: Bool) {
        isUpdatingUnknownVisitorAlerts = true
        Task { @MainActor in
            await settings.setUnknownVisitorAlertsEnabledFromUser(newValue)
            isUpdatingUnknownVisitorAlerts = false
        }
    }

    private var serverURLQueueDialogMessage: String {
        String(
            format: NSLocalizedString("location_update_outbox_server_change_message", tableName: "LocationTracking", comment: "Message shown when changing the server URL while location updates are queued"
            ),
            pendingServerURLQueuedCount
        )
    }

    private func commitServerURLDraft() {
        let newServerURL = serverURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        serverURLDraft = newServerURL

        guard newServerURL != settings.miataruServerURL else { return }

        Task {
            let pendingCount = await LocationManager.shared.pendingLocationUpdateOutboxCount()
            await MainActor.run {
                guard newServerURL != settings.miataruServerURL else { return }

                if pendingCount > 0 {
                    pendingServerURLChange = newServerURL
                    pendingServerURLQueuedCount = pendingCount
                    showingServerURLQueueDialog = true
                } else {
                    settings.miataruServerURL = newServerURL
                }
            }
        }
    }

    private func confirmPendingServerURLChange(sendQueuedUpdates: Bool) {
        guard let newServerURL = pendingServerURLChange else { return }

        pendingServerURLChange = nil
        pendingServerURLQueuedCount = 0
        serverURLDraft = newServerURL
        settings.miataruServerURL = newServerURL

        Task {
            if sendQueuedUpdates,
               let serverURL = Self.validServerURL(from: newServerURL) {
                await LocationManager.shared.sendPendingLocationUpdates(to: serverURL)
            } else if !sendQueuedUpdates {
                await LocationManager.shared.discardPendingLocationUpdates()
            }
        }
    }

    private func cancelPendingServerURLChange() {
        pendingServerURLChange = nil
        pendingServerURLQueuedCount = 0
        serverURLDraft = settings.miataruServerURL
    }

    private static func validServerURL(from string: String) -> URL? {
        guard let url = URL(string: string),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        return url
    }
}

#Preview {
    iPhone_SettingsView()
}
