import SwiftUI

struct OnboardingScreen8_TryQRCode: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Try QR Code Sharing")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Tap below to see your device's QR code, or scan someone else's.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            HStack(spacing: 16) {
                Button(action: { /* Show QR code */ }) {
                    Text("Show My QR Code")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                Button(action: { /* Scan QR code */ }) {
                    Text("Scan a QR Code")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            Button(action: { /* Skip action */ }) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.top, 8)
            }
            Spacer()
        }
    }
}

#Preview {
    OnboardingScreen8_TryQRCode()
} 