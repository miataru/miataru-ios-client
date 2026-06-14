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
    @ObservedObject private var appNavigation = AppNavigationCoordinator.shared
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
    @State private var selectedTab = 0
    @State private var showDeviceKeySheet = false
    @State private var showDeviceKeyBanner = false
    @State private var deviceKeyBannerMessage = ""
    @State private var deviceKeySheetShowsMismatch = false

    var body: some View {
        TabView(selection: $selectedTab) {
            iPhone_DevicesView()
                .accessibilityIdentifier("screen_devices")
                .tabItem {
                    Label(String(localized: "devices", table: "Devices"), systemImage: "iphone.gen3.badge.location")
                }
                .tag(0)
            iPhone_MyDeviceQRCodeView()
                .accessibilityIdentifier("screen_qr")
                .tabItem {
                    Label(String(localized: "qr", table: "OnboardingQR"), systemImage: "qrcode")
                }
                .tag(1)
            iPhone_SettingsView()
                .accessibilityIdentifier("screen_settings")
                .tabItem {
                    Label(String(localized: "settings", table: "SettingsDiagnostics"), systemImage: "gear")
                }
                .tag(2)
        }
        .accessibilityIdentifier("root_tab_view")
        .environmentObject(DeviceGroupStore.shared)
        .environmentObject(RouteInfoState.shared)
        .environmentObject(SettingsManager.shared)
        .bottomAccessory(onTap: nil)
        .adaptiveToolbarBackground()
        .sheet(isPresented: $showDeviceKeySheet) {
            iPhone_DeviceKeySheetView(showsMismatchWarning: deviceKeySheetShowsMismatch)
        }
        .onAppear {
            if let initialTab = UserDefaults.standard.object(forKey: "ui_test_initial_tab") as? Int,
               (0...2).contains(initialTab) {
                selectedTab = initialTab
            }
            applyRootNavigationDestination(appNavigation.rootDestination)
            if !isUITesting, settings.deviceKeyAuthBlocked {
                deviceKeyBannerMessage = NSLocalizedString("device_key_auth_runtime_error_message", tableName: "Devices", comment: "Runtime auth error when stored DeviceKey is missing or invalid")
                withAnimation(.easeInOut(duration: 0.25)) {
                    showDeviceKeyBanner = true
                }
                deviceKeySheetShowsMismatch = false
                showDeviceKeySheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceKeyAuthRequired)) { notification in
            guard !isUITesting else { return }
            deviceKeyBannerMessage = (notification.userInfo?["message"] as? String)
                ?? NSLocalizedString("device_key_auth_runtime_error_message", tableName: "Devices", comment: "Runtime auth error when stored DeviceKey is missing or invalid")
            deviceKeySheetShowsMismatch = deviceKeyBannerMessage == NSLocalizedString("device_key_auth_mismatch_message", tableName: "Devices", comment: "Message when stored DeviceKey does not match server")
            withAnimation(.easeInOut(duration: 0.25)) {
                showDeviceKeyBanner = true
            }
            showDeviceKeySheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceKeyAuthResolved)) { _ in
            guard !isUITesting else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                showDeviceKeyBanner = false
            }
            deviceKeySheetShowsMismatch = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceIdentityDidReset)) { _ in
            guard !isUITesting else { return }
            selectedTab = 1
        }
        .onReceive(appNavigation.$rootDestination.compactMap { $0 }) { destination in
            applyRootNavigationDestination(destination)
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
            if !isUITesting, newValue != nil {
                selectedTab = 0
            }
        }
    }

    private func applyRootNavigationDestination(_ destination: AppRootNavigationDestination?) {
        switch destination {
        case .devices:
            selectedTab = 0
            appNavigation.consumeRootDestination(.devices)
        case .settings:
            selectedTab = 2
        case .none:
            break
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
            .accessibilityLabel(Text("device_key_banner_set_button", tableName: "Devices"))

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(0.9))
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(Text("device_key_banner_dismiss", tableName: "Devices"))
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
