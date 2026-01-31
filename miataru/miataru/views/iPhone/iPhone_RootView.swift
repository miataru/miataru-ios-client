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
    @State private var showDeviceKeySheet = false
    @State private var showDeviceKeyBanner = false
    @State private var deviceKeyBannerMessage = ""
    @State private var deviceKeySheetShowsMismatch = false

    var body: some View {
        TabView(selection: $selectedTab) {
            iPhone_DevicesView()
                .tabItem {
                    Label("devices", systemImage: "iphone.gen3.badge.location")
                }
                .tag(0)
            iPhone_MyDeviceQRCodeView()
                .tabItem {
                    Label("qr", systemImage: "qrcode")
                }
                .tag(1)
            iPhone_SettingsView()
                .tabItem {
                    Label("settings", systemImage: "gear")
                }
                .tag(2)
        }
        .environmentObject(DeviceGroupStore.shared)
        .environmentObject(RouteInfoState.shared)
        .environmentObject(SettingsManager.shared)
        .bottomAccessory(onTap: nil)
        .adaptiveToolbarBackground()
        .sheet(isPresented: $showDeviceKeySheet) {
            iPhone_DeviceKeySheetView(showsMismatchWarning: deviceKeySheetShowsMismatch)
        }
        .onAppear {
            if settings.deviceKeyAuthBlocked {
                deviceKeyBannerMessage = NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDeviceKeyBanner = true
                }
                deviceKeySheetShowsMismatch = true
                showDeviceKeySheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceKeyAuthRequired)) { notification in
            deviceKeyBannerMessage = (notification.userInfo?["message"] as? String)
                ?? NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
            deviceKeySheetShowsMismatch = deviceKeyBannerMessage == NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
            withAnimation(.easeInOut(duration: 0.25)) {
                showDeviceKeyBanner = true
            }
            showDeviceKeySheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceKeyAuthResolved)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                showDeviceKeyBanner = false
            }
            deviceKeySheetShowsMismatch = false
        }
        .overlay(alignment: .top) {
            if showDeviceKeyBanner {
                DeviceKeyBannerView(
                    message: deviceKeyBannerMessage,
                    onSetKey: { showDeviceKeySheet = true },
                    onDismiss: { showDeviceKeyBanner = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
            }
        }
        .onChange(of: settings.lastOpenedDeviceID) { _, newValue in
            if newValue != nil {
                selectedTab = 0
            }
        }
    }
}

private struct DeviceKeyBannerView: View {
    let message: String
    let onSetKey: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.title3)

            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
                .lineLimit(3)

            Button(action: onSetKey) {
                Image(systemName: "key.card")
                    .foregroundColor(.black)
                    .font(.title3)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .accessibilityLabel(Text("device_key_banner_set_button"))

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("device_key_banner_dismiss"))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.85))
        )
        .padding(.horizontal, 12)
    }
}

#Preview {
    iPhone_RootView()
}
