import SwiftUI

struct iPhone_5_OnboardingQRcodeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Share & Scan with QR-Codes")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("qrcode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
            Text("Easily share your device ID or add others by scanning QR-Codes.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 8) {
                Text("To share:").bold().font(.headline)
                Text("Show your QR-Code to someone you trust.").font(.subheadline)
                Text("To add:").bold().font(.headline)
                    Text("Scan a QR-Code from another device running Miataru.")
                }.padding(.horizontal,10)
            Text("").padding(.bottom,16)
            Spacer()
        }.padding()
    }
}

#Preview {
    iPhone_5_OnboardingQRcodeView()
}
