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
    @State private var isVisible: Bool = false
    @State private var navigationPath: [String] = [] // Typed navigation path for device IDs
    @State private var didAutoNavigateFromSavedDevice: Bool = false
    @State private var hasPerformedInitialAutoNavigate: Bool = false
    @State private var navigationTargetDevice: KnownDevice? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                ForEach(store.devices) { device in
                    if editMode == .inactive {
                        NavigationLink(value: device.DeviceID) {
                            DeviceRowView(device: device, cache: cache)
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
                            if device.DeviceID != thisDeviceIDManager.shared.deviceID, cache.getLocation(for: device.DeviceID) != nil {
                                Button {
                                    navigationTargetDevice = device
                                } label: {
                                    Label(NSLocalizedString("navigation", comment: "Navigate to this device"), systemImage: "location")
                                }
                                .tint(.green)
                            }
                            Button {
                                editingDevice = device
                            } label: {
                                Label("edit_device_swipe", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    } else {
                        DeviceRowView(device: device, cache: cache)
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
                                if device.DeviceID != thisDeviceIDManager.shared.deviceID, cache.getLocation(for: device.DeviceID) != nil {
                                    Button {
                                        navigationTargetDevice = device
                                    } label: {
                                        Label(NSLocalizedString("navigation", comment: "Navigate to this device"), systemImage: "location")
                                    }
                                    .tint(.green)
                                }
                                Button {
                                    editingDevice = device
                                } label: {
                                    Label("edit_device_swipe", systemImage: "pencil")
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
                                .accessibilityHint(Text(NSLocalizedString("devicelist_editbutton_hint", comment: "Enters edit mode for the device list")))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddDevice = true }) {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text(NSLocalizedString("devicelist_addbutton", comment: "Add a new device to your list")))
                            .accessibilityHint(Text(NSLocalizedString("devicelist_addbutton_hint", comment: "Opens the add device form")))
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
            .navigationDestination(item: $navigationTargetDevice) { device in
                iPhone_DeviceNavigationView(device: device)
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
                let success = await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)
                if success { Haptic.notifySuccess() }
            }
            .onAppear {
                isVisible = true
                if !hasPerformedInitialAutoNavigate,
                   navigationPath.isEmpty,
                   let lastID = settings.lastOpenedDeviceID,
                   store.devices.contains(where: { $0.DeviceID == lastID }) {
                    navigationPath.append(lastID)
                    didAutoNavigateFromSavedDevice = true
                }
                hasPerformedInitialAutoNavigate = true
            }
            .onDisappear {
                isVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate)) { _ in
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                }
            }
            
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                }

                // Re-assert deep link navigation after activation to beat any restored navigation stack state.
                if let requestedID = settings.lastOpenedDeviceID,
                   store.devices.contains(where: { $0.DeviceID == requestedID }),
                   navigationPath.last != requestedID {
                    Task { @MainActor in
                        navigationPath = []
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        guard settings.lastOpenedDeviceID == requestedID else { return }
                        navigationPath = [requestedID]
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if (newPhase == .inactive || newPhase == .background) && navigationPath.isEmpty {
                    settings.lastOpenedDeviceID = nil
                }
            }
            .onChange(of: settings.lastOpenedDeviceID) { _, newDeviceID in
                guard let deviceID = newDeviceID,
                      store.devices.contains(where: { $0.DeviceID == deviceID }) else { return }
                let requestedID = deviceID
                Task { @MainActor in
                    // If we’re already showing the requested device (normal in-app navigation),
                    // do nothing to avoid a visible pop/push animation.
                    if navigationPath.last == requestedID {
                        return
                    }

                    // Clear first, then set after a short delay to override any restored navigation state.
                    navigationPath = []
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    // Guard against a stale delayed task (e.g. multiple widget taps).
                    guard settings.lastOpenedDeviceID == requestedID else { return }
                    navigationPath = [requestedID]
                }
            }
            // Intentionally do not reset didAutoNavigateFromSavedDevice on
            // changes to lastOpenedDeviceID to avoid unintended re-pushes
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
