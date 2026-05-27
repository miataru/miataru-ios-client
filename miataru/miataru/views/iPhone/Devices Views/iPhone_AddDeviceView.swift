/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_AddDeviceView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import CodeScanner

struct iPhone_AddDeviceView: View {
    @ObservedObject var store: KnownDeviceStore
    @Binding var isPresented: Bool
    var prefillDeviceID: String? = nil
    var allowsDeviceIDEditing: Bool = true
    @State private var deviceName: String = ""
    @State private var deviceID: String = ""
    @State private var deviceColor: Color = Self.randomVividColor()
    @State private var isShowingScanner = false
    @State private var showInvalidQRAlert = false
    @State private var showDuplicateAlert = false
    @State private var duplicateDeviceIDMessage: String = ""
    @State private var showColorPickerSheet = false
    @State private var hasCurrentLocationAccess: Bool = true
    @State private var hasHistoryAccess: Bool = false
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var fetchedSlogan: String = ""
    @State private var isLoadingSlogan = false
    @State private var sloganLookupTask: Task<Void, Never>? = nil
    @State private var isLoadingSecurityStatus = false
    @State private var securityStatusLookupTask: Task<Void, Never>? = nil
    @State private var deviceKeySecurityStatus: DeviceSecurityStatus = .unknown
    @State private var aclSecurityStatus: DeviceSecurityStatus = .unknown
    @State private var isActivatingAllowedDeviceList = false
    @State private var activationError: String? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared

    private enum DeviceSecurityStatus {
        case active
        case inactive
        case unknown
    }
    
    // Returns a random vivid color from an extensive palette of visible colors
    private static func randomVividColor() -> Color {
        let vividColors: [Color] = [
            // Standard SwiftUI named colors
            .red, .orange, .yellow, .green, .blue, .purple, .pink,
            .mint, .teal, .cyan, .indigo,
            // Additional vibrant colors using RGB
            Color(red: 1.0, green: 0.0, blue: 0.5),      // Hot pink
            Color(red: 1.0, green: 0.4, blue: 0.0),     // Orange red
            Color(red: 1.0, green: 0.6, blue: 0.0),      // Dark orange
            Color(red: 0.0, green: 0.8, blue: 0.4),      // Emerald green
            Color(red: 0.0, green: 0.6, blue: 1.0),      // Sky blue
            Color(red: 0.2, green: 0.6, blue: 1.0),      // Light blue
            Color(red: 0.4, green: 0.0, blue: 1.0),       // Violet
            Color(red: 0.6, green: 0.0, blue: 1.0),       // Purple
            Color(red: 0.8, green: 0.0, blue: 0.8),      // Magenta
            Color(red: 1.0, green: 0.0, blue: 0.8),      // Fuchsia
            Color(red: 0.0, green: 0.9, blue: 0.7),      // Turquoise
            Color(red: 0.0, green: 0.7, blue: 0.9),      // Cyan blue
            Color(red: 0.3, green: 0.9, blue: 0.3),      // Lime green
            Color(red: 0.9, green: 0.9, blue: 0.0),      // Gold
            Color(red: 1.0, green: 0.5, blue: 0.0),      // Deep orange
            Color(red: 0.8, green: 0.2, blue: 0.6),      // Rose
            Color(red: 0.5, green: 0.0, blue: 0.8),      // Deep purple
            Color(red: 0.0, green: 0.5, blue: 0.8),      // Ocean blue
            Color(red: 0.2, green: 0.8, blue: 0.2),     // Bright green
            Color(red: 0.9, green: 0.3, blue: 0.3),      // Coral
        ]
        return vividColors.randomElement() ?? .blue
    }
    
    init(store: KnownDeviceStore, isPresented: Binding<Bool>, prefillDeviceID: String? = nil, allowsDeviceIDEditing: Bool = true) {
        self.store = store
        self._isPresented = isPresented
        self.prefillDeviceID = prefillDeviceID
        self.allowsDeviceIDEditing = allowsDeviceIDEditing
        if let prefill = prefillDeviceID {
            _deviceID = State(initialValue: prefill)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $deviceName)

                    if hasSimilarDeviceName {
                        Label("device_name_similar_warning", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Info")
                        Spacer()
                        if isLoadingSlogan {
                            ProgressView()
                                .scaleEffect(0.9)
                        } else {
                            Text(fetchedSlogan.isEmpty ? "-" : fetchedSlogan)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        adoptSloganAsDeviceNameIfNeeded()
                    }
                }
                Section(header: Text("device_id")) {
                    if allowsDeviceIDEditing {
                        Button(action: { isShowingScanner = true }) {
                            Label("scan_qr_code", systemImage: "qrcode.viewfinder")
                        }
                        .accessibilityIdentifier("add_device_scan_qr_button")
                        TextField("device_id2", text: $deviceID)
                            .accessibilityIdentifier("add_device_device_id_field")
                    } else {
                        Text(deviceID.isEmpty ? "-" : deviceID)
                            .font(.footnote.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("add_device_locked_device_id")
                    }
                }
                Section(header: Text("device_color")) {
                    Button(action: { showColorPickerSheet = true }) {
                        HStack {
                            Circle().fill(deviceColor).frame(width: 24, height: 24)
                            Text(NSLocalizedString("Pick Color", comment: "Button label to open color picker sheet"))
                        }
                    }
                    .sheet(isPresented: $showColorPickerSheet) {
                        ColorPickerSheet(selectedColor: $deviceColor)
                            .presentationDetents([.medium])
                    }
                }
                if settings.allowedDeviceListEnabled {
                    Section(header: Text("allowed_device_list_access_controls")) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("allowed_device_list_security_overview_label")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: deviceKeySecurityStatusIcon)
                                    Text(deviceKeySecurityStatusText)
                                }
                                .foregroundColor(deviceKeySecurityStatusColor)
                                HStack(spacing: 6) {
                                    Image(systemName: aclSecurityStatusIcon)
                                    Text(aclSecurityStatusText)
                                }
                                .foregroundColor(aclSecurityStatusColor)
                                if isLoadingSecurityStatus {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text(verbatim: "...")
                                    }
                                    .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                        Toggle("allowed_device_list_current_location_access", isOn: $hasCurrentLocationAccess)
                        Text("allowed_device_list_current_location_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("allowed_device_list_history_access", isOn: $hasHistoryAccess)
                        Text("allowed_device_list_history_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section(header: Text("allowed_device_list_access_controls")) {
                        Button {
                            Task {
                                await activateAllowedDeviceList()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.blue)
                                Text("allowed_device_list_enable_button")

                                if isActivatingAllowedDeviceList {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isActivatingAllowedDeviceList || isSaving)

                        if let activationError {
                            Text(activationError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text("allowed_device_list_disabled_explanation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("new_device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                    .accessibilityIdentifier("add_device_cancel_button")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
                        Task {
                            await saveDevice()
                        }
                    }
                    .disabled(trimmedDeviceName.isEmpty || trimmedDeviceID.isEmpty || isSaving || isActivatingAllowedDeviceList)
                    .accessibilityIdentifier("add_device_confirm_button")
                }
            }
        }
        .accessibilityIdentifier("add_device_form")
        .sheet(isPresented: $isShowingScanner) {
            CodeScannerView(codeTypes: [.qr]) { result in
                switch result {
                case .success(let res):
                    if let scannedDeviceID = DeviceLinkResolver.deviceID(fromCanonicalCode: res.string) {
                        deviceID = scannedDeviceID
                        Haptic.impactMedium()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingScanner = false
                        }
                    } else {
                        deviceID = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isShowingScanner = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                Haptic.notifyWarning()
                                showInvalidQRAlert = true
                            }
                        }
                    }
                case .failure:
                    isShowingScanner = false
                }
            }
        }
        .alert(isPresented: $showInvalidQRAlert) {
            Alert(
                title: Text("invalid_miataru_qr_code"),
                message: Text("invalid_miataru_qr_code_error_text"), //"Der QR-Code muss mit 'miataru://' beginnen."
                dismissButton: .default(Text("ok"))
            )
        }
        .alert(isPresented: $showDuplicateAlert) {
            Alert(
                title: Text(NSLocalizedString("adddevice_duplicate_device_id_title", comment: "Alert title shown when user tries to add a duplicate device.")),
                message: Text(duplicateDeviceIDMessage.isEmpty ? NSLocalizedString("adddevice_duplicate_device_already_exists_message", comment:"Alert text shown when user tries to add a duplicate device.") : duplicateDeviceIDMessage),
                dismissButton: .default(Text("ok"))
            )
        }
        .alert(NSLocalizedString("Error", comment: "The title of an alert that appears when an error occurs."), isPresented: .constant(saveError != nil), presenting: saveError) { _ in
            Button(NSLocalizedString("ok", comment: "OK button")) {
                saveError = nil
            }
        } message: { error in
            Text(error)
        }
        .onAppear {
            // Update deviceID from prefillDeviceID when view appears
            // Check multiple times to handle timing issues
            if let prefill = prefillDeviceID, !prefill.isEmpty {
                deviceID = prefill
            }
            // Also check after a brief delay in case prefill wasn't set yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let prefill = self.prefillDeviceID, !prefill.isEmpty, self.deviceID.isEmpty {
                    self.deviceID = prefill
                }
            }
            scheduleSloganLookup(for: deviceID)
            scheduleSecurityStatusLookup(for: deviceID)
        }
        .onChange(of: prefillDeviceID) { oldValue, newValue in
            // Update deviceID when prefillDeviceID changes
            if let prefill = newValue, !prefill.isEmpty {
                deviceID = prefill
            }
        }
        .onChange(of: deviceID) { _, newValue in
            scheduleSloganLookup(for: newValue)
            scheduleSecurityStatusLookup(for: newValue)
        }
        .onChange(of: settings.allowedDeviceListEnabled) { _, _ in
            scheduleSecurityStatusLookup(for: deviceID)
        }
        .onChange(of: isPresented) { oldValue, newValue in
            // Reset form when sheet is dismissed
            if !newValue {
                deviceName = ""
                deviceID = ""
                deviceColor = Self.randomVividColor()
                hasCurrentLocationAccess = true
                hasHistoryAccess = false
                saveError = nil
                duplicateDeviceIDMessage = ""
                fetchedSlogan = ""
                sloganLookupTask?.cancel()
                sloganLookupTask = nil
                securityStatusLookupTask?.cancel()
                securityStatusLookupTask = nil
                isLoadingSecurityStatus = false
                deviceKeySecurityStatus = .unknown
                aclSecurityStatus = .unknown
                isActivatingAllowedDeviceList = false
                activationError = nil
            } else {
                // When sheet appears, set deviceID from prefill if available
                // Check immediately and also after a delay
                if let prefill = prefillDeviceID, !prefill.isEmpty {
                    deviceID = prefill
                }
                // Also check after a brief delay in case prefill wasn't set yet
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let prefill = self.prefillDeviceID, !prefill.isEmpty {
                        self.deviceID = prefill
                    }
                }
                scheduleSloganLookup(for: deviceID)
                scheduleSecurityStatusLookup(for: deviceID)
            }
        }
    }
    
    @MainActor
    private func saveDevice() async {
        isSaving = true
        saveError = nil

        guard !trimmedDeviceName.isEmpty, !trimmedDeviceID.isEmpty else {
            isSaving = false
            return
        }

        if let existingDevice = store.device(matchingDeviceIDCaseInsensitive: trimmedDeviceID) {
            duplicateDeviceIDMessage = String(
                format: NSLocalizedString("adddevice_duplicate_device_id_case_insensitive_message", comment: "Alert text shown when a device ID matches an existing device ignoring letter case."),
                existingDevice.DeviceID
            )
            Haptic.notifyWarning()
            showDuplicateAlert = true
            isSaving = false
            return
        }
        
        // Capture snapshot for rollback
        let snapshot = AllowedDeviceListManager.shared.captureSnapshot()
        
        let uiColor = UIColor(deviceColor)
        let newDevice = KnownDevice(
            name: trimmedDeviceName,
            deviceID: trimmedDeviceID,
            color: uiColor,
            hasCurrentLocationAccess: hasCurrentLocationAccess,
            hasHistoryAccess: hasHistoryAccess
        )
        
        let success = store.add(device: newDevice)
        if !success {
            duplicateDeviceIDMessage = NSLocalizedString("adddevice_duplicate_device_already_exists_message", comment:"Alert text shown when user tries to add a duplicate device.")
            Haptic.notifyWarning()
            showDuplicateAlert = true
            isSaving = false
            return
        }
        
        // If feature is enabled, sync to server
        if settings.allowedDeviceListEnabled {
            do {
                try await AllowedDeviceListManager.shared.syncAllowedDeviceListIfEnabled(trigger: .add)
                Haptic.notifySuccess()
                IgnoredVisitorDeviceStore.shared.removeIgnored(deviceID: trimmedDeviceID)
                isPresented = false
            } catch {
                // Rollback on sync failure
                AllowedDeviceListManager.shared.restoreSnapshot(snapshot)
                saveError = error.localizedDescription
                Haptic.notifyWarning()
                debugLog("[AddDevice] Sync failed, rolled back: \(error)")
            }
        } else {
            Haptic.notifySuccess()
            IgnoredVisitorDeviceStore.shared.removeIgnored(deviceID: trimmedDeviceID)
            isPresented = false
        }
        
        isSaving = false
    }

    @MainActor
    private func activateAllowedDeviceList() async {
        isActivatingAllowedDeviceList = true
        activationError = nil

        do {
            try await AllowedDeviceListManager.shared.activateAllowedDeviceList()
            await refreshDeviceSecurityStatus(for: deviceID)
        } catch {
            activationError = error.localizedDescription
            debugLog("[AddDevice] Failed to activate allowed device list: \(error)")
        }

        isActivatingAllowedDeviceList = false
    }

    private var deviceKeySecurityStatusText: String {
        switch deviceKeySecurityStatus {
        case .active:
            return NSLocalizedString("allowed_device_list_security_devicekey_active", comment: "DeviceKey security status active")
        case .inactive:
            return NSLocalizedString("allowed_device_list_security_devicekey_inactive", comment: "DeviceKey security status inactive")
        case .unknown:
            return NSLocalizedString("allowed_device_list_security_devicekey_unknown", comment: "DeviceKey security status unknown")
        }
    }

    private var aclSecurityStatusText: String {
        switch aclSecurityStatus {
        case .active:
            return NSLocalizedString("allowed_device_list_security_acl_active", comment: "ACL security status active")
        case .inactive:
            return NSLocalizedString("allowed_device_list_security_acl_inactive", comment: "ACL security status inactive")
        case .unknown:
            return NSLocalizedString("allowed_device_list_security_acl_unknown", comment: "ACL security status unknown")
        }
    }

    private var deviceKeySecurityStatusIcon: String {
        switch deviceKeySecurityStatus {
        case .active:
            return "key.fill"
        case .inactive:
            return "key.slash.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var aclSecurityStatusIcon: String {
        switch aclSecurityStatus {
        case .active:
            return "lock.fill"
        case .inactive:
            return "lock.open.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var deviceKeySecurityStatusColor: Color {
        switch deviceKeySecurityStatus {
        case .active:
            return .green
        case .inactive:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private var aclSecurityStatusColor: Color {
        switch aclSecurityStatus {
        case .active:
            return .green
        case .inactive:
            return .red
        case .unknown:
            return .secondary
        }
    }

    private func adoptSloganAsDeviceNameIfNeeded() {
        let trimmedDeviceName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSlogan = fetchedSlogan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedDeviceName.isEmpty, !trimmedSlogan.isEmpty else { return }
        deviceName = trimmedSlogan
    }

    private var trimmedDeviceName: String {
        deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDeviceID: String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSimilarDeviceName: Bool {
        store.hasCaseInsensitiveNameDuplicate(named: trimmedDeviceName)
    }

    @MainActor
    private func scheduleSecurityStatusLookup(for rawDeviceID: String) {
        securityStatusLookupTask?.cancel()
        securityStatusLookupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await refreshDeviceSecurityStatus(for: rawDeviceID)
        }
    }

    @MainActor
    private func scheduleSloganLookup(for rawDeviceID: String) {
        sloganLookupTask?.cancel()
        sloganLookupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await refreshSlogan(for: rawDeviceID)
        }
    }

    @MainActor
    private func refreshSlogan(for rawDeviceID: String) async {
        let normalizedDeviceID = rawDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedDeviceID.isEmpty else {
            fetchedSlogan = ""
            return
        }

        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""
        guard normalizedDeviceID.count >= 8 else { return }

        guard let serverURL = URL(string: settings.miataruServerURL) else { return }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else { return }

        isLoadingSlogan = true
        defer { isLoadingSlogan = false }

        do {
            _ = try await MiataruAppAPI.fetchAndCacheDeviceSlogan(
                serverURL: serverURL,
                forDeviceID: normalizedDeviceID,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: deviceKey
            )
        } catch {
            debugLog("[AddDevice] Failed loading slogan for \(normalizedDeviceID): \(error)")
        }
        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""
    }

    @MainActor
    private func refreshDeviceSecurityStatus(for rawDeviceID: String) async {
        guard settings.allowedDeviceListEnabled else {
            isLoadingSecurityStatus = false
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            return
        }

        let normalizedDeviceID = rawDeviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedDeviceID.isEmpty else {
            isLoadingSecurityStatus = false
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            return
        }
        guard normalizedDeviceID.count >= 8 else {
            isLoadingSecurityStatus = false
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            return
        }
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            return
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            return
        }

        isLoadingSecurityStatus = true
        defer { isLoadingSecurityStatus = false }

        do {
            let securityStatus = try await MiataruAppAPI.getDeviceSecurityStatus(
                serverURL: serverURL,
                forDeviceID: normalizedDeviceID,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: deviceKey
            )
            deviceKeySecurityStatus = securityStatus.HasDeviceKey ? .active : .inactive
            aclSecurityStatus = securityStatus.IsAllowedDeviceListEnabled ? .active : .inactive
        } catch {
            _ = DeviceKeyAuthHandler.handle(error: error)
            debugLog("[AddDevice] Failed loading security status for \(normalizedDeviceID): \(error)")
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
        }
    }
}

struct iPhone_AddDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        // Beispiel-Daten für die Vorschau
        let store = KnownDeviceStore.shared
        iPhone_AddDeviceView(store: store, isPresented: .constant(true))
    }
}
