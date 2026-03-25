/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_EditDeviceView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import QRCode
import MiataruAPIClient

struct iPhone_EditDeviceView: View {
    @Binding var device: KnownDevice
    @Binding var isPresented: Bool
    @Environment(\.animationsAllowed) private var animationsAllowed
    @State private var copiedIDFeedback = false
    @State private var tempDeviceName: String = ""
    @State private var tempDeviceColor: Color = .gray
    @State private var showColorPickerSheet = false
    @State private var tempHasCurrentLocationAccess: Bool = true
    @State private var tempHasHistoryAccess: Bool = true
    @State private var isSyncingACL = false
    @State private var aclSyncToken: Int = 0
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var fetchedSlogan: String = ""
    @State private var sloganDraft: String = ""
    @State private var isLoadingSlogan = false
    @State private var isLoadingSecurityStatus = false
    @State private var deviceKeySecurityStatus: DeviceSecurityStatus = .unknown
    @State private var aclSecurityStatus: DeviceSecurityStatus = .unknown
    @State private var isActivatingAllowedDeviceList = false
    @State private var activationError: String? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    private let maxSloganLength = MiataruAppAPI.maxDeviceSloganLength

    private enum DeviceSecurityStatus {
        case active
        case inactive
        case unknown
    }

    private var isCurrentDevice: Bool {
        device.DeviceID == thisDeviceIDManager.shared.deviceID
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $tempDeviceName)

                    if isCurrentDevice {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Info")
                                .foregroundColor(.secondary)

                            TextField("Info", text: $sloganDraft)
                                .onChange(of: sloganDraft) { _, newValue in
                                    let sanitizedDraft = MiataruAppAPI.sanitizeDeviceSloganDraft(newValue, maxLength: maxSloganLength)
                                    if sanitizedDraft != newValue {
                                        sloganDraft = sanitizedDraft
                                    }
                                }

                            HStack {
                                Spacer()
                                if isLoadingSlogan {
                                    ProgressView()
                                        .scaleEffect(0.9)
                                } else {
                                    Text("\(sloganDraft.count)/\(maxSloganLength)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
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
                    }
                }
                Section(header: Text("device_id")) {
                    HStack {
                        Text(device.DeviceID)
                            .foregroundColor(.secondary)
                            .font(.body)
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = device.DeviceID
                            Haptic.impactMedium()
                            copiedIDFeedback = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedIDFeedback = false
                            }
                        }) {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                Section(header: Text("device_color")) {
                    // Button wie in ColorPickerButtonDemo, öffnet das Sheet
                    Button(action: { showColorPickerSheet = true }) {
                        HStack {
                            Circle().fill(tempDeviceColor).frame(width: 24, height: 24)
                            Text(NSLocalizedString("Pick Color", comment: "Button label to open color picker sheet"))
                        }
                    }
                    .sheet(isPresented: $showColorPickerSheet) {
                        ColorPickerSheet(selectedColor: $tempDeviceColor)
                            .presentationDetents([.medium])
                    }
                }
                // Hide ACL controls for this device itself – ACLs are only relevant for *other* devices.
                if !settings.allowedDeviceListEnabled {
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
                } else if device.DeviceID != thisDeviceIDManager.shared.deviceID {
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
                        Toggle("allowed_device_list_current_location_access", isOn: Binding(
                            get: { tempHasCurrentLocationAccess },
                            set: { newValue in
                                let previousCurrentLocationAccess = tempHasCurrentLocationAccess
                                let previousHistoryAccess = tempHasHistoryAccess
                                let historyWasForcedOff = !newValue && tempHasHistoryAccess
                                guard previousCurrentLocationAccess != newValue || historyWasForcedOff else { return }

                                tempHasCurrentLocationAccess = newValue
                                // If current location access is disabled, also disable history access
                                if !newValue {
                                    tempHasHistoryAccess = false
                                }
                                device.hasCurrentLocationAccess = tempHasCurrentLocationAccess
                                device.hasHistoryAccess = tempHasHistoryAccess
                                syncACLImmediately(
                                    previousCurrentLocationAccess: previousCurrentLocationAccess,
                                    previousHistoryAccess: previousHistoryAccess
                                )
                            }
                        ))
                        .disabled(isSyncingACL)
                        Text("allowed_device_list_current_location_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("allowed_device_list_history_access", isOn: Binding(
                            get: { tempHasHistoryAccess },
                            set: { newValue in
                                let previousCurrentLocationAccess = tempHasCurrentLocationAccess
                                let previousHistoryAccess = tempHasHistoryAccess
                                guard previousHistoryAccess != newValue else { return }

                                tempHasHistoryAccess = newValue
                                device.hasHistoryAccess = tempHasHistoryAccess
                                syncACLImmediately(
                                    previousCurrentLocationAccess: previousCurrentLocationAccess,
                                    previousHistoryAccess: previousHistoryAccess
                                )
                            }
                        ))
                            .disabled(!tempHasCurrentLocationAccess || isSyncingACL)
                        Text("allowed_device_list_history_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if isSyncingACL {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.9)
                                Spacer()
                            }
                        }
                    }
                }
                Section(header: Text("device_qr_code")) {
                    let qrContent = QRCodeShape(
                        data: ("miataru://" + device.DeviceID).data(using: .utf8) ?? Data(),
                        errorCorrection: .low
                    )
                    HStack {
                        Spacer()
                        ZStack {
                            Color(UIColor.systemBackground)
                            qrContent
                                .components(.eyeOuter)
                                .fill(Color.primary)
                            qrContent
                                .components(.eyePupil)
                                .fill(Color.primary)
                            qrContent
                                .components(.onPixels)
                                .fill(Color.primary)
                        }
                        .frame(width: 200, height: 200)
                        .padding()
                        Spacer()
                    }
                }
            }
            .navigationTitle("edit_device")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("close_button_label") {
                        Task {
                            await saveDevice()
                        }
                    }
                    .disabled(isSaving || isSyncingACL || isActivatingAllowedDeviceList)
                }
            }
            .onAppear {
                tempDeviceName = device.DeviceName
                if #available(iOS 14.0, *) {
                    tempDeviceColor = Color(device.DeviceColor ?? UIColor.gray)
                }
                tempHasCurrentLocationAccess = device.hasCurrentLocationAccess
                tempHasHistoryAccess = device.hasHistoryAccess
                sloganDraft = sloganCache.slogan(for: device.DeviceID) ?? ""
                Task {
                    await refreshSlogan()
                }
                Task {
                    await refreshDeviceSecurityStatus()
                }
            }
            .onChange(of: settings.allowedDeviceListEnabled) { _, _ in
                Task {
                    await refreshDeviceSecurityStatus()
                }
            }
            .alert(NSLocalizedString("Error", comment: "The title of an alert that appears when an error occurs."), isPresented: .constant(saveError != nil), presenting: saveError) { _ in
                Button(NSLocalizedString("ok", comment: "OK button")) {
                    saveError = nil
                }
            } message: { error in
                Text(error)
            }
        }
        .overlay(
            Group {
                if copiedIDFeedback {
                    Text("device_id_copied_to_clipboard")
                        .padding(12)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .transition(animationsAllowed ? .opacity : .identity)
                        .zIndex(1)
                }
            }, alignment: .top
        )
        .animation(animationsAllowed ? .easeInOut : nil, value: copiedIDFeedback)
    }
    
    @MainActor
    private func saveDevice() async {
        isSaving = true
        saveError = nil

        // Update device properties
        let trimmedName = tempDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            device.DeviceName = trimmedName
        }
        if #available(iOS 14.0, *) {
            device.DeviceColor = UIColor(tempDeviceColor)
        }
        device.hasCurrentLocationAccess = tempHasCurrentLocationAccess
        device.hasHistoryAccess = tempHasHistoryAccess

        if isCurrentDevice {
            do {
                try await saveOwnDeviceSloganIfNeeded()
            } catch {
                if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                    saveError = authMessage
                } else if let editDeviceError = error as? EditDeviceSloganError,
                          let message = editDeviceError.errorDescription {
                    saveError = message
                } else {
                    saveError = NSLocalizedString(
                        "device_slogan_set_failed_try_again_later",
                        comment: "Fallback error when setting the device slogan failed."
                    )
                }
                Haptic.notifyWarning()
                isSaving = false
                return
            }
        }

        Haptic.notifySuccess()
        isPresented = false
        isSaving = false
    }

    @MainActor
    private func activateAllowedDeviceList() async {
        isActivatingAllowedDeviceList = true
        activationError = nil

        do {
            try await AllowedDeviceListManager.shared.activateAllowedDeviceList()
            await refreshDeviceSecurityStatus()
        } catch {
            activationError = error.localizedDescription
            debugLog("[EditDevice] Failed to activate allowed device list: \(error)")
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

    @MainActor
    private func syncACLImmediately(previousCurrentLocationAccess: Bool, previousHistoryAccess: Bool) {
        guard settings.allowedDeviceListEnabled, !isCurrentDevice else { return }

        let token = aclSyncToken + 1
        aclSyncToken = token
        isSyncingACL = true
        let deviceID = device.DeviceID
        let hasCurrentLocationAccess = tempHasCurrentLocationAccess
        let hasHistoryAccess = tempHasHistoryAccess

        Task {
            do {
                try await AllowedDeviceListManager.shared.upsertDeviceACL(
                    deviceID: deviceID,
                    hasCurrentLocationAccess: hasCurrentLocationAccess,
                    hasHistoryAccess: hasHistoryAccess
                )
                await MainActor.run {
                    guard token == aclSyncToken else { return }
                    isSyncingACL = false
                }
            } catch {
                await MainActor.run {
                    guard token == aclSyncToken else { return }
                    tempHasCurrentLocationAccess = previousCurrentLocationAccess
                    tempHasHistoryAccess = previousHistoryAccess
                    device.hasCurrentLocationAccess = previousCurrentLocationAccess
                    device.hasHistoryAccess = previousHistoryAccess
                    if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                        saveError = authMessage
                    } else {
                        saveError = error.localizedDescription
                    }
                    isSyncingACL = false
                    Haptic.notifyWarning()
                }
            }
        }
    }

    @MainActor
    private func refreshSlogan() async {
        let normalizedDeviceID = device.DeviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedDeviceID.isEmpty else {
            fetchedSlogan = ""
            return
        }

        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""

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
            debugLog("[EditDevice] Failed loading slogan for \(normalizedDeviceID): \(error)")
        }
        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""
        if isCurrentDevice {
            sloganDraft = fetchedSlogan
        }
    }

    @MainActor
    private func refreshDeviceSecurityStatus() async {
        guard settings.allowedDeviceListEnabled, !isCurrentDevice else {
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
            isLoadingSecurityStatus = false
            return
        }

        let normalizedDeviceID = device.DeviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedDeviceID.isEmpty else {
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
            deviceKeySecurityStatus = .unknown
            aclSecurityStatus = .unknown
        }
    }

    @MainActor
    private func saveOwnDeviceSloganIfNeeded() async throws {
        guard isCurrentDevice else { return }

        let normalizedSlogan = normalizeSlogan(sloganDraft)
        let currentKnownSlogan = normalizeSlogan(fetchedSlogan)
        guard normalizedSlogan != currentKnownSlogan else { return }

        guard let serverURL = URL(string: settings.miataruServerURL) else {
            throw EditDeviceSloganError.invalidServerURL
        }
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            throw EditDeviceSloganError.missingDeviceKey
        }

        _ = try await MiataruAppAPI.setDeviceSlogan(
            serverURL: serverURL,
            deviceID: device.DeviceID,
            deviceKey: deviceKey,
            slogan: normalizedSlogan
        )
        sloganCache.cacheSlogan(normalizedSlogan, for: device.DeviceID)
        sloganCache.markFreshNow(for: device.DeviceID)
        fetchedSlogan = normalizedSlogan
        sloganDraft = normalizedSlogan
    }

    private func normalizeSlogan(_ slogan: String) -> String {
        MiataruAppAPI.cleanseDeviceSlogan(slogan, maxLength: maxSloganLength)
    }

    private enum EditDeviceSloganError: LocalizedError {
        case invalidServerURL
        case missingDeviceKey

        var errorDescription: String? {
            switch self {
            case .invalidServerURL:
                return NSLocalizedString("device_key_error_invalid_server", comment: "Error when server URL is invalid")
            case .missingDeviceKey:
                return NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
            }
        }
    }
}

#Preview {
    @Previewable @State var device = KnownDevice(name: "Testdevice", deviceID: "12345", color: .blue)
    @Previewable @State var isPresented = true
    
    iPhone_EditDeviceView(device: $device, isPresented: $isPresented)
}
