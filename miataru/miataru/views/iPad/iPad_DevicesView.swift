import SwiftUI
import MiataruAPIClient

struct iPad_DevicesView: View {
    @StateObject private var store = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @State private var selection: String? = nil // DeviceID
    @State private var showingAddDevice = false
    @State private var editingDevice: KnownDevice? = nil
    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text("devices")) {
                    ForEach(store.devices) { device in
                        iPhone_DeviceRowView(device: device, cache: cache)
                            .tag(device.DeviceID)
                            .contextMenu {
                                Button {
                                    editingDevice = device
                                } label: {
                                    Label("edit_device", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    store.removeDevice(byID: device.DeviceID)
                                } label: {
                                    Label("delete_device", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { indices in
                        store.remove(atOffsets: indices)
                    }
                    .onMove { indices, newOffset in
                        store.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }
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
            .environment(\.editMode, $editMode)
            .refreshable {
                await refreshAllDeviceLocations()
            }
        } detail: {
            if let selectedID = selection, let device = store.devices.first(where: { $0.DeviceID == selectedID }) {
                iPhone_DeviceMapView(deviceID: device.DeviceID)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { editingDevice = device }) {
                                Image(systemName: "pencil")
                            }
                        }
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
            } else {
                Text("Select a device to view details")
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            iPhone_AddDeviceView(store: store, isPresented: $showingAddDevice)
        }
    }

    private func refreshAllDeviceLocations() async {
        guard let url = URL(string: SettingsManager.shared.miataruServerURL), !store.devices.isEmpty else { return }
        let deviceIDs = store.devices.map { $0.DeviceID }
        do {
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: deviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            for location in locations {
                DeviceLocationCacheStore.shared.setLocation(
                    for: location.Device,
                    latitude: location.Latitude,
                    longitude: location.Longitude,
                    accuracy: location.HorizontalAccuracy,
                    timestamp: location.TimestampDate
                )
            }
            // Remove cache entry for devices without location
            let foundIDs = Set(locations.map { $0.Device })
            let missingIDs = Set(deviceIDs).subtracting(foundIDs)
            for missingID in missingIDs {
                DeviceLocationCacheStore.shared.removeLocation(for: missingID)
            }
        } catch {
            print("Error refreshing device locations: \(error)")
            // Remove all device locations from cache if download fails
            for deviceID in deviceIDs {
                DeviceLocationCacheStore.shared.removeLocation(for: deviceID)
            }
            // Optionally: Show user overlay
        }
    }
}

#Preview {
    iPad_DevicesView()
} 