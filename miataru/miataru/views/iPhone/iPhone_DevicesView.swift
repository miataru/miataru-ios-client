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
    @ObservedObject private var appNavigation = AppNavigationCoordinator.shared
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    @StateObject private var visitorHistoryViewModel = VisitorHistoryViewModel()
    @ObservedObject private var ignoredStore = IgnoredVisitorDeviceStore.shared
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
    @State private var navigationTarget: DeviceNavigationTarget? = nil
    @State private var lastUnknownVisitorSupplementalRefresh: Date? = nil
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoomTransitionNamespace
    
    private var unknownVisitors: [MiataruVisitor] {
        UnknownVisitorFilter.visitors(
            from: visitorHistoryViewModel.sortedVisitors,
            knownDeviceIDs: Set(store.devices.map(\.DeviceID)),
            ignoredDeviceIDs: Set(ignoredStore.ignoredDeviceIDs),
            ownDeviceID: thisDeviceIDManager.shared.deviceID
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            devicesList
            .navigationTitle(String(localized: "devices", table: "Devices"))
            .toolbar { devicesToolbar }
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
                    .navigationTransition(
                        .zoom(
                            sourceID: MiataruZoomTransitionSource.device(deviceID),
                            in: zoomTransitionNamespace
                        )
                    )
                case .group(let groupID):
                    if let group = groupStore.groups.first(where: { $0.id == groupID }) {
                        iPhone_GroupMapView(group: group)
                            .navigationTransition(
                                .zoom(
                                    sourceID: MiataruZoomTransitionSource.group(groupID),
                                    in: zoomTransitionNamespace
                                )
                            )
                    } else {
                        Text(NSLocalizedString("Group not found", tableName: "Groups", comment: "Shown when a group with the given ID does not exist"))
                    }
                }
            }
            .navigationDestination(item: $navigationTarget) { target in
                iPhone_DeviceNavigationView(device: target.device, launchOptions: target.launchOptions)
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
                await refreshDeviceListFromPull()
            }
            .onAppear {
                handleAppear()
            }
            .onDisappear {
                isVisible = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate)) { _ in
                handleOwnLocationUpdateSent()
            }
            
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                handleAppDidBecomeActive()
            }
            .task(id: autoRefreshTaskID) {
                await runAutoRefreshLoop()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: settings.lastOpenedDeviceID) { _, newDeviceID in
                handleLastOpenedDeviceIDChange(newDeviceID)
            }
            .onChange(of: appNavigation.deviceOpenRequest) { _, request in
                handleDeviceOpenRequest(request)
            }
            .onChange(of: appNavigation.deviceNavigationOpenRequest) { _, request in
                handleDeviceNavigationOpenRequest(request)
            }
            // Intentionally do not reset didAutoNavigateFromSavedDevice on
            // changes to lastOpenedDeviceID to avoid unintended re-pushes
        }
    }

    private var autoRefreshTaskID: String {
        "\(settings.outsideMapUpdateInterval)-\(settings.autoRefreshDeviceList)"
    }

    @MainActor
    private func refreshDeviceListFromPull() async {
        let success = await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)
        await visitorHistoryViewModel.loadVisitorHistory(showLoading: false)
        await refreshUnknownVisitorSupplementalDataIfNeeded(force: true)
        if success { Haptic.notifySuccess() }
    }

    @MainActor
    private func handleAppear() {
        isVisible = true
        if !isUITesting,
           !hasPerformedInitialAutoNavigate,
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
        handleDeviceOpenRequest(appNavigation.deviceOpenRequest)
        handleDeviceNavigationOpenRequest(appNavigation.deviceNavigationOpenRequest)
    }

    @MainActor
    private func handleOwnLocationUpdateSent() {
        Task {
            _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
            await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
            await refreshUnknownVisitorSupplementalDataIfNeeded()
        }
    }

    @MainActor
    private func handleAppDidBecomeActive() {
        Task {
            _ = await DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)
            await visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)
            await refreshUnknownVisitorSupplementalDataIfNeeded()
        }
        reassertLastOpenedDeviceAfterActivation()
    }

    @MainActor
    private func reassertLastOpenedDeviceAfterActivation() {
        guard !isUITesting,
              let requestedID = settings.lastOpenedDeviceID,
              store.devices.contains(where: { $0.DeviceID == requestedID }),
              navigationPath.last != .device(requestedID) else { return }

        Task { @MainActor in
            navigationPath = []
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard settings.lastOpenedDeviceID == requestedID else { return }
            navigationPath = [.device(requestedID)]
        }
    }

    @MainActor
    private func runAutoRefreshLoop() async {
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

    @MainActor
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if (newPhase == .inactive || newPhase == .background) && navigationPath.isEmpty {
            settings.lastOpenedDeviceID = nil
        }
    }

    @MainActor
    private func handleLastOpenedDeviceIDChange(_ newDeviceID: String?) {
        guard !isUITesting else { return }
        guard let deviceID = newDeviceID,
              store.devices.contains(where: { $0.DeviceID == deviceID }) else { return }
        let requestedID = deviceID
        Task { @MainActor in
            if navigationPath.last == .device(requestedID) {
                return
            }

            navigationPath = []
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard settings.lastOpenedDeviceID == requestedID else { return }
            navigationPath = [.device(requestedID)]
        }
    }

    private var devicesList: some View {
        List {
            unknownVisitorsSection
            frequentLocationUpdatesSection
            devicesSection
            groupsSection
        }
        .environment(\.editMode, $editMode)
    }

    @ViewBuilder
    private var unknownVisitorsSection: some View {
        if !unknownVisitors.isEmpty {
            Section(header: Text("unknown_visitors_section_title", tableName: "Devices")) {
                ForEach(unknownVisitors, id: \.uniqueID) { visitor in
                    unknownVisitorRow(for: visitor)
                }
            }
        }
    }

    @ViewBuilder
    private var frequentLocationUpdatesSection: some View {
        if settings.trackAndReportLocation && settings.frequentBackgroundLocationUpdatesEnabled {
            Section {
                FrequentBackgroundLocationUpdatesDeviceListNotice(expiresAt: settings.frequentBackgroundLocationUpdatesExpiresAt) {
                    AppNavigationCoordinator.shared.openAdvancedSettings()
                }
            }
        }
    }

    private var devicesSection: some View {
        Section {
            ForEach(store.devices) { device in
                deviceRow(for: device)
            }
            .onMove { indices, newOffset in
                store.move(fromOffsets: indices, toOffset: newOffset)
            }
            .onDelete { indices in
                Task {
                    for index in indices {
                        await removeDevice(deviceID: store.devices[index].DeviceID)
                    }
                }
            }
        }
    }

    private var groupsSection: some View {
        Section {
            groupRows
        } header: {
            groupSectionHeader
        }
        .environment(\.editMode, $groupEditMode)
    }

    @ViewBuilder
    private var groupRows: some View {
        if groupStore.groups.isEmpty {
            emptyGroupsView
        } else {
            ForEach(groupStore.groups) { group in
                groupRow(for: group)
            }
            .onMove { indices, newOffset in
                groupStore.move(fromOffsets: indices, toOffset: newOffset)
            }
            .onDelete { indices in
                groupStore.remove(atOffsets: indices)
            }
        }
    }

    private var emptyGroupsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("No groups yet", tableName: "Groups", comment: "Shown when there are no groups in the list"))
                .font(.headline)
            Text(NSLocalizedString("Tap the + button to create a new group.", tableName: "Groups", comment: "Instruction to create a new group when none exist"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var groupSectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 12) {
                Text(NSLocalizedString("groups", tableName: "Groups", comment: "Section header for the groups list"))
                    .font(.headline)
                Spacer()
                groupEditButton
                addGroupButton
            }
        }
        .textCase(nil)
    }

    private var groupEditButton: some View {
        Button {
            groupEditMode = groupEditMode == .active ? .inactive : .active
        } label: {
            groupEditButtonLabel
        }
        .disabled(groupStore.groups.isEmpty)
    }

    @ViewBuilder
    private var groupEditButtonLabel: some View {
        if groupEditMode == .active {
            Text(NSLocalizedString("grouplist_edit_done", tableName: "Groups", comment: "Finish editing the groups list."))
        } else {
            EmptyView()
        }
    }

    private var addGroupButton: some View {
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
                .accessibilityLabel(Text(NSLocalizedString("grouplist_addbutton", tableName: "Groups", comment: "Create a new group")))
                .accessibilityHint(Text(NSLocalizedString("grouplist_addbutton_hint", tableName: "Groups", comment: "Opens the create group sheet")))
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var devicesToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                editMode = editMode == .active ? .inactive : .active
            } label: {
                deviceEditButtonLabel
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            addDeviceButton
        }
    }

    @ViewBuilder
    private var deviceEditButtonLabel: some View {
        if editMode == .active {
            Text(NSLocalizedString("devicelist_edit_done", tableName: "Devices", comment: "Finish editing the device list."))
        } else {
            Image(systemName: "pencil")
                .accessibilityLabel(Text(NSLocalizedString("devicelist_editbutton", tableName: "Devices", comment: "Edit device list")))
                .accessibilityHint(Text(NSLocalizedString("devicelist_editbutton_hint", tableName: "Devices", comment: "Enters edit mode for the device list")))
        }
    }

    private var addDeviceButton: some View {
        Button(action: { showingAddDevice = true }) {
            Image(systemName: "plus")
                .accessibilityLabel(Text(NSLocalizedString("devicelist_addbutton", tableName: "Devices", comment: "Add a new device to your list")))
                .accessibilityHint(Text(NSLocalizedString("devicelist_addbutton_hint", tableName: "Devices", comment: "Opens the add device form")))
        }
        .accessibilityIdentifier("devices_add_button")
    }

    private func unknownVisitorRow(for visitor: MiataruVisitor) -> some View {
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
                    String(
                        localized: settings.allowedDeviceListEnabled
                            ? "unknown_visitor_add_and_allow"
                            : "add",
                        table: settings.allowedDeviceListEnabled ? "Devices" : "Common"
                    ),
                    systemImage: "plus.circle"
                )
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                ignoredStore.addIgnored(deviceID: visitor.DeviceID)
            } label: {
                Label(String(localized: "allowed_device_list_ignore_button", table: "Devices"), systemImage: "eye.slash")
            }
        }
    }

    private func groupRow(for group: DeviceGroup) -> some View {
        NavigationLink(value: NavigationDestination.group(group.id)) {
            GroupRowView(group: group)
                .matchedTransitionSource(
                    id: MiataruZoomTransitionSource.group(group.id),
                    in: zoomTransitionNamespace
                )
        }
        .listRowBackground(selectedGroupID == group.id ? Color(.systemGray) : Color(.systemBackground))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                if let index = groupStore.groups.firstIndex(where: { $0.id == group.id }) {
                    groupStore.remove(atOffsets: IndexSet(integer: index))
                }
            } label: {
                Label(String(localized: "delete_group", table: "Groups"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                editingGroup = group
                selectedGroupID = group.id
            } label: {
                Label(String(localized: "edit_group", table: "Groups"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private func deviceRow(for device: KnownDevice) -> some View {
        if editMode == .inactive {
            activeDeviceRow(for: device)
        } else {
            editableDeviceRow(for: device)
        }
    }

    private func activeDeviceRow(for device: KnownDevice) -> some View {
        NavigationLink(value: NavigationDestination.device(device.DeviceID)) {
            DeviceRowView(device: device, cache: cache, showsSlogan: true)
                .matchedTransitionSource(
                    id: MiataruZoomTransitionSource.device(device.DeviceID),
                    in: zoomTransitionNamespace
                )
        }
        .accessibilityIdentifier(deviceAccessibilityIdentifier(for: device))
        .listRowBackground(deviceRowBackground(for: device))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteDeviceButton(for: device)
        }
        .swipeActions(edge: .leading) {
            navigationSwipeButton(for: device)
            editDeviceSwipeButton(for: device)
        }
    }

    private func editableDeviceRow(for device: KnownDevice) -> some View {
        DeviceRowView(device: device, cache: cache, showsSlogan: true)
            .contentShape(Rectangle())
            .onTapGesture {
                editingDevice = device
                selectedDeviceID = device.DeviceID
            }
            .listRowBackground(deviceRowBackground(for: device))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                deleteDeviceButton(for: device)
            }
            .swipeActions(edge: .leading) {
                navigationSwipeButton(for: device)
                editDeviceSwipeButton(for: device)
            }
    }

    private func deviceAccessibilityIdentifier(for device: KnownDevice) -> String {
        device.DeviceID == thisDeviceIDManager.shared.deviceID
            ? "devices_row_this_device"
            : "devices_row_\(device.DeviceID)"
    }

    private func deviceRowBackground(for device: KnownDevice) -> Color {
        selectedDeviceID == device.DeviceID ? Color(.systemGray) : Color(.systemBackground)
    }

    private func canNavigate(to device: KnownDevice) -> Bool {
        device.DeviceID != thisDeviceIDManager.shared.deviceID && cache.getLocation(for: device.DeviceID) != nil
    }

    @ViewBuilder
    private func navigationSwipeButton(for device: KnownDevice) -> some View {
        if canNavigate(to: device) {
            Button {
                navigationTarget = DeviceNavigationTarget(device: device)
            } label: {
                Label(String(localized: "navigation", table: "MapNavigationHistory"), systemImage: "location")
            }
            .tint(.green)
        }
    }

    private func editDeviceSwipeButton(for device: KnownDevice) -> some View {
        Button {
            editingDevice = device
        } label: {
            Label(String(localized: "edit_device_swipe", table: "Devices"), systemImage: "pencil")
        }
        .tint(.blue)
    }

    private func deleteDeviceButton(for device: KnownDevice) -> some View {
        Button(role: .destructive) {
            Task {
                await removeDevice(deviceID: device.DeviceID)
            }
        } label: {
            Label(String(localized: "delete_device", table: "Devices"), systemImage: "trash")
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
            navigationPath = []
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)
            navigationPath = [.device(deviceID)]
            settings.lastOpenedDeviceID = deviceID
            appNavigation.consumeDeviceOpenRequest(request)
        }
    }

    @MainActor
    private func handleDeviceNavigationOpenRequest(_ request: DeviceNavigationOpenRequest?) {
        guard let request else { return }
        guard let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: request.deviceID, store: store),
              let device = store.devices.first(where: { $0.DeviceID == deviceID }) else {
            appNavigation.consumeDeviceNavigationOpenRequest(request)
            return
        }

        Task { @MainActor in
            navigationPath = []
            navigationTarget = nil
            await Task.yield()
            try? await Task.sleep(nanoseconds: 180_000_000)
            navigationTarget = DeviceNavigationTarget(device: device, launchOptions: request.options)
            appNavigation.consumeDeviceNavigationOpenRequest(request)
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
            debugLog("[DevicesView] Failed refreshing unknown visitor locations: \(error)")
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
                debugLog("[DevicesView] Failed refreshing unknown visitor slogan for \(deviceID): \(error)")
            }
        }
    }

}

private enum NavigationDestination: Hashable {
    case device(String)
    case group(String)
}

private struct DeviceNavigationTarget: Identifiable, Hashable {
    let id = UUID()
    let device: KnownDevice
    let launchOptions: DeviceNavigationLaunchOptions

    init(device: KnownDevice, launchOptions: DeviceNavigationLaunchOptions = .standard) {
        self.device = device
        self.launchOptions = launchOptions
    }

    static func == (lhs: DeviceNavigationTarget, rhs: DeviceNavigationTarget) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct UnknownVisitorRow: View {
    let visitor: MiataruVisitor
    let onShowActions: () -> Void
    let onIgnore: () -> Void
    
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
            }
            Spacer()
            Button(action: onShowActions) {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("unknown_device_actions_title", tableName: "Devices"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onShowActions()
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
