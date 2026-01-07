/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_RootView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_RootView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            iPhone_DevicesView()
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
                .tag(0)
            iPhone_GroupsView()
                .tabItem {
                    Label("groups", systemImage: "person.3")
                }
                .tag(1)
            iPhone_MyDeviceQRCodeView()
                .tabItem {
                    Label("qr", systemImage: "qrcode")
                }
                .tag(2)
            iPhone_SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
                .tag(3)
        }
        .environmentObject(DeviceGroupStore.shared)
        .environmentObject(RouteInfoState.shared)
        .environmentObject(SettingsManager.shared)
        .bottomAccessory(onTap: nil)
        .adaptiveToolbarBackground()
        .onChange(of: settings.lastOpenedDeviceID) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
    }
}

#Preview {
    iPhone_RootView()
}
