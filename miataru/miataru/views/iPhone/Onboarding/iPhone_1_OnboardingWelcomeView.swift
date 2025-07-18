import SwiftUI

struct iPhone_1_OnboardingWelcomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Welcome to Miataru!")
                .font(.largeTitle)
                .fontWeight(.bold)
            //MiataruIcon().offset(x:-15).frame(width:200)
            Image("yourlocationyourcontrol")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
            //Image(systemName: "location.circle.fill")
            //               .resizable()
            //               .frame(width: 100, height: 100)
            //               .foregroundColor(.accentColor)
            Text("Miataru helps you share your (device) location with people and groups you trust.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("•")
                    Text("Your data stays on the server you choose for the time you choose")
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top) {
                    Text("•")
                    Text("Your data is only sent when you specifically activate it")
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top) {
                    Text("•")
                    Text("Miataru uses battery optimized background location tracking")
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal,10)
            
            Text("Swipe left to get you set up in just a few steps.")
                .font(.body)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("").padding(.bottom,16)
            Spacer()
            
        }.padding()
    }
}

#Preview {
    iPhone_1_OnboardingWelcomeView()
} 
