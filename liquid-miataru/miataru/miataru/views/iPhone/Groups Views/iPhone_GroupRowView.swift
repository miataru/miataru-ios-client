import SwiftUI

struct iPhone_GroupRowView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(group.groupName)
                    .font(.headline)
                Text("\(group.deviceIDs.count) \(group.deviceIDs.count == 1 ? "device" : "devices")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("device1")
    group.addDevice("device2")
    return iPhone_GroupRowView(group: group)
} 