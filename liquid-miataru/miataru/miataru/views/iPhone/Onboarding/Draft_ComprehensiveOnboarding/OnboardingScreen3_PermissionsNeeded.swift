import SwiftUI

struct OnboardingScreen3_PermissionsNeeded: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Permissions Needed")
                .font(.largeTitle)
                .fontWeight(.bold)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Location: To update and share your position.")
                }
                HStack {
                    Image(systemName: "bell.fill")
                    Text("Notifications: To alert you about important updates.")
                }
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Camera: To scan QR codes for easy sharing.")
                }
            }
            .font(.body)
            .padding(.horizontal)
            Spacer()
            Button(action: { /* Next action */ }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    OnboardingScreen3_PermissionsNeeded()
} 