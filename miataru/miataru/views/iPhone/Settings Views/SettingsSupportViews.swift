/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SettingsSupportViews.swift
 * miataru
 *
 * Created by Codex on 14.03.26.
 */

import SwiftUI

struct SettingsDescriptionText: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsWarningText: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AllowedDeviceListSettingsContent: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isActivatingAllowedDeviceList = false
    @State private var activationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.allowedDeviceListEnabled {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("allowed_device_list_enabled_status")
                        .font(.body)
                }

                SettingsDescriptionText("allowed_device_list_enabled_explanation")
            } else {
                Button {
                    Task {
                        await activateAllowedDeviceList()
                    }
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.blue)
                        Text("allowed_device_list_enable_button")

                        if isActivatingAllowedDeviceList {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isActivatingAllowedDeviceList)

                if let error = activationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                SettingsDescriptionText("allowed_device_list_disabled_explanation")
            }
        }
    }

    @MainActor
    private func activateAllowedDeviceList() async {
        isActivatingAllowedDeviceList = true
        activationError = nil

        do {
            try await AllowedDeviceListManager.shared.activateAllowedDeviceList()
        } catch {
            activationError = error.localizedDescription
            debugLog("[Settings] Failed to activate allowed device list: \(error)")
        }

        isActivatingAllowedDeviceList = false
    }
}

struct AllowedDeviceListStatusCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("allowed_device_list_section_title")
                .font(.headline)

            AllowedDeviceListSettingsContent()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityIdentifier("location_status_access_control_card")
    }
}
