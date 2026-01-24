/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_RootView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPad_RootView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            iPad_DevicesView()
                .ignoresSafeArea(.container, edges: .top)
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
                .tag(0)
            iPad_GroupsView()
                .ignoresSafeArea(.container, edges: .top)
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
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
                .tag(3)
        }
        .environmentObject(DeviceGroupStore.shared)
        .environmentObject(RouteInfoState.shared)
        .environmentObject(SettingsManager.shared)
        .bottomAccessory(onTap: nil)
        .ignoresSafeArea(.all)
        .toolbarBackground(.clear, for: .tabBar)
        .toolbarBackground(.clear, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .onChange(of: settings.lastOpenedDeviceID) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
    }
}

#Preview {
    iPad_RootView()
}
