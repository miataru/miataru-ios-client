import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Tracking & Verlauf")) {
                    Toggle("Standort erfassen & melden", isOn: Binding(
                        get: { SettingsManager.shared.trackAndReportLocation },
                        set: { SettingsManager.shared.trackAndReportLocation = $0 }
                    ))
                    Toggle("Standortverlauf auf Server speichern", isOn: Binding(
                        get: { SettingsManager.shared.saveLocationHistoryOnServer },
                        set: { SettingsManager.shared.saveLocationHistoryOnServer = $0 }
                    ))
                    Picker("Verlauf speichern für", selection: Binding(
                        get: { SettingsManager.shared.historyNumberOfDays },
                        set: { SettingsManager.shared.historyNumberOfDays = $0 }
                    )) {
                        Text("1 Tag").tag(1)
                        Text("2 Tage").tag(2)
                        Text("3 Tage").tag(3)
                        Text("4 Tage").tag(4)
                        Text("5 Tage").tag(5)
                        Text("6 Tage").tag(6)
                        Text("7 Tage").tag(7)
                        Text("14 Tage").tag(14)
                        Text("31 Tage").tag(31)
                        Text("Alle verfügbaren").tag(10000000)
                    }
                    Picker("Letzte Standortdaten speichern für", selection: Binding(
                        get: { SettingsManager.shared.locationDataRetentionTime },
                        set: { SettingsManager.shared.locationDataRetentionTime = $0 }
                    )) {
                        Text("30 Minuten").tag(30)
                        Text("1 Stunde").tag(60)
                        Text("2 Stunden").tag(120)
                        Text("6 Stunden").tag(360)
                        Text("12 Stunden").tag(720)
                    }
                }
                Section(header: Text("Allgemein")) {
                    Toggle("Gerätesperre deaktivieren", isOn: Binding(
                        get: { SettingsManager.shared.disableDeviceAutolock },
                        set: { SettingsManager.shared.disableDeviceAutolock = $0 }
                    ))
                    Toggle("Genauigkeit auf Karte anzeigen", isOn: Binding(
                        get: { SettingsManager.shared.indicateAccuracyOnMap },
                        set: { SettingsManager.shared.indicateAccuracyOnMap = $0 }
                    ))
                    TextField("Server URL", text: Binding(
                        get: { SettingsManager.shared.miataruServerURL ?? "" },
                        set: { SettingsManager.shared.miataruServerURL = $0 }
                    ))
                }
                Section(header: Text("Karte")) {
                    Picker("Kartentyp", selection: Binding(
                        get: { SettingsManager.shared.mapType },
                        set: { SettingsManager.shared.mapType = $0 }
                    )) {
                        Text("Standard").tag(1)
                        Text("Hybrid").tag(2)
                        Text("Satellit").tag(3)
                    }
                    Picker("Karten-Update-Intervall", selection: Binding(
                        get: { SettingsManager.shared.mapUpdateInterval },
                        set: { SettingsManager.shared.mapUpdateInterval = $0 }
                    )) {
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                    Picker("Karten-Zoom-Level", selection: Binding(
                        get: { SettingsManager.shared.mapZoomLevel },
                        set: { SettingsManager.shared.mapZoomLevel = $0 }
                    )) {
                        Text("1 km").tag(1)
                        Text("2 km").tag(2)
                        Text("5 km").tag(5)
                        Text("10 km").tag(10)
                        Text("25 km").tag(25)
                        Text("50 km").tag(50)
                        Text("100 km").tag(100)
                    }
                }
                Section(header: Text("Gruppen")) {
                    Toggle("Zoom-to-Fit für Gruppen aktivieren", isOn: Binding(
                        get: { SettingsManager.shared.groupsZoomToFit },
                        set: { SettingsManager.shared.groupsZoomToFit = $0 }
                    ))
                }
            }
            .navigationTitle("Einstellungen")
        }
    }
}

#Preview {
    SettingsView()
}
