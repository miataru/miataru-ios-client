import SwiftUI

struct iPhone_OnboardingWelcomeView: View {
    var body: some View {
        VStack {
            MiataruIcon()
            Text("Welcome to Miataru!")
            Text("This app helps you ...")
        }
    }
}

#Preview {
    iPhone_OnboardingWelcomeView()
} 
