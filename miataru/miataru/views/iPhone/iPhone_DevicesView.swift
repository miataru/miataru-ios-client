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
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var showingAddDevice = false
    @State private var showingAddGroup = false
    @State private var prefillDeviceID: String? = nil
    @State private var editMode: EditMode = .inactive
    @State private var groupEditMode: EditMode = .inactive
    @State private var editingDevice: KnownDevice? = nil
    @State private var editingGroup: DeviceGroup? = nil
    @State private var selectedDeviceID: String? = nil
    @State private var selectedGroupID: String? = nil
    @State private var isVisible: Bool = false
    @State private var navigationPath: [NavigationDestination] = [] // Typed navigation path for device/group IDs
    @State private var didAutoNavigateFromSavedDevice: Bool = false
    @State private var hasPerformedInitialAutoNavigate: Bool = false
    @State private var navigationTargetDevice: KnownDevice? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    ForEach(store.devices) { device in
                        if editMode == .inactive {
                            NavigationLink(value: NavigationDestination.device(device.DeviceID)) {
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
                Section {
                    if groupStore.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("No groups yet", comment: "Shown when there are no groups in the list"))
                                .font(.headline)
                            Text(NSLocalizedString("Tap the + button to create a new group.", comment: "Instruction to create a new group when none exist"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(groupStore.groups) { group in
                            NavigationLink(value: NavigationDestination.group(group.id)) {
                                GroupRowView(group: group)
                            }
                            .listRowBackground(selectedGroupID == group.id ? Color(.systemGray) : Color(.systemBackground))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    if let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) {
                                        groupStore.remove(atOffsets: IndexSet(integer: index))
                                    }
                                } label: {
                                    Label("delete_group", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingGroup = group
                                    selectedGroupID = group.id
                                } label: {
                                    Label {
                                        Text(NSLocalizedString("edit_group", comment: "Edit group"))
                                    } icon: {
                                        Image(systemName: "pencil")
                                    }
                                }
                                .tint(.blue)
                            }
                        }
                        .onMove { indices, newOffset in
                            groupStore.move(fromOffsets: indices, toOffset: newOffset)
                        }
                        .onDelete { indices in
                            groupStore.remove(atOffsets: indices)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        HStack(spacing: 12) {
                            Text(NSLocalizedString("groups", comment: "Section header for the groups list"))
                                .font(.headline)
                            Spacer()
                            Button {
                                groupEditMode = groupEditMode == .active ? .inactive : .active
                            } label: {
                                if groupEditMode == .active {
                                    Text(NSLocalizedString("grouplist_edit_done", comment: "Finish editing the groups list."))
                                } else {
                                    /*Image(systemName: "pencil")
                                        .accessibilityLabel(Text(NSLocalizedString("grouplist_editbutton", comment: "Edit groups list")))
                                        .accessibilityHint(Text(NSLocalizedString("grouplist_editbutton_hint", comment: "Enters edit mode for the groups list")))
                                */
                                }
                            }
                            .disabled(groupStore.groups.isEmpty)
                            Button(action: { showingAddGroup = true }) {
                                Image(systemName: "plus")
                                    .accessibilityLabel(Text(NSLocalizedString("grouplist_addbutton", comment: "Create a new group")))
                                    .accessibilityHint(Text(NSLocalizedString("grouplist_addbutton_hint", comment: "Opens the create group sheet")))
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                        }
                    }
                    .textCase(nil)
                }
                .environment(\.editMode, $groupEditMode)
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
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .device(let deviceID):
                    iPhone_DeviceMapView(
                        deviceID: deviceID,
                        onNavigateToDevice: { newDeviceID in
                            // Push another device map view onto the stack
                            navigationPath.append(.device(newDeviceID))
                        }
                    )
                case .group(let groupID):
                    if let group = groupStore.groups.first(where: { $0.id == groupID }) {
                        iPhone_GroupMapView(group: group)
                    } else {
                        Text(NSLocalizedString("Group not found", comment: "Shown when a group with the given ID does not exist"))
                    }
                }
            }
            .navigationDestination(item: $navigationTargetDevice) { device in
                iPhone_DeviceNavigationView(device: device)
            }
            .sheet(isPresented: $showingAddDevice) {
                iPhone_AddDeviceView(store: store, isPresented: $showingAddDevice, prefillDeviceID: prefillDeviceID)
            }
            .sheet(isPresented: $showingAddGroup) {
                iPhone_AddGroupView(groupStore: groupStore, isPresented: $showingAddGroup)
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
            .sheet(item: $editingGroup) { group in
                GroupEditSheetContainer(group: group) {
                    editingGroup = nil
                    selectedGroupID = nil
                } onSave: {
                    editingGroup = nil
                    selectedGroupID = nil
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
                    navigationPath.append(.device(lastID))
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
                   navigationPath.last != .device(requestedID) {
                    Task { @MainActor in
                        navigationPath = []
                        await Task.yield()
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        guard settings.lastOpenedDeviceID == requestedID else { return }
                        navigationPath = [.device(requestedID)]
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
                    if navigationPath.last == .device(requestedID) {
                        return
                    }

                    // Clear first, then set after a short delay to override any restored navigation state.
                    navigationPath = []
                    await Task.yield()
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    // Guard against a stale delayed task (e.g. multiple widget taps).
                    guard settings.lastOpenedDeviceID == requestedID else { return }
                    navigationPath = [.device(requestedID)]
                }
            }
            // Intentionally do not reset didAutoNavigateFromSavedDevice on
            // changes to lastOpenedDeviceID to avoid unintended re-pushes
        }
    }
}

private enum NavigationDestination: Hashable {
    case device(String)
    case group(String)
}

#Preview {
    let store = KnownDeviceStore.shared
    store.devices = [
        KnownDevice(name: "iPhone 13", deviceID: UUID().uuidString, color: .red),
        KnownDevice(name: "iPad Pro", deviceID: UUID().uuidString, color: .green),
        KnownDevice(name: "MacBook Air", deviceID: UUID().uuidString, color: .blue)
    ]
    let groupStore = DeviceGroupStore.shared
    groupStore.groups = [
        DeviceGroup(name: "Family"),
        DeviceGroup(name: "Work"),
        DeviceGroup(name: "Friends")
    ]
    return iPhone_DevicesView()
        .environmentObject(store)
        .environmentObject(groupStore)
}
