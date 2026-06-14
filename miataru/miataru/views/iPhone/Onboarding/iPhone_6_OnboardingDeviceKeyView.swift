/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_6_OnboardingDeviceKeyView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 31.01.26.
 */

import SwiftUI

struct iPhone_6_OnboardingDeviceKeyView: View {
    var onFinish: () -> Void = {}
    @State private var showDeviceKeySheet = false
    @State private var dismissDeviceKeySheetTask: Task<Void, Never>? = nil
    @StateObject private var settings = SettingsManager.shared
    
    private var hasDeviceKey: Bool {
        guard let key = settings.deviceKey else { return false }
        return !key.isEmpty
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("device_key_title", tableName: "Devices")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("devicekey")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            Text("device_key_intro_text", tableName: "Devices")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(String(localized: hasDeviceKey ? "device_key_banner_configure_button" : "device_key_banner_set_button", table: "Devices")) {
                showDeviceKeySheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(hasDeviceKey ? .green : .blue)
            .accessibilityHint(Text("device_key_button_hint", tableName: "Devices"))
            .padding(.horizontal)
            .sheet(
                isPresented: $showDeviceKeySheet,
                onDismiss: cancelPendingDeviceKeySheetDismiss
            ) {
                iPhone_DeviceKeySheetView(
                    showsMismatchWarning: false,
                    onDeviceKeySuccess: scheduleDeviceKeySheetDismiss
                )
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .onDisappear(perform: cancelPendingDeviceKeySheetDismiss)
    }

    @MainActor
    private func scheduleDeviceKeySheetDismiss() {
        dismissDeviceKeySheetTask?.cancel()
        dismissDeviceKeySheetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            showDeviceKeySheet = false
            dismissDeviceKeySheetTask = nil
        }
    }

    private func cancelPendingDeviceKeySheetDismiss() {
        dismissDeviceKeySheetTask?.cancel()
        dismissDeviceKeySheetTask = nil
    }
}

#Preview {
    iPhone_6_OnboardingDeviceKeyView()
}
