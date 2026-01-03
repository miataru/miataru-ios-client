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
    var body: some View {
        TabView {
            iPad_DevicesView()
                .ignoresSafeArea(.container, edges: .top)
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
            iPad_GroupsView()
                .ignoresSafeArea(.container, edges: .top)
                .tabItem {
                    Label("groups", systemImage: "person.3")
                }
            iPhone_MyDeviceQRCodeView()
                .tabItem {
                    Label("qr", systemImage: "qrcode")
                }
            iPhone_SettingsView()
                .navigationViewStyle(.stack)
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
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
    }
}

#Preview {
    iPad_RootView()
}
