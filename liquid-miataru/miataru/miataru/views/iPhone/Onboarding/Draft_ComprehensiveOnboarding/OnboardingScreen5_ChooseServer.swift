import SwiftUI

struct OnboardingScreen5_ChooseServer: View {
    @State private var useDefault = true
    @State private var customServer = ""
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Choose Your Server")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Your location data is stored on a server you trust.\n- Use the default Miataru server, or\n- Enter your own server address.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Picker("Server", selection: $useDefault) {
                Text("Use Default Server").tag(true)
                Text("Enter Custom Server").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            if !useDefault {
                TextField("Custom server URL", text: $customServer)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
            }
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
    OnboardingScreen5_ChooseServer()
} 