import SwiftUI


struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore()
    @State private var showingAddDevice = false

    var body: some View {
        NavigationView {
            List(store.devices, id: \.DeviceID) { device in
                iPhone_DeviceRowView(device: device)
            }
            .navigationTitle("devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddDevice = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                iPhone_AddDeviceView(store: store, isPresented: $showingAddDevice)
            }
        }
    }
}

#Preview {
    iPhone_DevicesView()
}
