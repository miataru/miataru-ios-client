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
                    iPhone_GroupDeviceRowView(
                        device: device,
                        cache: cache,
                        isInGroup: group.containsDevice(device.DeviceID)
                    ) {
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
                            Label("edit_device", systemImage: "pencil")
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
        .navigationTitle("edit_group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Close group details")) {
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

struct iPhone_GroupDeviceRowView: View {
    @ObservedObject var device: KnownDevice
    @ObservedObject var cache: DeviceLocationCacheStore
    let isInGroup: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color(device.DeviceColor ?? UIColor.gray))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.DeviceName)
                    .font(.headline)
                if let subtitle = subtitleText() {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let place = placemarkText() {
                    Text(place)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Image(systemName: isInGroup ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isInGroup ? .green : .gray)
                .font(.title2)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }

    /// Returns the subtitle string for the device row: last seen + distance
    private func subtitleText() -> String? {
        guard let cached = cache.getLocation(for: device.DeviceID) else {
            let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
            let never = NSLocalizedString("device_row_never", comment: "Default value for never seen device")
            let separator = NSLocalizedString("device_row_separator", comment: "Separator between last seen and distance in device row subtitle")
            let distanceLabel = NSLocalizedString("device_row_distance", comment: "Label for the distance to the device in the device list row")
            let unknown = NSLocalizedString("device_row_unknown", comment: "Default value for unknown distance")
            return "\(lastSeen): \(never) \(separator) \(distanceLabel): \(unknown)"
        }
        let now = Date()
        let relativeTime = relativeTimeString(from: cached.timestamp, to: now, unitsStyle: .abbreviated)
        guard let myCached = cache.getLocation(for: thisDeviceIDManager.shared.deviceID) else {
            let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
            return "\(lastSeen): \(relativeTime)"
        }
        let deviceLoc = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        let myLoc = CLLocation(latitude: myCached.latitude, longitude: myCached.longitude)
        let distance = deviceLoc.distance(from: myLoc) // in meters
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        let formattedDistance: String
        if usesMetric {
            let meterUnit = NSLocalizedString("device_row_meter_unit", comment: "Unit for meters in device row distance display")
            let kilometerUnit = NSLocalizedString("device_row_kilometer_unit", comment: "Unit for kilometers in device row distance display")
            if distance < 1000 {
                formattedDistance = String(format: "%.0f %@", distance, meterUnit)
            } else {
                formattedDistance = String(format: "%d %@", Int(round(distance / 1000)), kilometerUnit)
            }
        } else {
            let feetUnit = NSLocalizedString("device_row_feet_unit", comment: "Unit for feet in device row distance display (imperial)")
            let milesUnit = NSLocalizedString("device_row_miles_unit", comment: "Unit for miles in device row distance display (imperial)")
            let distanceInFeet = distance / 0.3048
            let distanceInMiles = distance / 1609.34
            if distanceInFeet > 528 {
                formattedDistance = String(format: "%.2f %@", distanceInMiles, milesUnit)
            } else {
                formattedDistance = String(format: "%.0f %@", distanceInFeet, feetUnit)
            }
        }
        let separator = NSLocalizedString("device_row_separator", comment: "Separator between last seen and distance in device row subtitle")
        let lastSeen = NSLocalizedString("device_row_last_seen", comment: "Label for the last seen time of a device in the device list row")
        let distanceLabel = NSLocalizedString("device_row_distance", comment: "Label for the distance to the device in the device list row")
        return "\(lastSeen): \(relativeTime) \(separator) \(distanceLabel): \(formattedDistance)"
    }

    /// Returns the cached placemark text if available. Does not trigger geocoding.
    private func placemarkText() -> String? {
        if let placemark = cache.getPlacemark(for: device.DeviceID) {
            let parts = [placemark.locality, placemark.country].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: ", ") }
        }
        return nil
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
