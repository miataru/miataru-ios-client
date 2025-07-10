import SwiftUI
import AVFoundation

struct iPhone_2b_OnboardingCameraPermissionView: View {
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Camera Permission Required")
                .font(.title)
                .bold()
                .padding(.bottom, 8)
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
            Spacer()
        }
        .padding()
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
    iPhone_2b_OnboardingCameraPermissionView()
} 