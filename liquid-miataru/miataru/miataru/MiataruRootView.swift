//
//  ContentView.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import SwiftUI

struct MiataruRootView: View {
    var body: some View {
        TabView {
            DevicesView()
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
            GroupsView()
                .tabItem {
                    Label("groups", systemImage: "person.3")
                }
            MyDeviceQRCodeView()
                .tabItem {
                    Label("qr", systemImage: "qrcode")
                }
            SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MiataruRootView()
}
