import SwiftUI
import CoreLocation

struct iPhone_2_OnboardingLocationPermissionView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Location Permission Required")
                .font(.title)
                .bold()
                .padding(.bottom, 8)
            HStack(alignment: .top) {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location Access")
                        .font(.headline)
                    Text("We need your location to provide core app functionality, such as sharing your position with trusted contacts.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("Status: ")
                        Text(locationStatusText)
                            .foregroundColor(locationStatusColor)
                    }
                    Button(action: {
                        locationManager.requestLocationPermission()
                    }) {
                        Text("Request Location Permission")
                    }
                    .disabled(locationManager.authorizationStatus == .authorizedAlways || locationManager.authorizationStatus == .authorizedWhenInUse)
                }
            }
            Spacer()
        }
        .padding()
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
