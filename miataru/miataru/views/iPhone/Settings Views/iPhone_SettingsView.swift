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
    @ObservedObject private var appNavigation = AppNavigationCoordinator.shared
    @State private var showingDeviceKeySheet = false
    @State private var showAdvancedOptionsFromNavigationRequest = false
    @State private var serverURLDraft = SettingsManager.shared.miataruServerURL
    @State private var pendingServerURLChange: String?
    @State private var pendingServerURLQueuedCount = 0
    @State private var showingServerURLQueueDialog = false
    @FocusState private var isServerURLFieldFocused: Bool

    var body: some View {
        NavigationStack {
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

                if settings.trackAndReportLocation {
                    Section(header: Text("background_location_updates_section_title")) {
                        Toggle("frequent_background_location_updates_title", isOn: $settings.frequentBackgroundLocationUpdatesEnabled)
                            .accessibilityIdentifier("settings_frequent_background_location_updates_central_toggle")
                        SettingsDescriptionText("frequent_background_location_updates_explanation")
                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            SettingsWarningText("frequent_background_location_updates_battery_warning")
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
                    TextField("server_url", text: $serverURLDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                        .focused($isServerURLFieldFocused)
                        .onSubmit {
                            commitServerURLDraft()
                        }
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
            .navigationDestination(isPresented: $showAdvancedOptionsFromNavigationRequest) {
                iPhone_AdvancedOptionsView()
            }
            .navigationTitle("settings")
            .sheet(isPresented: $showingDeviceKeySheet) {
                iPhone_DeviceKeySheetView(showsMismatchWarning: false)
            }
            .confirmationDialog(
                "location_update_outbox_server_change_title",
                isPresented: $showingServerURLQueueDialog,
                titleVisibility: .visible
            ) {
                Button("location_update_outbox_send_to_new_server_button") {
                    confirmPendingServerURLChange(sendQueuedUpdates: true)
                }
                Button("location_update_outbox_discard_pending_button", role: .destructive) {
                    confirmPendingServerURLChange(sendQueuedUpdates: false)
                }
                Button("cancel", role: .cancel) {
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
            format: NSLocalizedString(
                "location_update_outbox_server_change_message",
                comment: "Message shown when changing the server URL while location updates are queued"
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
