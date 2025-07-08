import SwiftUI

struct OnboardingScreen7_QRCodeExplanation: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Share & Scan with QR Codes")
                .font(.largeTitle)
                .fontWeight(.bold)
            VStack(alignment: .leading, spacing: 12) {
                Text("Easily share your device ID or add others by scanning QR codes.")
                Text("- To share: Show your QR code to someone you trust.")
                Text("- To add: Scan a QR code from another device.")
            }
            .font(.body)
            .padding(.horizontal)
            Image(systemName: "qrcode.viewfinder")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
            Spacer()
            Button(action: { /* Next action */ }) {
                Text("Next")
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
    OnboardingScreen7_QRCodeExplanation()
} 