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
    @EnvironmentObject var tabBarState: TabBarState

    var body: some View {
        ZStack(alignment: .bottom) {
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
            if tabBarState.collapsed {
                Button {
                    tabBarState.collapsed = false
                } label: {
                    Image(systemName: "menubar.rectangle")
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                .padding(.bottom, 8)
            }
        }
        .environmentObject(DeviceGroupStore.shared)
        .tabBarVisibility(tabBarState.collapsed)
        .onAppear {
            if #unavailable(iOS 16.0) {
                UITabBar.appearance().isHidden = tabBarState.collapsed
            }
        }
        .onChange(of: tabBarState.collapsed) { hidden in
            if #unavailable(iOS 16.0) {
                UITabBar.appearance().isHidden = hidden
            }
        }
        .adaptiveToolbarBackground()
    }
}

private extension View {
    @ViewBuilder
    func tabBarVisibility(_ collapsed: Bool) -> some View {
        if #available(iOS 16.0, *) {
            self.toolbar(collapsed ? .hidden : .visible, for: .tabBar)
        } else {
            self
        }
    }
}

#Preview {
    iPhone_RootView()
        .environmentObject(TabBarState())
}
