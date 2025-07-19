//
//  ContentView.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

struct iPad_RootView: View {
    @State private var selection: SidebarItem? = .devices
    @State private var selectedDeviceID: String? = nil
    @State private var selectedGroupID: String? = nil
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(header: Text("Devices")) {
                    ForEach(KnownDeviceStore.shared.devices) { device in
                        NavigationLink(value: SidebarItem.device(device.DeviceID)) {
                            Label(device.name, systemImage: "iphone.gen3.badge.location")
                        }
                    }
                }
                Section(header: Text("Groups")) {
                    ForEach(DeviceGroupStore.shared.groups) { group in
                        NavigationLink(value: SidebarItem.group(group.id)) {
                            Label(group.name, systemImage: "person.3")
                        }
                    }
                }
                Section(header: Text("Other")) {
                    NavigationLink(value: SidebarItem.qr) {
                        Label("QR Code", systemImage: "qrcode")
                    }
                    NavigationLink(value: SidebarItem.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Miataru")
        } detail: {
            switch selection ?? .devices {
            case .devices:
                iPhone_DevicesView()
            case .device(let deviceID):
                iPhone_DeviceMapView(deviceID: deviceID)
            case .groups:
                iPhone_GroupsView()
            case .group(let groupID):
                if let group = DeviceGroupStore.shared.groups.first(where: { $0.id == groupID }) {
                    iPhone_GroupMapView(group: group)
                } else {
                    Text("Group not found")
                }
            case .qr:
                iPhone_MyDeviceQRCodeView()
            case .settings:
                iPhone_SettingsView()
            }
        }
        .environmentObject(DeviceGroupStore.shared)
    }
}

enum SidebarItem: Hashable {
    case devices
    case device(String)
    case groups
    case group(String)
    case qr
    case settings
}

#Preview {
    iPad_RootView()
}
