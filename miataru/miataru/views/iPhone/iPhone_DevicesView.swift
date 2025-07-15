import SwiftUI
import MiataruAPIClient

struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @State private var showingAddDevice = false
    @State private var editMode: EditMode = .inactive
    @State private var editingDevice: KnownDevice? = nil
    @State private var selectedDeviceID: String? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.devices) { device in
                    if editMode == .inactive {
                        NavigationLink(value: device.DeviceID) {
                            iPhone_DeviceRowView(device: device, cache: cache)
                        }
                        .listRowBackground(selectedDeviceID == device.DeviceID ? Color(.systemGray) : Color(.systemBackground))
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
                        iPhone_DeviceRowView(device: device, cache: cache)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingDevice = device
                                selectedDeviceID = device.DeviceID
                            }
                            .listRowBackground(selectedDeviceID == device.DeviceID ? Color(.systemGray) : Color(.systemBackground))
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
            .navigationDestination(for: String.self) { deviceID in
                iPhone_DeviceMapView(deviceID: deviceID)
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
            .refreshable {
                await refreshAllDeviceLocations()
            }
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
            // Für Devices ohne Location den Cache-Eintrag entfernen
            let foundIDs = Set(locations.map { $0.Device })
            let missingIDs = Set(deviceIDs).subtracting(foundIDs)
            for missingID in missingIDs {
                DeviceLocationCacheStore.shared.removeLocation(for: missingID)
            }
        } catch {
            print("Error refreshing device locations: \(error)")
            // Optional: User-Overlay anzeigen
        }
    }
}

#Preview {
    let store = KnownDeviceStore.shared
    store.devices = [
        KnownDevice(name: "iPhone 13", deviceID: UUID().uuidString, color: .red),
        KnownDevice(name: "iPad Pro", deviceID: UUID().uuidString, color: .green),
        KnownDevice(name: "MacBook Air", deviceID: UUID().uuidString, color: .blue)
    ]
    return iPhone_DevicesView().environmentObject(store)
}
