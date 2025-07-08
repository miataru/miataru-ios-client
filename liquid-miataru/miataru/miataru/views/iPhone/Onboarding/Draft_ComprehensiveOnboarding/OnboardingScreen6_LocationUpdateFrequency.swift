import SwiftUI

struct OnboardingScreen6_LocationUpdateFrequency: View {
    @State private var selectedFrequency = 1
    let options = ["Every 5 seconds", "Every 30 seconds", "Every 1 minute", "Every 5 minutes"]
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Location Update Frequency")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("How often should Miataru update your location while the app is open?\nMore frequent updates = more accuracy, but may use more battery.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Picker("Update Frequency", selection: $selectedFrequency) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i]).tag(i)
                }
            }
            .pickerStyle(.inline)
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
    OnboardingScreen6_LocationUpdateFrequency()
} 