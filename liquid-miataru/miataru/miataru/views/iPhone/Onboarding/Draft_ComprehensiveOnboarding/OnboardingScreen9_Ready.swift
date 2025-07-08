import SwiftUI

struct OnboardingScreen9_Ready: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.accentColor)
            Text("You're Ready to Go!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Miataru is set up and ready.\nYou can change your settings or permissions anytime in the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Button(action: { /* Start using app */ }) {
                Text("Start Using Miataru")
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
    OnboardingScreen9_Ready()
} 