import SwiftUI

struct iPhone_DevicesView: View {
 @State private var knownDevices: [KnownDevice] = []

    var body: some View {
        NavigationView {
            List(knownDevices, id: \.DeviceID) { device in
                Text(device.DeviceName)
            }
            .navigationTitle("devices")
            .onAppear {
                knownDevices = KnownDeviceStore.shared.load();
            }
        }
    }
}

#Preview {
    iPhone_DevicesView()
} 
