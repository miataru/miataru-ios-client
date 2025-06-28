import SwiftUI
import MapKit

struct iPhone_DeviceMapView: View {
    let device: KnownDevice
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco als Standard
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        Map(coordinateRegion: $region)
            .ignoresSafeArea()
            .navigationTitle(device.DeviceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Aktualisieren") {
                        // Hier könnte die Standortaktualisierung implementiert werden
                    }
                    .foregroundColor(Color(device.DeviceColor ?? UIColor.blue))
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

#Preview {
    let device = KnownDevice(name: "Mein iPhone", deviceID: "12345", color: .blue)
    iPhone_DeviceMapView(device: device)
} 