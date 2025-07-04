import SwiftUI
import CoreLocation

struct iPhone_LocationStatusView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var backgroundManager = BackgroundLocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Status-Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("Location-Tracking Status")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Tracking Toggle
                Toggle("location_track", isOn: $settings.trackAndReportLocation)
                    .labelsHidden()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Detaillierte Informationen
            if settings.trackAndReportLocation {
                VStack(spacing: 12) {
                    // Aktuelle Location
                    if let location = locationManager.currentLocation {
                        LocationInfoRow(
                            title: "Aktuelle Position",
                            value: String(format: "%.6f, %.6f", 
                                        location.coordinate.latitude, 
                                        location.coordinate.longitude),
                            icon: "location.fill"
                        )
                        
                        LocationInfoRow(
                            title: "Genauigkeit",
                            value: String(format: "%.1f m", location.horizontalAccuracy),
                            icon: "target"
                        )
                    }
                    
                    // Letzte Updates
                    if let lastUpdate = locationManager.lastUpdateTime {
                        LocationInfoRow(
                            title: "Letztes GPS-Update",
                            value: formatDate(lastUpdate),
                            icon: "clock"
                        )
                    }
                    
                    if let lastServerUpdate = locationManager.lastServerUpdate {
                        LocationInfoRow(
                            title: "Letzter Server-Update",
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
            PermissionStatusView(status: locationManager.locationStatus)
            
            // Background Status
            BackgroundStatusCard()
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    private var statusIcon: String {
        if !settings.trackAndReportLocation {
            return "location.slash"
        }
        
        switch locationManager.locationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? "location.fill" : "location"
        case .authorizedWhenInUse:
            return "location"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location.slash"
        case .unavailable:
            return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        if !settings.trackAndReportLocation {
            return .gray
        }
        
        switch locationManager.locationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? .green : .orange
        case .authorizedWhenInUse:
            return .orange
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .gray
        case .unavailable:
            return .red
        }
    }
    
    private var statusText: String {
        if !settings.trackAndReportLocation {
            return "Location-Tracking deaktiviert"
        }
        
        switch locationManager.locationStatus {
        case .authorizedAlways:
            return locationManager.isTracking ? "Tracking aktiv (Vorder- & Hintergrund)" : "Berechtigung erteilt, aber nicht aktiv"
        case .authorizedWhenInUse:
            return "Nur im Vordergrund erlaubt"
        case .denied:
            return "Location-Zugriff verweigert"
        case .restricted:
            return "Location-Zugriff eingeschränkt"
        case .notDetermined:
            return "Berechtigung nicht angefordert"
        case .unavailable:
            return "Location-Dienste nicht verfügbar"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

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
            
            Text("Server-Status")
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
            return "Bereit"
        case .updating:
            return "Wird gesendet..."
        case .success:
            return "Erfolgreich"
        case .failed(let error):
            return "Fehler: \(error)"
        }
    }
}

struct PermissionStatusView: View {
    let status: LocationManager.LocationStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Berechtigungs-Status")
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
                Text("Öffne die Einstellungen, um Location-Zugriff zu erlauben")
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
        case .unavailable:
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
        case .unavailable:
            return .red
        }
    }
    
    private var permissionText: String {
        switch status {
        case .authorizedAlways:
            return "Vollständiger Zugriff erteilt"
        case .authorizedWhenInUse:
            return "Nur Vordergrund-Zugriff erteilt"
        case .denied:
            return "Zugriff verweigert"
        case .restricted:
            return "Zugriff eingeschränkt"
        case .notDetermined:
            return "Berechtigung nicht angefordert"
        case .unavailable:
            return "Location-Dienste nicht verfügbar"
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
    iPhone_LocationStatusView()
} 
