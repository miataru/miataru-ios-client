//
//  ContentView.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//
import SwiftUI

struct iPhone_RootView: View {
    var body: some View {
        TabView {
            iPhone_DevicesView()
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
            iPhone_GroupsView()
                .tabItem {
                    Label("groups", systemImage: "person.3")
                }
            iPhone_MyDeviceQRCodeView()
                .tabItem {
                    Label("qr", systemImage: "qrcode")
                }
            iPhone_SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
        }
        .environmentObject(DeviceGroupStore.shared)
    }
}

#Preview {
    iPhone_RootView()
}
