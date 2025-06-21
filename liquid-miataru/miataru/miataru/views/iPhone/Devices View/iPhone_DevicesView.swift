import SwiftUI


struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore()
    @State private var showingAddDevice = false
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationView {
            List {
                ForEach(store.devices) { device in
                    iPhone_DeviceRowView(device: device)
                }
                .onMove { indices, newOffset in
                    store.devices.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indices in
                    store.remove(atOffsets: indices)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode == .active ? "Fertig" : "Bearbeiten") {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
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
