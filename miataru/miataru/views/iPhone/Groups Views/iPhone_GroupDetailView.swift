/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_GroupDetailView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import CoreLocation
import MapKit // For CLLocationCoordinate2D

struct iPhone_GroupDetailView: View {
    @ObservedObject var group: DeviceGroup
    var showsDoneButton: Bool = true
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @State private var editingDevice: KnownDevice? = nil
    @State private var previousGroupName: String = ""
    @State private var groupNameField: String = ""
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        List {
            Section(header: Text("group_name_section", tableName: "Groups")) {
                HStack {
                    TextField(String(localized: "group_name_textfield", table: "Groups"), text: $groupNameField)
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
            Section(header: Text("group_member_devices", tableName: "Groups")) {
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
                            Label(String(localized: "remove_from_group", table: "Groups"), systemImage: "minus.circle")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            editingDevice = device
                        } label: {
                            Label(String(localized: "edit_device", table: "Devices"), systemImage: "pencil")
                        }
                        .tint(.blue)
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
        .navigationTitle(String(localized: "edit_group", table: "Groups"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", tableName: "Common", comment: "Close group details")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            // ToolbarItem(placement: .navigationBarTrailing) {
            //     NavigationLink(destination: iPhone_GroupMapView(group: group)) {
            //         Text("show")
            //     }
            // }
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
        }
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
        iPhone_GroupDetailView(group: group)
    }
    .environmentObject(deviceStore)
} 
