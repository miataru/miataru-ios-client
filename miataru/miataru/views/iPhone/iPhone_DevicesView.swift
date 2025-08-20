/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_DevicesView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MiataruAPIClient

struct iPhone_DevicesView: View {
    @StateObject private var store = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showingAddDevice = false
    @State private var prefillDeviceID: String? = nil
    @State private var editMode: EditMode = .inactive
    @State private var editingDevice: KnownDevice? = nil
    @State private var selectedDeviceID: String? = nil
    @State private var lastDeviceListRefresh: Date? = nil
    @State private var isVisible: Bool = false
    @State private var navigationPath: [String] = [] // Typed navigation path for device IDs

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                    for index in indices {
                        store.removeDevice(byID: store.devices[index].DeviceID)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        editMode = editMode == .active ? .inactive : .active
                    } label: {
                        if editMode == .active {
                            Text(NSLocalizedString("devicelist_edit_done", comment: "Finish editing the device list."))
                        } else {
                            Image(systemName: "pencil")
                                .accessibilityLabel(Text(NSLocalizedString("devicelist_editbutton", comment: "Edit device list")))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddDevice = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: String.self) { deviceID in
                iPhone_DeviceMapView(
                    deviceID: deviceID,
                    onNavigateToDevice: { newDeviceID in
                        // Push another device map view onto the stack
                        navigationPath.append(newDeviceID)
                    }
                )
            }
            .sheet(isPresented: $showingAddDevice) {
                iPhone_AddDeviceView(store: store, isPresented: $showingAddDevice, prefillDeviceID: prefillDeviceID)
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
                let success = await refreshAllDeviceLocations()
                if success { Haptic.notifySuccess() }
            }
            .onAppear {
                isVisible = true
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
        }
    }

    private func refreshAllDeviceLocations() async -> Bool {
        guard let url = URL(string: SettingsManager.shared.miataruServerURL), !store.devices.isEmpty else { return false }
        let deviceIDs = store.devices.map { $0.DeviceID }
        do {
            print("[iPhone_DevicesView] refreshAllDeviceLocations")
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
            print("Error refreshing device locations: \(error)")
            // Remove all device locations from cache if download fails
            for deviceID in deviceIDs {
                DeviceLocationCacheStore.shared.removeLocation(for: deviceID)
            }
            // Optional: User-Overlay anzeigen
            return false
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
