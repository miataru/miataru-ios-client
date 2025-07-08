import SwiftUI

struct OnboardingScreen2_WhatIsMiataru: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("What is Miataru?")
                .font(.largeTitle)
                .fontWeight(.bold)
            VStack(alignment: .leading, spacing: 12) {
                Text("• Miataru is a privacy-focused location sharing app.")
                Text("• You control who sees your location.")
                Text("• Share your device's location with friends, family, or groups.")
                Text("• Your data stays on the server you choose.")
            }
            .font(.body)
            .padding(.horizontal)
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
    OnboardingScreen2_WhatIsMiataru()
} 