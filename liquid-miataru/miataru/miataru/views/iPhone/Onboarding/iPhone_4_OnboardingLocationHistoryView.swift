import SwiftUI

struct iPhone_4_OnboardingLocationHistoryView: View {
    @ObservedObject var settings = SettingsManager.shared
    // @State private var useServerHistory = false // entfernt
    @State private var selectedRetentionTime = 30
    @State private var storeonServerTemp = 30
    let retentionOptions: [(label: String, value: Int)] = [
        ("30 minutes", 30),
        ("1 hour", 60),
        ("2 hours", 120),
        ("6 hours", 360),
        ("12 hours", 720)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Location History")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("locationhistory")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
            Text("You can choose how your location data is stored on the Miataru server.")
                .font(.headline)
                //.multilineTextAlignment(.center)
                //.padding(.horizontal)
            Text("If you enable server history, the server will keep a history of your last locations (depending on server and update frequency).\n\nIf you prefer not to keep a history, you can choose to only store your last location for a limited time.")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .padding(.horizontal)
            Picker("History Options", selection: $settings.saveLocationHistoryOnServer) {
                Text("store location history").tag(true)
                Text("only store last location").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .onAppear {
                // useServerHistory = settings.saveLocationHistoryOnServer // entfernt
            }

            if !settings.saveLocationHistoryOnServer {
                Text("Only the last location is stored for a fixed time on the server (default 30 minutes).")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal)
            } else {
                Text("A number of your last location updates ist stored on the server (default: last 1000).")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal)
            }
            Text("").padding(.bottom,16)
            Spacer()
        }.padding()
    }
}

#Preview {
    iPhone_4_OnboardingLocationHistoryView()
} 
