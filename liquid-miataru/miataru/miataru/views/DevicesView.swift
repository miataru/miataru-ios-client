import SwiftUI

struct DevicesView: View {
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
    DevicesView()
} 
