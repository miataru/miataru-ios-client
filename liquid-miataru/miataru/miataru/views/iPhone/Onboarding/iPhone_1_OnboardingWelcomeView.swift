import SwiftUI

struct iPhone_1_OnboardingWelcomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Welcome to Miataru!")
                .font(.largeTitle)
                .fontWeight(.bold)
            MiataruIcon().offset(x:-15).frame(width:200)
            //Image(systemName: "location.circle.fill")
            //               .resizable()
            //               .frame(width: 100, height: 100)
            //               .foregroundColor(.accentColor)
            Text("Miataru helps you share your device's location with people and groups you trust.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Let's get you set up in just a few steps.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            
        }
    }
}

#Preview {
    iPhone_1_OnboardingWelcomeView()
} 
