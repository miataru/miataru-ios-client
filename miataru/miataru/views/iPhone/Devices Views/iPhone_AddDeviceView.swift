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
    @State private var deviceName: String = ""
    @State private var deviceID: String = ""
    @State private var deviceColor: Color = Self.randomVividColor()
    @State private var isShowingScanner = false
    @State private var showInvalidQRAlert = false
    @State private var showDuplicateAlert = false
    @State private var showColorPickerSheet = false
    @State private var hasCurrentLocationAccess: Bool = true
    @State private var hasHistoryAccess: Bool = false
    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var fetchedSlogan: String = ""
    @State private var isLoadingSlogan = false
    @State private var sloganLookupTask: Task<Void, Never>? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var sloganCache = DeviceSloganCacheStore.shared
    
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
    
    init(store: KnownDeviceStore, isPresented: Binding<Bool>, prefillDeviceID: String? = nil) {
        self.store = store
        self._isPresented = isPresented
        self.prefillDeviceID = prefillDeviceID
        if let prefill = prefillDeviceID {
            _deviceID = State(initialValue: prefill)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $deviceName)

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
                Section(header: Text("device_id")) {
                    Button(action: { isShowingScanner = true }) {
                        Label("scan_qr_code", systemImage: "qrcode.viewfinder")
                    }
                    TextField("device_id2", text: $deviceID)
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
                        Toggle("allowed_device_list_current_location_access", isOn: $hasCurrentLocationAccess)
                        Text("allowed_device_list_current_location_access_description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("allowed_device_list_history_access", isOn: $hasHistoryAccess)
                        Text("allowed_device_list_history_access_description")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
                        Task {
                            await saveDevice()
                        }
                    }
                    .disabled(deviceName.isEmpty || deviceID.isEmpty || isSaving)
                }
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            CodeScannerView(codeTypes: [.qr]) { result in
                switch result {
                case .success(let res):
                    let prefix = "miataru://"
                    if res.string.hasPrefix(prefix) {
                        deviceID = String(res.string.dropFirst(prefix.count)).uppercased()
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
                message: Text(NSLocalizedString("adddevice_duplicate_device_already_exists_message", comment:"Alert text shown when user tries to add a duplicate device.")),
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
        }
        .onChange(of: prefillDeviceID) { oldValue, newValue in
            // Update deviceID when prefillDeviceID changes
            if let prefill = newValue, !prefill.isEmpty {
                deviceID = prefill
            }
        }
        .onChange(of: deviceID) { _, newValue in
            scheduleSloganLookup(for: newValue)
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
                fetchedSlogan = ""
                sloganLookupTask?.cancel()
                sloganLookupTask = nil
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
            }
        }
    }
    
    @MainActor
    private func saveDevice() async {
        isSaving = true
        saveError = nil
        
        // Capture snapshot for rollback
        let snapshot = AllowedDeviceListManager.shared.captureSnapshot()
        
        let uiColor = UIColor(deviceColor)
        let newDevice = KnownDevice(
            name: deviceName,
            deviceID: deviceID,
            color: uiColor,
            hasCurrentLocationAccess: hasCurrentLocationAccess,
            hasHistoryAccess: hasHistoryAccess
        )
        
        let success = store.add(device: newDevice)
        if !success {
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
                IgnoredVisitorDeviceStore.shared.removeIgnored(deviceID: deviceID)
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
            IgnoredVisitorDeviceStore.shared.removeIgnored(deviceID: deviceID)
            isPresented = false
        }
        
        isSaving = false
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

        await sloganCache.refreshSloganIfStale(
            for: normalizedDeviceID,
            serverURL: serverURL,
            requestingDeviceID: thisDeviceIDManager.shared.deviceID,
            requestingDeviceKey: deviceKey,
            minimumRefreshInterval: 300,
            force: true
        )
        fetchedSlogan = sloganCache.slogan(for: normalizedDeviceID) ?? ""
    }
}

struct iPhone_AddDeviceView_Previews: PreviewProvider {
    static var previews: some View {
        // Beispiel-Daten für die Vorschau
        let store = KnownDeviceStore.shared
        iPhone_AddDeviceView(store: store, isPresented: .constant(true))
    }
}
