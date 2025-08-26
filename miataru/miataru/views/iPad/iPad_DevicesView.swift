/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_DevicesView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MiataruAPIClient

struct iPad_DevicesView: View {
    @StateObject private var store = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selection: String? = nil // DeviceID
    @State private var showingAddDevice = false
    @State private var editingDevice: KnownDevice? = nil
    @State private var editMode: EditMode = .inactive
    @State private var lastDeviceListRefresh: Date? = nil
    @State private var isVisible: Bool = false
    @State private var mapViewKey: UUID = UUID() // Force map view refresh when device changes
    @State private var lastSelectedDeviceID: String? = nil // Track last non-nil selection to avoid unnecessary resets
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text(NSLocalizedString("devices", comment: "Devices list header on iPad"))) {
                    ForEach(store.devices) { device in
                        iPhone_DeviceRowView(device: device, cache: cache)
                            .tag(device.DeviceID)
                            .tint(.primary)
                            .contextMenu {
                                Button {
                                    editingDevice = device
                                } label: {
                                    Label("edit_device", systemImage: "pencil").labelStyle(.titleAndIcon)
                                }
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
                                    Label(NSLocalizedString("edit_device", comment: "Edit this device."), systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete { indices in
                        store.removeDevice(byID: store.devices[indices.first!].DeviceID)
                    }
                    .onMove { indices, newOffset in
                        store.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("devices", comment: "Devices list title on iPad"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        editMode = editMode == .active ? .inactive : .active
                    } label: {
                        if editMode == .active {
                            Text(NSLocalizedString("devicelist_edit_done", comment: "Finish editing the device list."))
                        } else {
                            Text(NSLocalizedString("devicelist_editbutton", comment: "Edit device list"))
                            //Image(systemName: "pencil")
                            //    .accessibilityLabel(Text(NSLocalizedString("devicelist_editbutton", comment: "Edit device list")))
                        }
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
                let success = await refreshAllDeviceLocations()
                if success { Haptic.notifySuccess() }
            }
            .onAppear {
                isVisible = true
                // Automatically select the first device if no selection is made yet
                if selection == nil && !store.devices.isEmpty {
                    if let lastID = settings.lastOpenedDeviceID,
                       store.devices.contains(where: { $0.DeviceID == lastID }) {
                        selection = lastID
                        lastSelectedDeviceID = lastID
                    } else {
                        let firstID = store.devices.first?.DeviceID
                        selection = firstID
                        lastSelectedDeviceID = firstID
                    }
                }
            }
            .onDisappear {
                isVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate)) { _ in
                guard settings.autoRefreshDeviceList, isVisible, UIApplication.shared.applicationState == .active else { return }
                let interval = Double(SettingsManager.shared.mapUpdateInterval)
                let now = Date()
                if let last = lastDeviceListRefresh, now.timeIntervalSince(last) < interval {
                    // Throttle: do not refresh yet
                    return
                }
                lastDeviceListRefresh = now
                Task {
                    _ = await refreshAllDeviceLocations()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                guard settings.autoRefreshDeviceList, isVisible, UIApplication.shared.applicationState == .active else { return }
                let interval = Double(SettingsManager.shared.mapUpdateInterval)
                let now = Date()
                if let last = lastDeviceListRefresh, now.timeIntervalSince(last) < interval {
                    // Throttle: do not refresh yet
                    return
                }
                lastDeviceListRefresh = now
                Task {
                    _ = await refreshAllDeviceLocations()
                }
            }
        } detail: {
            if let selectedID = (selection ?? lastSelectedDeviceID), let device = store.devices.first(where: { $0.DeviceID == selectedID }) {
                iPad_DeviceMapView(
                    deviceID: device.DeviceID,
                    onNavigateToDevice: { newDeviceID in
                        // Navigate to the new device in the split view
                        selection = newDeviceID
                    }
                )
                    .id(mapViewKey) // Force view refresh when device changes
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { editingDevice = device }) {
                                Label(NSLocalizedString("edit_device", comment: "Edit the selected device."), systemImage: "pencil")
                                    .labelStyle(.titleAndIcon)
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
        .onChange(of: scenePhase) { _, newPhase in
            if (newPhase == .inactive || newPhase == .background) && (selection ?? lastSelectedDeviceID) == nil {
                settings.lastOpenedDeviceID = nil
            }
        }
        .onChange(of: selection) { oldSelection, newSelection in
            // Only refresh map when the selected device actually changes to a different ID
            if let newSelection = newSelection, newSelection != lastSelectedDeviceID {
                lastSelectedDeviceID = newSelection
                mapViewKey = UUID()
            }
        }
        .onChange(of: editMode) { _, newMode in
            // Preserve and restore selection in edit mode to avoid detail reset
            if newMode == .active {
                if selection == nil, let last = lastSelectedDeviceID {
                    selection = last
                }
            }
        }
    }

    private func refreshAllDeviceLocations() async -> Bool {
        guard let url = URL(string: SettingsManager.shared.miataruServerURL), !store.devices.isEmpty else { return false }
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
            return true
        } catch {
            debugLog("Error refreshing device locations: \(error)")
            // Remove all device locations from cache if download fails
            for deviceID in deviceIDs {
                DeviceLocationCacheStore.shared.removeLocation(for: deviceID)
            }
            // Optionally: Show user overlay
            return false
        }
    }
}

#Preview {
    iPad_DevicesView()
} 
