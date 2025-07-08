import SwiftUI

struct OnboardingScreen1_Welcome: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Welcome to Miataru!")
                .font(.largeTitle)
                .fontWeight(.bold)
            MiataruIcon().offset(x:-15).frame(width:200)
            Text("Miataru helps you share your device's location with people and groups you trust.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Let's get you set up in just a few steps.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button(action: { /* Next action */ }) {
                Text("Get Started")
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
    OnboardingScreen1_Welcome()
} 
