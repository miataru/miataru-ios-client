import SwiftUI

struct iPhone_6_OnboardingDoneView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("You are Ready to Go!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("done")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(.horizontal)
            Text("Miataru is set up and ready.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("You can change your settings or permissions anytime in the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Tap on "+"Finish"+" to start using Miataru.")
                .font(.body)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            
        }.padding()
    }
}

#Preview {
    iPhone_6_OnboardingDoneView()
}
