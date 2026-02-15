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
    @StateObject private var visitorHistoryViewModel = VisitorHistoryViewModel()
    @ObservedObject private var ignoredStore = IgnoredVisitorDeviceStore.shared
    @EnvironmentObject private var groupStore: DeviceGroupStore
    @State private var showingAddDevice = false
    @State private var showingAddGroup = false
    @State private var prefillDeviceID: String? = nil
    @State private var pendingDeviceItem: DeviceIDItem? = nil
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
    @State private var lastUnknownVisitorSupplementalRefresh: Date? = nil
    @Environment(\.scenePhase) private var scenePhase
    
    private var unknownVisitors: [MiataruVisitor] {
        let knownDeviceIDs = Set(store.devices.map { $0.DeviceID.uppercased() })
        let ignoredDeviceIDs = Set(ignoredStore.ignoredDeviceIDs.map { $0.uppercased() })
        
        // Get unique DeviceIDs from visitors, keeping the most recent visit for each
        var uniqueVisitors: [String: MiataruVisitor] = [:]
        for visitor in visitorHistoryViewModel.sortedVisitors {
            let normalizedID = visitor.DeviceID.uppercased()
            if !knownDeviceIDs.contains(normalizedID) && !ignoredDeviceIDs.contains(normalizedID) && !normalizedID.isEmpty {
                if let existing = uniqueVisitors[normalizedID] {
                    // Keep the most recent visit
                    if visitor.TimeStampDate > existing.TimeStampDate {
                        uniqueVisitors[normalizedID] = visitor
                    }
                } else {
                    uniqueVisitors[normalizedID] = visitor
                }
            }
        }
        
        return Array(uniqueVisitors.values).sorted { $0.TimeStampDate > $1.TimeStampDate }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if settings.allowedDeviceListEnabled && !unknownVisitors.isEmpty {
                    Section(header: Text("unknown_visitors_section_title")) {
                        ForEach(unknownVisitors, id: \.uniqueID) { visitor in
                            UnknownVisitorRow(visitor: visitor) {
                                // Allow action - set pendingDeviceItem to trigger sheet with prefill
                                pendingDeviceItem = DeviceIDItem(id: visitor.DeviceID, deviceID: visitor.DeviceID)
                            } onIgnore: {
                                // Ignore action
                                ignoredStore.addIgnored(deviceID: visitor.DeviceID)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    // Set pendingDeviceItem to trigger sheet with prefill
                                    pendingDeviceItem = DeviceIDItem(id: visitor.DeviceID, deviceID: visitor.DeviceID)
                                } label: {
                                    Label("unknown_visitor_add_and_allow", systemImage: "plus.circle")
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    ignoredStore.addIgnored(deviceID: visitor.DeviceID)
                                } label: {
                                    Label("allowed_device_list_ignore_button", systemImage: "eye.slash")
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(store.devices) { device in
                        if editMode == .inactive {
                            NavigationLink(value: NavigationDestination.device(device.DeviceID)) {
                                DeviceRowView(device: device, cache: cache)
                            }
                            .listRowBackground(selectedDeviceID == device.DeviceID ? Color(.systemGray) : Color(.systemBackground))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task {
                                        await removeDevice(deviceID: device.DeviceID)
                                    }
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
                                        Task {
                                            await removeDevice(deviceID: device.DeviceID)
                                        }
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
                        Task {
                            for index in indices {
                                await removeDevice(deviceID: store.devices[index].DeviceID)
                            }
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
                                    .padding(8)
                                    .background {
                                        if #available(iOS 26.0, *) {
                                            Color.clear.glassEffect(in: .circle)
                                        } else {
                                            Circle().fill(.ultraThinMaterial)
                                        }
                                    }
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                                    .accessibilityLabel(Text(NSLocalizedString("grouplist_addbutton", comment: "Create a new group")))
                                    .accessibilityHint(Text(NSLocalizedString("grouplist_addbutton_hint", comment: "Opens the create group sheet")))
                            }
                            .buttonStyle(.plain)
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
            .sheet(item: $pendingDeviceItem) { item in
                iPhone_AddDeviceView(
                    store: store,
                    isPresented: Binding(
                        get: { pendingDeviceItem != nil },
                        set: { if !$0 { pendingDeviceItem = nil } }
                    ),
                    prefillDeviceID: item.deviceID
                )
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
                await visitorHistoryViewModel.loadVisitorHistory(showLoading: false)
                await refreshUnknownVisitorSupplementalDataIfNeeded(force: true)
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

                Task {
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: true, force: true)
                    await refreshUnknownVisitorSupplementalDataIfNeeded(force: true)
                }
            }
            .onDisappear {
                isVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate)) { _ in
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
                    await refreshUnknownVisitorSupplementalDataIfNeeded()
                }
            }
            
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
                    await refreshUnknownVisitorSupplementalDataIfNeeded()
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
    
    @MainActor
    private func removeDevice(deviceID: String) async {
        if settings.allowedDeviceListEnabled {
            do {
                try await AllowedDeviceListManager.shared.removeDeviceAndSync(deviceID: deviceID)
                Haptic.notifySuccess()
            } catch {
                Haptic.notifyWarning()
                debugLog("[DevicesView] Failed to remove device with sync: \(error)")
                // Device removal will be rolled back by AllowedDeviceListManager
            }
        } else {
            store.removeDevice(byID: deviceID)
        }
    }

    @MainActor
    private func refreshUnknownVisitorSupplementalDataIfNeeded(force: Bool = false) async {
        guard shouldRefreshUnknownVisitorSupplementalData(force: force) else { return }
        guard let serverURL = URL(string: settings.miataruServerURL) else { return }

        let unknownDeviceIDs = Array(Set(unknownVisitors.map { $0.DeviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }))
            .filter { !$0.isEmpty }
        guard !unknownDeviceIDs.isEmpty else {
            lastUnknownVisitorSupplementalRefresh = Date()
            return
        }

        await refreshUnknownVisitorLocations(
            deviceIDs: unknownDeviceIDs,
            serverURL: serverURL
        )

        let sloganRefreshInterval = max(1.0, Double(settings.outsideMapUpdateInterval))
        await refreshUnknownVisitorSlogans(
            deviceIDs: unknownDeviceIDs,
            serverURL: serverURL,
            minimumRefreshInterval: sloganRefreshInterval,
            force: force
        )

        lastUnknownVisitorSupplementalRefresh = Date()
    }

    @MainActor
    private func shouldRefreshUnknownVisitorSupplementalData(force: Bool) -> Bool {
        if force {
            return true
        }

        guard settings.autoRefreshDeviceList, isVisible else { return false }
        guard UIApplication.shared.applicationState == .active else { return false }

        let interval = max(1.0, Double(settings.outsideMapUpdateInterval))
        if let lastUnknownVisitorSupplementalRefresh,
           Date().timeIntervalSince(lastUnknownVisitorSupplementalRefresh) < interval {
            return false
        }

        return true
    }

    @MainActor
    private func refreshUnknownVisitorLocations(deviceIDs: [String], serverURL: URL) async {
        do {
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: serverURL,
                forDeviceIDs: deviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: settings.deviceKey
            )

            let foundIDs = Set(locations.map { $0.Device })
            for location in locations {
                cache.setLocation(
                    for: location.Device,
                    latitude: location.Latitude,
                    longitude: location.Longitude,
                    accuracy: location.HorizontalAccuracy,
                    timestamp: location.TimestampDate,
                    batteryLevel: location.BatteryLevel,
                    altitude: location.Altitude
                )
            }

            let missingIDs = Set(deviceIDs).subtracting(foundIDs)
            for missingID in missingIDs {
                cache.removeLocation(for: missingID)
            }
        } catch {
            debugLog("[DevicesView] Failed refreshing unknown visitor locations: \(error)")
        }
    }

    @MainActor
    private func refreshUnknownVisitorSlogans(deviceIDs: [String],
                                              serverURL: URL,
                                              minimumRefreshInterval: TimeInterval,
                                              force: Bool) async {
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }

        for deviceID in deviceIDs {
            await DeviceSloganCacheStore.shared.refreshSloganIfStale(
                for: deviceID,
                serverURL: serverURL,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: deviceKey,
                minimumRefreshInterval: minimumRefreshInterval,
                force: force
            )
        }
    }
}

private enum NavigationDestination: Hashable {
    case device(String)
    case group(String)
}

struct UnknownVisitorRow: View {
    let visitor: MiataruVisitor
    let onAllow: () -> Void
    let onIgnore: () -> Void
    
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    @ObservedObject private var locationCache = DeviceLocationCacheStore.shared
    
    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: visitor.TimeStampDate, relativeTo: Date())
    }

    private var sloganText: String? {
        guard let slogan = sloganCache.slogan(for: visitor.DeviceID), !slogan.isEmpty else { return nil }
        return slogan
    }

    private var locationText: String? {
        if let cached = locationCache.getLocation(for: visitor.DeviceID) {
            if let locality = cached.locality, let country = cached.country {
                return "\(locality), \(country)"
            }
            if let locality = cached.locality {
                return locality
            }
            if let country = cached.country {
                return country
            }
        }

        if let placemark = locationCache.getPlacemark(for: visitor.DeviceID) {
            if let locality = placemark.locality, let country = placemark.country {
                return "\(locality), \(country)"
            }
            if let locality = placemark.locality {
                return locality
            }
            if let country = placemark.country {
                return country
            }
        }
        return nil
    }

    private var primarySubtitleText: String? {
        sloganText ?? locationText
    }

    private var secondaryLocationText: String? {
        guard sloganText != nil else { return nil }
        return locationText
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(visitor.DeviceID)
                    .font(.body)
                    .fontWeight(.medium)

                if let primarySubtitleText {
                    Text(primarySubtitleText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let secondaryLocationText {
                    Text(secondaryLocationText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .onAppear {
                locationCache.enqueueGeocodingIfNeeded(for: visitor.DeviceID)
                Task {
                    await fetchSloganIfNeeded()
                }
            }
            Spacer()
            Menu {
                Button(role: .none) {
                    onAllow()
                } label: {
                    Label("unknown_visitor_add_and_allow", systemImage: "plus.circle")
                }
                
                Button(role: .destructive) {
                    onIgnore()
                } label: {
                    Label("allowed_device_list_ignore_button", systemImage: "eye.slash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    @MainActor
    private func fetchSloganIfNeeded() async {
        guard let serverURL = URL(string: settings.miataruServerURL) else { return }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }
        let refreshInterval = max(1.0, Double(settings.outsideMapUpdateInterval))

        await sloganCache.refreshSloganIfStale(
            for: visitor.DeviceID,
            serverURL: serverURL,
            requestingDeviceID: thisDeviceIDManager.shared.deviceID,
            requestingDeviceKey: deviceKey,
            minimumRefreshInterval: refreshInterval
        )
    }
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
