import SwiftUI
import CoreLocation
import AVFoundation

struct iPhone_2_OnboardingPermissionsView: View {
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Permissions Required")
                .font(.title)
                .bold()
                .padding(.bottom, 8)
            
            Group {
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
            }
            
            Group {
                HStack(alignment: .top) {
                    Image(systemName: "camera.fill")
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera Access")
                            .font(.headline)
                        Text("Camera access is needed to scan QR codes for device pairing and quick setup.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack {
                            Text("Status: ")
                            Text(cameraStatusText)
                                .foregroundColor(cameraStatusColor)
                        }
                        Button(action: {
                            AVCaptureDevice.requestAccess(for: .video) { _ in
                                DispatchQueue.main.async {
                                    cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                                }
                            }
                        }) {
                            Text("Request Camera Permission")
                        }
                        .disabled(cameraStatus == .authorized)
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
    private var cameraStatusText: String {
        switch cameraStatus {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }
    private var cameraStatusColor: Color {
        switch cameraStatus {
        case .authorized: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .gray
        @unknown default: return .gray
        }
    }
}

#Preview {
    iPhone_2_OnboardingPermissionsView()
} 
