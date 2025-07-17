import SwiftUI

struct iPhone_GroupDetailView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared
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
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("done") {
                    presentationMode.wrappedValue.dismiss()
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
    let isInGroup: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Circle()
                .fill(Color(device.DeviceColor ?? UIColor.gray))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading) {
                Text(device.DeviceName)
                    .font(.headline)
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