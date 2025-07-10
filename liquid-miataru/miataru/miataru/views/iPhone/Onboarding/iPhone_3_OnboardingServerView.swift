import SwiftUI

struct iPhone_3_OnboardingServerView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var useDefaultServer: Bool = true
    @State private var customServerURL: String = ""
    @State private var showURLError: Bool = false
    
    private let defaultServer = "https://service.miataru.com"
    
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
            Picker("Server", selection: $useDefaultServer) {
                Text("Use Default Server").tag(true)
                Text("Enter Custom Server").tag(false)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            if !useDefaultServer {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Custom server URL (must start with https://)", text: $customServerURL)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding(.horizontal)
                    if showURLError {
                        Text("Please enter a valid https server URL.")
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }
                }
            }
            Spacer()
            Link("Self-host your own server (GitHub)", destination: URL(string: "https://github.com/miataru/miataru-server")!)
                .font(.footnote)
                .foregroundColor(.blue)
                .padding(.bottom, 8)
            Button(action: {
                if useDefaultServer {
                    settings.miataruServerURL = defaultServer
                    showURLError = false
                } else {
                    if isValidHTTPSURL(customServerURL) {
                        settings.miataruServerURL = customServerURL
                        showURLError = false
                    } else {
                        showURLError = true
                    }
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
        .onAppear {
            // Pre-fill customServerURL if not using default
            if settings.miataruServerURL != defaultServer && !settings.miataruServerURL.isEmpty {
                useDefaultServer = false
                customServerURL = settings.miataruServerURL
            } else {
                useDefaultServer = true
                customServerURL = ""
            }
        }
    }
    
    private func isValidHTTPSURL(_ url: String) -> Bool {
        guard let u = URL(string: url), u.scheme == "https", !url.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return true
    }
}

#Preview {
    iPhone_3_OnboardingServerView()
} 
