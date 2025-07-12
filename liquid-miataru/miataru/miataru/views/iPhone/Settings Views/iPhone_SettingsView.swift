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
                Section(header: Text(NSLocalizedString("activity_type_accuracy_settings_title", comment: "Section header for location activity type"))) {
                    Picker("", selection: $settings.locationActivityType) {
                        Text(NSLocalizedString("activity_type_other", comment: "Other (default, battery saving) option for location activity type")).tag(0)
                        Text(NSLocalizedString("activity_type_fitness", comment: "Fitness (walking, running, cycling) option for location activity type")).tag(2)
                        Text(NSLocalizedString("activity_type_automotive", comment: "Automotive Navigation (car) option for location activity type")).tag(1)
                    }
                    .pickerStyle(.menu)
                    Text(NSLocalizedString("activity_type_explanation", comment: "Explanation for location activity type picker"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("server_url")) {
                    TextField("server_url", text: $settings.miataruServerURL)
                }
                Section(header: Text("app_behaviour")) {
                    Toggle("deactivate_device_lock", isOn: $settings.disableDeviceAutolock)
                    Toggle("indicate_location_accuracy", isOn: $settings.indicateAccuracyOnMap)
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
                }
                Section(header: Text("map_configuration")) {
                    Picker("map_type", selection: $settings.mapType) {
                        Text("default_map").tag(1)
                        Text("hybrid_map").tag(2)
                        Text("sat_map").tag(3)
                    }
                    Picker("map_update_interval", selection: $settings.mapUpdateInterval) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    Picker("map_zoom_level", selection: $settings.mapZoomLevel) {
                        Text("1km").tag(1)
                        Text("2km").tag(2)
                        Text("5km").tag(5)
                        Text("10km").tag(10)
                        Text("25km").tag(25)
                        Text("50km").tag(50)
                        Text("100km").tag(100)
                    }
                    Toggle("zoom_to_fit_for_groups", isOn: $settings.groupsZoomToFit)
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
                                Button("done") {
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
