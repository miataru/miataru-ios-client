import SwiftUI

struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore()
    @State private var showingAddDevice = false
    @State private var editMode: EditMode = .inactive
    @State private var editingDevice: KnownDevice? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(store.devices) { device in
                    iPhone_DeviceRowView(device: device)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editMode == .active {
                                editingDevice = device
                            }
                        }
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
                    Button(editMode == .active ? "devicelist_edit_done" : "devicelist_editbutton") {
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
            .sheet(item: $editingDevice) { device in
                if let index = store.devices.firstIndex(where: { $0.id == device.id }) {
                    iPhone_EditDeviceView(
                        device: $store.devices[index],
                        isPresented: Binding(
                            get: { editingDevice != nil },
                            set: { if !$0 { editingDevice = nil } }
                        )
                    )
                }
            }
        }
    }
}

#Preview {
    iPhone_DevicesView()
}
