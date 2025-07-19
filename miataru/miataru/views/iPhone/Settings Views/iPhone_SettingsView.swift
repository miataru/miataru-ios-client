import SwiftUI

struct iPhone_SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var showingLocationStatus = false
    @State private var showingLocationTest = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("track_and_history")) {
                    Toggle("location_track", isOn: $settings.trackAndReportLocation)
                    if settings.trackAndReportLocation {
                        Toggle("save_location_history_to_server", isOn: $settings.saveLocationHistoryOnServer)

                        if !settings.saveLocationHistoryOnServer {
                            Picker("store_history_before_autoremove", selection: $settings.locationDataRetentionTime) {
                                Text("30minutes").tag(30)
                                Text("1hour").tag(60)
                                Text("2hours").tag(120)
                                Text("6hours").tag(360)
                                Text("12hours").tag(720)
                                Text("24hours").tag(1440)
                                Text("7days").tag(10080)
                            }
                        }
                    }
                }
                if settings.trackAndReportLocation {
                    Section(header: Text(NSLocalizedString("activity_type_accuracy_settings_title", comment: "Section header for location activity type"))) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("activity_type_tracking_accuracy_title", comment: "Title for tracking accuracy picker"))
                                .font(.headline)
                            Picker("", selection: $settings.locationActivityType) {
                                Text(NSLocalizedString("activity_type_other", comment: "Other (default, battery saving) option for location activity type")).tag(0)
                                Text(NSLocalizedString("activity_type_fitness", comment: "Fitness (walking, running, cycling) option for location activity type")).tag(2)
                                Text(NSLocalizedString("activity_type_automotive", comment: "Automotive Navigation (car) option for location activity type")).tag(1)
                            }
                            .pickerStyle(.menu)
                        }
                        Text(NSLocalizedString("activity_type_accuracy_explanation", comment: "Explanation for location tracking accuracy picker"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("location_sensitivity_title", comment: "Title for location sensitivity picker"))
                                .font(.headline)
                            Picker("", selection: $settings.locationSensitivityLevel) {
                                Text(NSLocalizedString("location_tracking_update_sensitivity_very_sensitive_short", comment: "Very sensitive (3m/2m) option for location sensitivity")).tag(1)
                                Text(NSLocalizedString("location_tracking_update_sensitivity_default_short", comment: "Default (5m/5m) option for location sensitivity")).tag(2)
                                Text(NSLocalizedString("location_tracking_update_sensitivity_balanced_short", comment: "Balanced (10m/10m) option for location sensitivity")).tag(3)
                                Text(NSLocalizedString("location_tracking_update_sensitivity_battery_saver_short", comment: "Battery saver (25m/20m) option for location sensitivity")).tag(4)
                                Text(NSLocalizedString("location_tracking_update_sensitivity_minimal_short", comment: "Minimal (50m/40m) option for location sensitivity")).tag(5)
                            }
                            .pickerStyle(.menu)
                        }
                        Text(NSLocalizedString("location_sensitivity_explanation", comment: "Explanation for location sensitivity picker"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Section(header: Text("server_url")) {
                    TextField("server_url", text: $settings.miataruServerURL)
                }
                Section(header: Text("app_behaviour")) {
                    Toggle("deactivate_device_lock", isOn: $settings.disableDeviceAutolock)
                    Text(NSLocalizedString("explanation_deactivate_device_lock", comment: "Explanation for deactivate device lock toggle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("indicate_location_accuracy", isOn: $settings.indicateAccuracyOnMap)
                    Text(NSLocalizedString("explanation_indicate_location_accuracy", comment: "Explanation for indicate location accuracy toggle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("auto_refresh_device_list", isOn: $settings.autoRefreshDeviceList)
                    Text(NSLocalizedString("explanation_auto_refresh_device_list", comment: "Explanation for auto refresh device list toggle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("show_history_days", selection: $settings.historyNumberOfDays) {
                        Text("1day").tag(1)
                        Text("2days").tag(2)
                        Text("3days").tag(3)
                        Text("4days").tag(4)
                        Text("5days").tag(5)
                        Text("6days").tag(6)
                        Text("7days").tag(7)
                        Text("14days").tag(14)
                        Text("31days").tag(31)
                        Text("all_available").tag(10000000)
                    }
                    Text(NSLocalizedString("explanation_show_history_days", comment: "Explanation for show history days picker"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("map_configuration")) {
                    Picker("map_type", selection: $settings.mapType) {
                        Text("default_map").tag(1)
                        Text("hybrid_map").tag(2)
                        Text("sat_map").tag(3)
                    }
                    Text(NSLocalizedString("explanation_map_type", comment: "Explanation for map type picker"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("map_update_interval", selection: $settings.mapUpdateInterval) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    Text(NSLocalizedString("explanation_map_update_interval", comment: "Explanation for map update interval picker"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("map_zoom_level", selection: $settings.mapZoomLevel) {
                        Text("1km").tag(1)
                        Text("2km").tag(2)
                        Text("5km").tag(5)
                        Text("10km").tag(10)
                        Text("25km").tag(25)
                        Text("50km").tag(50)
                        Text("100km").tag(100)
                    }
                    Text(NSLocalizedString("explanation_map_zoom_level", comment: "Explanation for map zoom level picker"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Toggle("zoom_to_fit_for_groups", isOn: $settings.groupsZoomToFit)
                    Text(NSLocalizedString("explanation_zoom_to_fit_for_groups", comment: "Explanation for zoom to fit for groups toggle"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                // Location Tracking Status Section
                Section(header: Text("Location Tracking Status")) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                        Text("Location Tracking Details")
                        Spacer()
                        Button("show") {
                            showingLocationStatus = true
                        }
                        .foregroundColor(.blue)
                    }
                }
                Section {
                    Button("Show Onboarding Wizard Again") {
                        UserDefaults.standard.hasCompletedOnboarding = false
                        appState.showOnboarding = true
                    }
                }
            }
            .navigationTitle("settings")
            .sheet(isPresented: $showingLocationStatus) {
                NavigationView {
                    iPhone_LocationStatusView()
                        .navigationTitle("Location Tracking Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingLocationStatus = false
                                }
                            }
                        }
                }
            }
        }
    }
}

#Preview {
    iPhone_SettingsView()
}
