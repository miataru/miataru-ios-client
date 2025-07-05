import SwiftUI

struct iPhone_GroupDetailView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore()

    var body: some View {
        List {
            ForEach(deviceStore.devices) { device in
                iPhone_GroupDeviceRowView(
                    device: device,
                    isInGroup: group.containsDevice(device.DeviceID)
                ) {
                    group.toggleDevice(device.DeviceID)
                }
            }
        }
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.inline)
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
    let group = DeviceGroup(name: "Test Group", color: .blue)
    group.addDevice("device1")
    
    let deviceStore = KnownDeviceStore()
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