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
    @ObservedObject private var appNavigation = AppNavigationCoordinator.shared
    @StateObject private var visitorHistoryViewModel = VisitorHistoryViewModel()
    @ObservedObject private var ignoredStore = IgnoredVisitorDeviceStore.shared

    @State private var selection: String? = nil // DeviceID
    @State private var showingAddDevice = false
    @State private var editingDevice: KnownDevice? = nil
    @State private var editMode: EditMode = .inactive
    @State private var isVisible: Bool = false
    @State private var mapViewKey: UUID = UUID() // Force map view refresh when device changes
    @State private var lastSelectedDeviceID: String? = nil // Track last non-nil selection to avoid unnecessary resets
    @State private var navigationTargetDevice: KnownDevice? = nil
    @State private var isUpdatingFromDeepLink = false // Track if we're updating selection from deep link (to prevent circular updates)
    @State private var lastUnknownVisitorSupplementalRefresh: Date? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    private var unknownVisitors: [MiataruVisitor] {
        UnknownVisitorFilter.visitors(
            from: visitorHistoryViewModel.sortedVisitors,
            knownDeviceIDs: Set(store.devices.map(\.DeviceID)),
            ignoredDeviceIDs: Set(ignoredStore.ignoredDeviceIDs),
            ownDeviceID: thisDeviceIDManager.shared.deviceID
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                iPadSidebarListHeader(
                    title: NSLocalizedString("devices", comment: "Devices list title on iPad"),
                    editTitle: editMode == .active
                        ? NSLocalizedString("devicelist_edit_done", comment: "Finish editing the device list.")
                        : NSLocalizedString("devicelist_editbutton", comment: "Edit device list"),
                    onToggleEdit: {
                        editMode = editMode == .active ? .inactive : .active
                    },
                    onAdd: {
                        showingAddDevice = true
                    },
                    onToggleSidebar: {
                        withAnimation {
                            columnVisibility = .detailOnly
                        }
                    },
                    addAccessibilityLabel: NSLocalizedString("devicelist_addbutton", comment: "Add a new device to your list"),
                    addAccessibilityHint: NSLocalizedString("devicelist_addbutton_hint", comment: "Opens the add device form"),
                    addAccessibilityIdentifier: "devices_add_button"
                )

                List(selection: $selection) {
                    if !unknownVisitors.isEmpty {
                        Section(header: Text("unknown_visitors_section_title")) {
                            ForEach(unknownVisitors, id: \.uniqueID) { visitor in
                                UnknownVisitorRow(
                                    visitor: visitor,
                                    onShowActions: {
                                        appNavigation.presentUnknownDeviceActions(visitor.DeviceID, visitDate: visitor.TimeStampDate)
                                    },
                                    onIgnore: {
                                        ignoredStore.addIgnored(deviceID: visitor.DeviceID)
                                    }
                                )
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        appNavigation.openAddDevice(visitor.DeviceID, source: .unknownVisitor)
                                    } label: {
                                        Label(
                                            settings.allowedDeviceListEnabled
                                                ? "unknown_visitor_add_and_allow"
                                                : "add",
                                            systemImage: "plus.circle"
                                        )
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

                    Section(header: Text(NSLocalizedString("devices", comment: "Devices list header on iPad"))) {
                        if settings.trackAndReportLocation && settings.frequentBackgroundLocationUpdatesEnabled {
                            FrequentBackgroundLocationUpdatesDeviceListNotice(expiresAt: settings.frequentBackgroundLocationUpdatesExpiresAt) {
                                AppNavigationCoordinator.shared.openAdvancedSettings()
                            }
                        }

                        ForEach(store.devices) { device in
                            if cache.getLocation(for: device.DeviceID) != nil {
                                DeviceRowView(device: device, cache: cache, showsSlogan: true)
                                    .accessibilityIdentifier(
                                        device.DeviceID == thisDeviceIDManager.shared.deviceID
                                            ? "devices_row_this_device"
                                            : "devices_row_\(device.DeviceID)"
                                    )
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
                                            Task {
                                                await removeDevice(deviceID: device.DeviceID)
                                            }
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
                                DeviceRowView(device: device, cache: cache, showsSlogan: true)
                                    .accessibilityIdentifier(
                                        device.DeviceID == thisDeviceIDManager.shared.deviceID
                                            ? "devices_row_this_device"
                                            : "devices_row_\(device.DeviceID)"
                                    )
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
                                            Task {
                                                await removeDevice(deviceID: device.DeviceID)
                                            }
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
                            let deviceIDs = indices.map { store.devices[$0].DeviceID }
                            Task {
                                for deviceID in deviceIDs {
                                    await removeDevice(deviceID: deviceID)
                                }
                            }
                        }
                        .onMove { indices, newOffset in
                            store.move(fromOffsets: indices, toOffset: newOffset)
                        }
                    }
                }
                .listStyle(.sidebar)
                .contentMargins(.top, 0, for: .scrollContent)
                .refreshable {
                    let success = await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)
                    await visitorHistoryViewModel.loadVisitorHistory(showLoading: false)
                    await refreshUnknownVisitorSupplementalDataIfNeeded(force: true)
                    if success { Haptic.notifySuccess() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(.container, edges: .top)
            .environment(\.editMode, $editMode)
            .onAppear {
                isVisible = true
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

                Task {
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: true, force: true)
                    await refreshUnknownVisitorSupplementalDataIfNeeded(force: true)
                }
                handleDeviceOpenRequest(appNavigation.deviceOpenRequest)
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
            .task(id: "\(settings.outsideMapUpdateInterval)-\(settings.autoRefreshDeviceList)") {
                let seconds = max(5.0, Double(settings.outsideMapUpdateInterval))
                let interval = UInt64(seconds * 1_000_000_000)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: interval)
                    guard isVisible,
                          UIApplication.shared.applicationState == .active else { continue }
                    _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: true)
                    await visitorHistoryViewModel.refreshIfNeeded(isVisible: true)
                    await refreshUnknownVisitorSupplementalDataIfNeeded()
                }
            }
            .onChange(of: appNavigation.deviceOpenRequest) { _, request in
                handleDeviceOpenRequest(request)
            }
        } detail: {
            NavigationStack {
                if let selectedID = (selection ?? lastSelectedDeviceID), let device = store.devices.first(where: { $0.DeviceID == selectedID }) {
                    iPad_DeviceMapView(
                        deviceID: device.DeviceID,
                        onNavigateToDevice: { newDeviceID in
                            selection = newDeviceID
                        },
                        // Only update lastOpenedDeviceID for deep links, not for local selections.
                        shouldUpdateLastOpenedDeviceID: isUpdatingFromDeepLink
                    )
                    .id(mapViewKey)
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
                if selection == requestedID {
                    return
                }
                await Task.yield()
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard settings.lastOpenedDeviceID == requestedID else {
                    isUpdatingFromDeepLink = false
                    return
                }
                isUpdatingFromDeepLink = true
                selection = requestedID
                lastSelectedDeviceID = requestedID
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    isUpdatingFromDeepLink = false
                }
            }
        }
        .onChange(of: selection) { _, newSelection in
            if let newSelection = newSelection, newSelection != lastSelectedDeviceID {
                navigationTargetDevice = nil
                lastSelectedDeviceID = newSelection
                mapViewKey = UUID()
            }
        }
        .onChange(of: editMode) { _, newMode in
            if newMode == .active, selection == nil, let last = lastSelectedDeviceID {
                selection = last
            }
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
                debugLog("[iPad_DevicesView] Failed to remove device with sync: \(error)")
                // Device removal will be rolled back by AllowedDeviceListManager.
            }
        } else {
            store.removeDevice(byID: deviceID)
            PersistentDataCleanup.run()
        }
    }

    @MainActor
    private func handleDeviceOpenRequest(_ request: DeviceOpenRequest?) {
        guard let request else { return }
        guard let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: request.deviceID, store: store) else {
            appNavigation.consumeDeviceOpenRequest(request)
            return
        }

        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)
            isUpdatingFromDeepLink = true
            selection = deviceID
            lastSelectedDeviceID = deviceID
            mapViewKey = UUID()
            settings.lastOpenedDeviceID = deviceID
            appNavigation.consumeDeviceOpenRequest(request)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                isUpdatingFromDeepLink = false
            }
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
        await refreshUnknownVisitorMissingSlogans(
            deviceIDs: unknownDeviceIDs,
            serverURL: serverURL,
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
            let locations = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: deviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: settings.deviceKey
            )

            let foundIDs = Set(locations.map { $0.Device })
            let missingIDs = Set(deviceIDs).subtracting(foundIDs)
            cache.ingestServerLocations(locations, removingMissingDeviceIDs: missingIDs)
        } catch {
            debugLog("[iPad_DevicesView] Failed refreshing unknown visitor locations: \(error)")
        }
    }

    @MainActor
    private func refreshUnknownVisitorMissingSlogans(deviceIDs: [String], serverURL: URL, force: Bool) async {
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }
        let minimumRefreshInterval = max(5.0, Double(settings.outsideMapUpdateInterval))

        for deviceID in deviceIDs {
            if let cachedSlogan = DeviceSloganCacheStore.shared.slogan(for: deviceID),
               !cachedSlogan.isEmpty {
                continue
            }
            if !DeviceSloganCacheStore.shared.shouldRefresh(
                for: deviceID,
                minimumRefreshInterval: minimumRefreshInterval,
                force: force
            ) {
                continue
            }

            do {
                _ = try await MiataruAppAPI.fetchAndCacheDeviceSlogan(
                    serverURL: serverURL,
                    forDeviceID: deviceID,
                    requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                    requestingDeviceKey: deviceKey
                )
            } catch {
                debugLog("[iPad_DevicesView] Failed refreshing unknown visitor slogan for \(deviceID): \(error)")
            }
        }
    }

}

struct iPadSidebarListHeader: View {
    let title: String
    let editTitle: String
    let onToggleEdit: () -> Void
    let onAdd: () -> Void
    let onToggleSidebar: () -> Void
    let addAccessibilityLabel: String
    let addAccessibilityHint: String
    let addAccessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleEdit) {
                Text(editTitle)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .frame(width: 104, alignment: .leading)

            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel(Text(addAccessibilityLabel))
                .accessibilityHint(Text(addAccessibilityHint))
                .accessibilityIdentifier(addAccessibilityIdentifier)

                Button(action: onToggleSidebar) {
                    Image(systemName: "sidebar.left")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel(Text("Hide sidebar"))
                .accessibilityHint(Text("Shows the map without the sidebar"))
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}

#Preview {
    iPad_DevicesView()
}
