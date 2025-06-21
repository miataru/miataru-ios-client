import SwiftUI

struct iPhone_SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("track_and_history")) {
                    Toggle("location_track", isOn: Binding( //Standort erfassen & melden
                        get: { SettingsManager.shared.trackAndReportLocation },
                        set: { SettingsManager.shared.trackAndReportLocation = $0 }
                    ))
                    Toggle("send_location_to_server", isOn: Binding( // Standortverlauf auf Server speichern
                        get: { SettingsManager.shared.saveLocationHistoryOnServer },
                        set: { SettingsManager.shared.saveLocationHistoryOnServer = $0 }
                    ))

                    Picker("show_history_days", selection: Binding( // Verlauf speichern für
                        get: { SettingsManager.shared.historyNumberOfDays },
                        set: { SettingsManager.shared.historyNumberOfDays = $0 }
                    )) {
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
                    Picker("store_history_before_autoremove", selection: Binding( // Letzte Standortdaten speichern für
                        get: { SettingsManager.shared.locationDataRetentionTime },
                        set: { SettingsManager.shared.locationDataRetentionTime = $0 }
                    )) {
                        Text("30minutes").tag(30)
                        Text("1hour").tag(60)
                        Text("2hours").tag(120)
                        Text("6hours").tag(360)
                        Text("12hours").tag(720)
                    }
                }
                Section(header: Text("server_url")) {
                TextField("server_url", text: Binding(
                    get: { SettingsManager.shared.miataruServerURL ?? "" },
                    set: { SettingsManager.shared.miataruServerURL = $0 }
                ))
                }
                Section(header: Text("app_behaviour")) {
                    Toggle("deactivate_device_lock", isOn: Binding(
                        get: { SettingsManager.shared.disableDeviceAutolock },
                        set: { SettingsManager.shared.disableDeviceAutolock = $0 }
                    ))
                    Toggle("indicate_location_accuracy", isOn: Binding(
                        get: { SettingsManager.shared.indicateAccuracyOnMap },
                        set: { SettingsManager.shared.indicateAccuracyOnMap = $0 }
                    ))

                }
                Section(header: Text("map_configuration")) {
                    Picker("map_type", selection: Binding(
                        get: { SettingsManager.shared.mapType },
                        set: { SettingsManager.shared.mapType = $0 }
                    )) {
                        Text("default_map").tag(1)
                        Text("hybrid_mal").tag(2)
                        Text("sat_map").tag(3)
                    }
                    Picker("map_update_interval", selection: Binding(
                        get: { SettingsManager.shared.mapUpdateInterval },
                        set: { SettingsManager.shared.mapUpdateInterval = $0 }
                    )) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    Picker("map_zoom_level", selection: Binding(
                        get: { SettingsManager.shared.mapZoomLevel },
                        set: { SettingsManager.shared.mapZoomLevel = $0 }
                    )) {
                        Text("1km").tag(1)
                        Text("2km").tag(2)
                        Text("5km").tag(5)
                        Text("10km").tag(10)
                        Text("25km").tag(25)
                        Text("50km").tag(50)
                        Text("100km").tag(100)
                    }
                    Toggle("zoom_to_fit_for_groups", isOn: Binding(
                        get: { SettingsManager.shared.groupsZoomToFit },
                        set: { SettingsManager.shared.groupsZoomToFit = $0 }
                    ))
                }
            }
            .navigationTitle("settings")
        }
    }
}

#Preview {
    iPhone_SettingsView()
}
