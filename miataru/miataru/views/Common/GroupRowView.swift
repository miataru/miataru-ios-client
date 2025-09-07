/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * GroupRowView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI

struct GroupRowView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(group.groupName)
                    .font(.headline)
                    .foregroundColor(colorScheme == .light ? .black : .white)
                Text("\(group.deviceIDs.count) \(group.deviceIDs.count == 1 ? NSLocalizedString("device", comment: "GroupRow Device singular") : NSLocalizedString("devices", comment: "GroupRow Device plural"))")
                    .font(.caption)
                    .foregroundColor(colorScheme == .light ? Color.black.opacity(0.6) : Color.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(group.groupName))
        .accessibilityValue(Text(String(format: NSLocalizedString("group_row_num_devices", comment: "Accessibility value expressing how many devices are in the group"), group.deviceIDs.count)))
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("device1")
    group.addDevice("device2")
    return GroupRowView(group: group)
}
