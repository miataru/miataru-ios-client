import SwiftUI

struct MiataruDemoView: View {
    
    // State to hold the result of the API call
    @State private var locationInfo: String = "Tap the button to fetch location..."
    @State private var isLoading: Bool = false
    
    // Server details
    private let serverURL = URL(string: "https://service.miataru.com")!
    private let deviceID = "demo"

    var body: some View {
        VStack(spacing: 20) {
            Text("Miataru API Demo")
                .font(.largeTitle)

            // Display the result in a rounded text box
            Text(locationInfo)
                .padding()
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .multilineTextAlignment(.center)
            
            // The button to trigger the fetch operation
            Button(action: {
                fetchLocation()
            }) {
                // Show a progress view while loading
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Label("Fetch Location for 'demo'", systemImage: "location.magnifyingglass")
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(isLoading) // Disable button while loading
            
            Spacer()
        }
        .padding()
    }
    
    /// Kicks off the asynchronous task to fetch location data.
    private func fetchLocation() {
        // Set loading state
        isLoading = true
        locationInfo = "Fetching..."
        
        // Start a new async task
        Task {
            do {
                // Perform the API call
                let locations = try await MiataruAPIClient.getLocation(
                    serverURL: serverURL,
                    forDeviceIDs: [deviceID],
                    requestingDeviceID: nil
                )
                
                // Update the UI on the main thread
                if let firstLocation = locations.first {
                    locationInfo = """
                    Device: \(firstLocation.Device)
                    Timestamp: \(firstLocation.Timestamp)
                    Latitude: \(firstLocation.Latitude)
                    Longitude: \(firstLocation.Longitude)
                    """
                } else {
                    locationInfo = "Device '\(deviceID)' not found or has no location data."
                }
                
            } catch {
                // Handle any errors from the API call
                locationInfo = "An error occurred:\n\(error.localizedDescription)"
            }
            
            // Reset loading state
            isLoading = false
        }
    }
}

struct MiataruDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MiataruDemoView()
    }
} 