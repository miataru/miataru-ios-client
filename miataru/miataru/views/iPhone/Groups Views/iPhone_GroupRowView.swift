/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_GroupRowView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_GroupRowView: View {
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
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("device1")
    group.addDevice("device2")
    return iPhone_GroupRowView(group: group)
} 
