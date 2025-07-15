import SwiftUI

struct iPhone_GroupRowView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(group.groupName)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(group.deviceIDs.count) \(group.deviceIDs.count == 1 ? NSLocalizedString("device", comment: "GroupRow Device singular") : NSLocalizedString("devices", comment: "GroupRow Device plural"))")
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
