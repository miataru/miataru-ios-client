/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_GroupDetailView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import CoreLocation
import MapKit // For CLLocationCoordinate2D

struct iPad_GroupDetailView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @State private var editingDevice: KnownDevice? = nil
    @State private var previousGroupName: String = ""
    @State private var groupNameField: String = ""
    @State private var originalGroupName: String = ""
    @State private var originalDeviceIds: Set<String> = []
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List {
            Section(header: Text("group_name_section")) {
                HStack {
                    TextField("group_name_textfield", text: $groupNameField)
                        .onTapGesture {
                            previousGroupName = group.groupName
                        }
                        .onSubmit {
                            let trimmed = groupNameField.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.isEmpty {
                                groupNameField = previousGroupName
                            } else {
                                group.groupName = trimmed
                                previousGroupName = trimmed
                            }
                        }
                }
            }
            Section(header: Text("group_member_devices")) {
                ForEach(deviceStore.devices) { device in
                    HStack {
                        DeviceRowView(
                            device: device,
                            cache: cache
                        )
                        Spacer()
                        Image(systemName: group.containsDevice(device.DeviceID) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(group.containsDevice(device.DeviceID) ? .green : .gray)
                            .font(.title2)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        group.toggleDevice(device.DeviceID)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            group.removeDevice(device.DeviceID)
                        } label: {
                            Label("remove_from_group", systemImage: "minus.circle")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingDevice = device
                        } label: {
                            Label("edit_device", systemImage: "pencil").labelStyle(.titleAndIcon)
                        }
                        .tint(.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingDevice = device
                    }
                }
                .onDelete { indices in
                    // Remove devices from group based on indices
                    let devicesToRemove = indices.map { deviceStore.devices[$0] }
                    for device in devicesToRemove {
                        group.removeDevice(device.DeviceID)
                    }
                }
            }
        }
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("cancel", comment: "Cancel button to discard changes and dismiss the view")) {
                    cancelChanges()
                    presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("save", comment: "Save button to save changes and dismiss the view")) {
                    saveChanges()
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(!hasChanges())
            }
        }
        .sheet(item: $editingDevice) { device in
            if let index = deviceStore.devices.firstIndex(where: { $0.id == device.id }) {
                iPhone_EditDeviceView(
                    device: $deviceStore.devices[index],
                    isPresented: Binding(
                        get: { editingDevice != nil },
                        set: { if !$0 { editingDevice = nil } }
                    )
                )
            }
        }
        .onAppear {
            previousGroupName = group.groupName
            groupNameField = group.groupName
            originalGroupName = group.groupName
            originalDeviceIds = Set(group.deviceIDs)
        }
    }
    
    // MARK: - Helper Methods
    
    private func hasChanges() -> Bool {
        let nameChanged = groupNameField.trimmingCharacters(in: .whitespacesAndNewlines) != originalGroupName
        let devicesChanged = Set(group.deviceIDs) != originalDeviceIds
        return nameChanged || devicesChanged
    }
    
    private func saveChanges() {
        let trimmedName = groupNameField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            group.groupName = trimmedName
        }
        // Device changes are already applied through the UI interactions
    }
    
    private func cancelChanges() {
        // Revert group name
        group.groupName = originalGroupName
        groupNameField = originalGroupName
        
        // Revert device selections
        group.deviceIDs = originalDeviceIds
    }
}


#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("device1")
    
    let deviceStore = KnownDeviceStore.shared
    deviceStore.devices = [
        KnownDevice(name: "iPhone 13", deviceID: "device1", color: .red),
        KnownDevice(name: "iPad Pro", deviceID: "device2", color: .green),
        KnownDevice(name: "MacBook Air", deviceID: "device3", color: .blue)
    ]
    
    return NavigationView {
        iPad_GroupDetailView(group: group)
    }
    .environmentObject(deviceStore)
}
