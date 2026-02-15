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
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("device_name")) {
                    TextField("device_name2", text: $tempDeviceName)
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
                Haptic.notifySuccess()
                isPresented = false
            } catch {
                // Rollback on sync failure
                device.hasCurrentLocationAccess = previousHasCurrentLocationAccess
                device.hasHistoryAccess = previousHasHistoryAccess
                AllowedDeviceListManager.shared.restoreSnapshot(snapshot)
                saveError = error.localizedDescription
                Haptic.notifyWarning()
                debugLog("[EditDevice] Sync failed, rolled back: \(error)")
            }
        } else {
            Haptic.notifySuccess()
            isPresented = false
        }
        
        isSaving = false
    }
}

#Preview {
    @Previewable @State var device = KnownDevice(name: "Testdevice", deviceID: "12345", color: .blue)
    @Previewable @State var isPresented = true
    
    iPhone_EditDeviceView(device: $device, isPresented: $isPresented)
}

