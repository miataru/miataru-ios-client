import SwiftUI


struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore()

    var body: some View {
        NavigationView {
            List(store.devices, id: \.DeviceID) { device in
                iPhone_DeviceRowView(device: device)
            }
            .navigationTitle("devices")
        }
    }
}

#Preview {
    iPhone_DevicesView()
}
