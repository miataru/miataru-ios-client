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
                    if editMode == .inactive {
                        NavigationLink(destination: iPhone_DeviceMapView(device: device)) {
                            iPhone_DeviceRowView(device: device)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.removeDevice(byID: device.DeviceID)
                            } label: {
                                Label("delete_device", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingDevice = device
                            } label: {
                                Label("edit_device", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    } else {
                        iPhone_DeviceRowView(device: device)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingDevice = device
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    store.removeDevice(byID: device.DeviceID)
                                } label: {
                                    Label("delete_device", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingDevice = device
                                } label: {
                                    Label("edit_device", systemImage: "pencil")
                                }
                                .tint(.blue)
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
    let store = KnownDeviceStore()
    store.devices = [
        KnownDevice(name: "iPhone 13", deviceID: UUID().uuidString, color: .red),
        KnownDevice(name: "iPad Pro", deviceID: UUID().uuidString, color: .green),
        KnownDevice(name: "MacBook Air", deviceID: UUID().uuidString, color: .blue)
    ]
    return iPhone_DevicesView().environmentObject(store)
}
