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
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var fetchedSlogan: String = ""
    @State private var sloganDraft: String = ""
    @State private var isLoadingSlogan = false
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    private let maxSloganLength = 40

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
                                    if newValue.count > maxSloganLength {
                                        sloganDraft = String(newValue.prefix(maxSloganLength))
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
                if settings.allowedDeviceListEnabled && device.DeviceID != thisDeviceIDManager.shared.deviceID {
                    Section(header: Text("allowed_device_list_access_controls")) {
                        Toggle("allowed_device_list_current_location_access", isOn: Binding(
                            get: { tempHasCurrentLocationAccess },
                            set: { newValue in
                                tempHasCurrentLocationAccess = newValue
                                // If current location access is disabled, also disable history access
                                if !newValue {
                                    tempHasHistoryAccess = false
                                }
                            }
                        ))
                        Text("allowed_device_list_current_location_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("allowed_device_list_history_access", isOn: $tempHasHistoryAccess)
                            .disabled(!tempHasCurrentLocationAccess)
                        Text("allowed_device_list_history_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        Task {
                            await saveDevice()
                        }
                    }
                    .disabled(tempDeviceName.isEmpty || isSaving)
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
        
        // Capture snapshot for rollback
        let snapshot = AllowedDeviceListManager.shared.captureSnapshot()
        
        // Store previous ACL values for rollback
        let previousHasCurrentLocationAccess = device.hasCurrentLocationAccess
        let previousHasHistoryAccess = device.hasHistoryAccess
        
        // Update device properties
        device.DeviceName = tempDeviceName
        if #available(iOS 14.0, *) {
            device.DeviceColor = UIColor(tempDeviceColor)
        }
        device.hasCurrentLocationAccess = tempHasCurrentLocationAccess
        device.hasHistoryAccess = tempHasHistoryAccess
        
        debugLog("[EditDevice] Updated device \(device.DeviceID): current=\(tempHasCurrentLocationAccess), history=\(tempHasHistoryAccess)")
        debugLog("[EditDevice] Device object values after update: current=\(device.hasCurrentLocationAccess), history=\(device.hasHistoryAccess)")
        
        // Ensure property changes are propagated
        await Task.yield()
        
        // If feature is enabled, sync to server
        if settings.allowedDeviceListEnabled {
            do {
                // Verify device values before syncing
                debugLog("[EditDevice] Before sync - device \(device.DeviceID): current=\(device.hasCurrentLocationAccess), history=\(device.hasHistoryAccess)")
                try await AllowedDeviceListManager.shared.syncAllowedDeviceListIfEnabled(trigger: .edit)
            } catch {
                // Rollback on sync failure
                device.hasCurrentLocationAccess = previousHasCurrentLocationAccess
                device.hasHistoryAccess = previousHasHistoryAccess
                AllowedDeviceListManager.shared.restoreSnapshot(snapshot)
                saveError = error.localizedDescription
                Haptic.notifyWarning()
                debugLog("[EditDevice] Sync failed, rolled back: \(error)")
                isSaving = false
                return
            }
        }

        if isCurrentDevice {
            do {
                try await saveOwnDeviceSloganIfNeeded()
            } catch {
                if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                    saveError = authMessage
                } else {
                    saveError = error.localizedDescription
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

        await sloganCache.refreshSloganIfStale(
            for: normalizedDeviceID,
            serverURL: serverURL,
            requestingDeviceID: thisDeviceIDManager.shared.deviceID,
            requestingDeviceKey: deviceKey,
            minimumRefreshInterval: 300,
            force: true
        )
        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""
        if isCurrentDevice {
            sloganDraft = fetchedSlogan
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

        _ = try await MiataruAPIClient.setDeviceSlogan(
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
        String(slogan.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSloganLength))
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
