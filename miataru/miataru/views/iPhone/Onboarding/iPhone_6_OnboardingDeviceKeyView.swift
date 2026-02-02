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
    @StateObject private var settings = SettingsManager.shared
    
    private var hasDeviceKey: Bool {
        guard let key = settings.deviceKey else { return false }
        return !key.isEmpty
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("device_key_title")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("devicekey")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            Text("device_key_intro_text")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(hasDeviceKey ? "device_key_banner_configure_button" : "device_key_banner_set_button") {
                showDeviceKeySheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(hasDeviceKey ? .green : .blue)
            .accessibilityHint(Text("device_key_button_hint"))
            .padding(.horizontal)
            .sheet(isPresented: $showDeviceKeySheet) {
                iPhone_DeviceKeySheetView(showsMismatchWarning: false)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    iPhone_6_OnboardingDeviceKeyView()
}
