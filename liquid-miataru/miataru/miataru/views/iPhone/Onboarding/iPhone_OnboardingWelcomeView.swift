import SwiftUI

struct iPhone_OnboardingWelcomeView: View {
    var body: some View {
        VStack(spacing:20) {
            Text(NSLocalizedString("Welcome to Miataru.", comment: "OnboardingView"))
               .font(.title)
               .bold()
               .multilineTextAlignment(.center)
            
            MiataruIcon().frame(width: 200).shadow(radius: 8).offset(x:-15)
                        
            Spacer()
        }
    }
}

#Preview {
    iPhone_OnboardingWelcomeView()
} 
