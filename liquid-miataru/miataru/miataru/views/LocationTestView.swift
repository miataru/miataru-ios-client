import SwiftUI
import MiataruAPIClient
import CoreLocation

struct LocationTestView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var backgroundManager = BackgroundLocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status-Karte
                    StatusCard()
                    
                    // Location-Informationen
                    LocationInfoCard()
                    
                    // Server-Status
                    ServerStatusCard()
                    
                    // Test-Buttons
                    //TestButtonsCard()
                    
                    // Background-Status
                    BackgroundStatusCard()
                }
                .padding()
            }
            .navigationTitle("Location-Test")
            .alert("Info", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - Supporting Views
struct StatusCard: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Tracking-Status")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.subheadline)
                Spacer()
            }
            
            HStack {
                Text("Berechtigung:")
                Spacer()
                Text(permissionText)
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        if !settings.trackAndReportLocation {
            return .gray
        }
        return locationManager.isTracking ? .green : .orange
    }
    
    private var statusText: String {
        if !settings.trackAndReportLocation {
            return "Tracking deaktiviert"
        }
        return locationManager.isTracking ? "Tracking aktiv" : "Tracking inaktiv"
    }
    
    private var permissionText: String {
        switch locationManager.locationStatus {
        case .authorizedAlways:
            return "Vollständig"
        case .authorizedWhenInUse:
            return "Nur Vordergrund"
        case .denied:
            return "Verweigert"
        case .restricted:
            return "Eingeschränkt"
        case .notDetermined:
            return "Nicht bestimmt"
        case .unavailable:
            return "Nicht verfügbar"
        }
    }
}

struct LocationInfoCard: View {
    @ObservedObject private var locationManager = LocationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.green)
                Text("Aktuelle Position")
                    .font(.headline)
                Spacer()
            }
            
            if let location = locationManager.currentLocation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Latitude:")
                        Spacer()
                        Text(String(format: "%.6f", location.coordinate.latitude))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Longitude:")
                        Spacer()
                        Text(String(format: "%.6f", location.coordinate.longitude))
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Genauigkeit:")
                        Spacer()
                        Text(String(format: "%.1f m", location.horizontalAccuracy))
                    }
                    
                    if let timestamp = locationManager.lastUpdateTime {
                        HStack {
                            Text("Letztes Update:")
                            Spacer()
                            Text(formatTime(timestamp))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("Keine Position verfügbar")
                    .foregroundColor(.secondary)
                    .italic()
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

struct ServerStatusCard: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.blue)
                Text("Server-Status")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Text("Server-URL:")
                Spacer()
                Text(settings.miataruServerURL.isEmpty ? "Nicht gesetzt" : "Gesetzt")
                    .foregroundColor(settings.miataruServerURL.isEmpty ? .red : .green)
            }
            
            HStack {
                Text("Status:")
                Spacer()
                Text(serverStatusText)
                    .foregroundColor(serverStatusColor)
            }
            
            if let lastUpdate = locationManager.lastServerUpdate {
                HStack {
                    Text("Letzter Update:")
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
    
    private var serverStatusText: String {
        switch locationManager.serverUpdateStatus {
        case .idle:
            return "Bereit"
        case .updating:
            return "Wird gesendet..."
        case .success:
            return "Erfolgreich"
        case .failed(let error):
            return "Fehler: \(error)"
        }
    }
    
    private var serverStatusColor: Color {
        switch locationManager.serverUpdateStatus {
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct TestButtonsCard: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @Binding var showingAlert: Bool
    @Binding var alertMessage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(.orange)
                Text("Test-Funktionen")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button("Tracking starten") {
                    settings.trackAndReportLocation = true
                    showAlert("Tracking gestartet")
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.trackAndReportLocation)
                
                Button("Tracking stoppen") {
                    settings.trackAndReportLocation = false
                    showAlert("Tracking gestoppt")
                }
                .buttonStyle(.bordered)
                .disabled(!settings.trackAndReportLocation)
                
                Button("Berechtigung anfordern") {
                    locationManager.requestLocationPermission()
                    showAlert("Berechtigung angefordert")
                }
                .buttonStyle(.bordered)
                
                Button("Manueller Server-Update") {
                    Task {
                        await manualServerUpdate()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(locationManager.currentLocation == nil)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func showAlert(_ message: String) {
        alertMessage = message
        showingAlert = true
    }
    
    private func manualServerUpdate() async {
        guard let location = locationManager.currentLocation,
              !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            showAlert("Keine gültige Location oder Server-URL verfügbar")
            return
        }
        
        let locationData = UpdateLocationPayload(
            Device: thisDeviceIDManager.shared.deviceID,
            Timestamp: String(Int64(location.timestamp.timeIntervalSince1970)),
            Longitude: location.coordinate.longitude,
            Latitude: location.coordinate.latitude,
            HorizontalAccuracy: location.horizontalAccuracy
        )
        
        do {
            let success = try await MiataruAPIClient.updateLocation(
                serverURL: serverURL,
                locationData: locationData,
                enableHistory: settings.saveLocationHistoryOnServer,
                retentionTime: settings.locationDataRetentionTime
            )
            
            if success {
                showAlert("Manueller Server-Update erfolgreich")
            } else {
                showAlert("Server-Update fehlgeschlagen")
            }
        } catch {
            showAlert("Fehler beim Server-Update: \(error.localizedDescription)")
        }
    }
}

struct BackgroundStatusCard: View {
    @ObservedObject private var backgroundManager = BackgroundLocationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.purple)
                Text("Background-Status")
                    .font(.headline)
                Spacer()
            }
            
            HStack {
                Text("Background Tasks:")
                Spacer()
                Text(backgroundManager.backgroundTaskStatus)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Background Updates:")
                Spacer()
                Text("\(backgroundManager.backgroundUpdateCount)")
                    .foregroundColor(.secondary)
            }
            
            if let lastUpdate = backgroundManager.lastBackgroundUpdate {
                HStack {
                    Text("Letzter Background Update:")
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
    LocationTestView()
} 
