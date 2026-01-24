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
    @State private var isVisible: Bool = false
    @State private var mapViewKey: UUID = UUID() // Force map view refresh when device changes
    @State private var lastSelectedDeviceID: String? = nil // Track last non-nil selection to avoid unnecessary resets
    @State private var navigationTargetDevice: KnownDevice? = nil
    @State private var isUpdatingFromDeepLink = false // Track if we're updating selection from deep link (to prevent circular updates)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text(NSLocalizedString("devices", comment: "Devices list header on iPad"))) {
                    ForEach(store.devices) { device in
                        if cache.getLocation(for: device.DeviceID) != nil {
                            DeviceRowView(device: device, cache: cache)
                                .tag(device.DeviceID)
                                .tint(.primary)
                                .draggable(device.DeviceID)
                                .contextMenu {
                                    Button {
                                        openWindow(value: device.DeviceID)
                                    } label: {
                                        Label(NSLocalizedString("open_in_new_window", comment: "Open device in a new window."), systemImage: "macwindow.badge.plus")
                                            .labelStyle(.titleAndIcon)
                                    }
                                    if device.DeviceID != thisDeviceIDManager.shared.deviceID, cache.getLocation(for: device.DeviceID) != nil {
                                        Button {
                                            navigationTargetDevice = device
                                        } label: {
                                            Label(NSLocalizedString("navigation", comment: "Navigate to this device"), systemImage: "location")
                                                .labelStyle(.titleAndIcon)
                                        }
                                    }
                                    Button {
                                        editingDevice = device
                                    } label: {
                                        Label(NSLocalizedString("edit_device", comment: "Edit this device."), systemImage: "pencil")
                                            .labelStyle(.titleAndIcon)
                                    }
                                    Button(role: .destructive) {
                                        store.removeDevice(byID: device.DeviceID)
                                    } label: {
                                        Label(NSLocalizedString("delete_device", comment: "Delete this device."), systemImage: "trash")
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
                                .tag(device.DeviceID)
                                .tint(.primary)
                                .contextMenu {
                                    Button {
                                        editingDevice = device
                                    } label: {
                                        Label(NSLocalizedString("edit_device", comment: "Edit this device."), systemImage: "pencil")
                                            .labelStyle(.titleAndIcon)
                                    }
                                    Button(role: .destructive) {
                                        store.removeDevice(byID: device.DeviceID)
                                    } label: {
                                        Label(NSLocalizedString("delete_device", comment: "Delete this device."), systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingDevice = device
                                    } label: {
                                        Label("edit_device_swipe", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
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
                            .accessibilityLabel(Text(NSLocalizedString("devicelist_addbutton", comment: "Add a new device to your list")))
                            .accessibilityHint(Text(NSLocalizedString("devicelist_addbutton_hint", comment: "Opens the add device form")))
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .refreshable {
                let success = await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)
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
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                }
            }
            
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                }

                // Re-assert deep link selection after activation to beat any restored split-view state.
                if let requestedID = settings.lastOpenedDeviceID,
                   store.devices.contains(where: { $0.DeviceID == requestedID }),
                   selection != requestedID {
                    Task { @MainActor in
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        guard settings.lastOpenedDeviceID == requestedID else { return }
                        selection = requestedID
                        lastSelectedDeviceID = requestedID
                    }
                }
            }
        } detail: {
            NavigationStack {
                if let selectedID = (selection ?? lastSelectedDeviceID), let device = store.devices.first(where: { $0.DeviceID == selectedID }) {
                    iPad_DeviceMapView(
                        deviceID: device.DeviceID,
                        onNavigateToDevice: { newDeviceID in
                            // Navigate to the new device in the split view
                            selection = newDeviceID
                        },
                        // Only update lastOpenedDeviceID for deep links, not for local selections
                        // This prevents cross-window synchronization when user selects a device locally
                        shouldUpdateLastOpenedDeviceID: isUpdatingFromDeepLink
                    )
                        .id(device.DeviceID) // Force view refresh when device changes
                        .navigationDestination(item: $navigationTargetDevice) { device in
                            iPhone_DeviceNavigationView(device: device)
                        }
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
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $showingAddDevice) {
            iPhone_AddDeviceView(store: store, isPresented: $showingAddDevice)
        }
        .dropDestination(for: String.self) { items, _ in
            if let deviceID = items.first, cache.getLocation(for: deviceID) != nil {
                openWindow(value: deviceID)
                return true
            }
            return false
        }
        .onChange(of: scenePhase) { _, newPhase in
            if (newPhase == .inactive || newPhase == .background) && (selection ?? lastSelectedDeviceID) == nil {
                settings.lastOpenedDeviceID = nil
            }
        }
        .onChange(of: settings.lastOpenedDeviceID) { _, newDeviceID in
            guard let deviceID = newDeviceID,
                  store.devices.contains(where: { $0.DeviceID == deviceID }) else { return }
            let requestedID = deviceID
            Task { @MainActor in
                // If we’re already showing the requested device, do nothing to avoid flicker.
                if selection == requestedID {
                    return
                }
                await Task.yield()
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard settings.lastOpenedDeviceID == requestedID else {
                    isUpdatingFromDeepLink = false
                    return
                }
                // Mark that we're updating from deep link to prevent onChange(of: selection) from updating lastOpenedDeviceID
                isUpdatingFromDeepLink = true
                // Update selection from deep link - this will trigger onChange(of: selection)
                selection = requestedID
                lastSelectedDeviceID = requestedID
                // Reset flag after a delay to allow onChange(of: selection) to complete
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
                    isUpdatingFromDeepLink = false
                }
            }
        }
        .onChange(of: selection) { oldSelection, newSelection in
            // Only refresh map when the selected device actually changes to a different ID
            if let newSelection = newSelection, newSelection != lastSelectedDeviceID {
                // Reset any active navigation push so only the newly selected device is shown
                navigationTargetDevice = nil
                lastSelectedDeviceID = newSelection
                mapViewKey = UUID()
                // Do NOT update settings.lastOpenedDeviceID here - this prevents cross-window sync
                // settings.lastOpenedDeviceID will only be updated for deep links
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
}

#Preview {
    iPad_DevicesView()
} 
