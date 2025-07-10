import SwiftUI

struct iPhone_4_OnboardingLocationHistoryView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var useServerHistory = true
    @State private var selectedRetentionTime = 30
    let retentionOptions: [(label: String, value: Int)] = [
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("6 hours", 360),
        ("12 hours", 720)
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Location History Options")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("You can choose how your location data is stored on the Miataru server.\n\nIf you enable server history, the server will keep a history of your last locations (default: 1000, depending on server and update frequency).\n\nIf you prefer not to keep a history, you can choose to only store your last location for a limited time. After this time, your location is automatically deleted from the server.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Picker("Storage Option", selection: $useServerHistory) {
                Text("Use server location history").tag(true)
                Text("Only store last location for a limited time").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            if !useServerHistory {
                VStack(spacing: 8) {
                    Text("Choose how long your last location should be kept on the server:")
                        .font(.subheadline)
                    Picker("Retention Time", selection: $selectedRetentionTime) {
                        ForEach(retentionOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.inline)
                    .padding(.horizontal)
                }
            }
            Spacer()
            Button(action: {
                settings.saveLocationHistoryOnServer = useServerHistory
                if !useServerHistory {
                    settings.locationDataRetentionTime = selectedRetentionTime
                }
            }) {
                Text("Continue")
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
    iPhone_4_OnboardingLocationHistoryView()
} 