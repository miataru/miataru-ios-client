import SwiftUI
import CoreLocation

struct iPhone_2_OnboardingLocationPermissionView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Location Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("mapandpin")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 1024)
            HStack(alignment: .top) {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Location Access")
                        .font(.headline)
                    Text("Miataru needs your location to provide core app functionality, such as sharing your position with trusted contacts.")
                        .font(.subheadline)
                    Text("To give Miataru the permission please enable the toggle and answer the following dialog with '")
                        .font(.subheadline)
                        + Text("Allow While Using App").bold()
                        + Text("'.")
                        .font(.subheadline)
                    Toggle(isOn: Binding(
                        get: { settings.trackAndReportLocation },
                        set: { newValue in
                            settings.trackAndReportLocation = newValue
                            if newValue {
                                locationManager.requestLocationPermission()                            }
                        }
                    )) {
                        Text("Enable Location Tracking")
                    }
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
