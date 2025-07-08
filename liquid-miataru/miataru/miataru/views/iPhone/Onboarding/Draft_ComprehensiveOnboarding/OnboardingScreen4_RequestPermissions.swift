import SwiftUI

struct OnboardingScreen4_RequestPermissions: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Enable Location Access")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Miataru needs your location to share it with your trusted contacts. You can choose how often updates happen.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button(action: { /* Request location permission */ }) {
                Text("Allow Location Access")
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
    OnboardingScreen4_RequestPermissions()
} 