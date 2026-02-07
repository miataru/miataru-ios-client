/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_8_OnboardingAllowedDeviceListView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_8_OnboardingAllowedDeviceListView: View {
    var onFinish: () -> Void = {}
    @State private var showDeviceKeySheet = false
    @State private var isActivating = false
    @State private var activationError: String? = nil
    @StateObject private var settings = SettingsManager.shared
    
    private var hasDeviceKey: Bool {
        guard let key = settings.deviceKey else { return false }
        return !key.isEmpty
    }
    
    private var isFeatureEnabled: Bool {
        settings.allowedDeviceListEnabled
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("allowed_device_list_title")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("devicekey")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            Text("allowed_device_list_intro_text")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if isFeatureEnabled {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("allowed_device_list_enabled_status")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if hasDeviceKey {
                VStack(spacing: 16) {
                    Button("allowed_device_list_enable_button") {
                        Task {
                            await activateFeature()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isActivating)
                    
                    if isActivating {
                        ProgressView()
                            .padding(.top, 8)
                    }
                    
                    if let error = activationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
            } else {
                Button("allowed_device_list_setup_devicekey_button") {
                    showDeviceKeySheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .accessibilityHint(Text("allowed_device_list_devicekey_hint"))
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .sheet(isPresented: $showDeviceKeySheet) {
            iPhone_DeviceKeySheetView(showsMismatchWarning: false)
        }
    }
    
    @MainActor
    private func activateFeature() async {
        isActivating = true
        activationError = nil
        
        do {
            try await AllowedDeviceListManager.shared.activateAllowedDeviceList()
            // Success - UI will update automatically via settings.allowedDeviceListEnabled
        } catch {
            activationError = error.localizedDescription
            debugLog("[Onboarding] Failed to activate allowed device list: \(error)")
        }
        
        isActivating = false
    }
}

#Preview {
    iPhone_8_OnboardingAllowedDeviceListView()
}
