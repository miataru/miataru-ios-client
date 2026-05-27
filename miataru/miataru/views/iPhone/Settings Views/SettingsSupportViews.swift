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

struct FrequentBackgroundLocationUpdatesDeviceListNotice: View {
    let expiresAt: Date?
    let action: () -> Void

    init(expiresAt: Date?, action: @escaping () -> Void) {
        self.expiresAt = expiresAt
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("frequent_background_location_updates_device_list_notice")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        if let expiresAt {
                            Text(expirationText(for: expiresAt))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .padding(.vertical, 6)
        .accessibilityIdentifier("devices_frequent_background_location_updates_notice")
        .accessibilityHint(Text("frequent_background_location_updates_device_list_notice_hint"))
    }

    private func expirationText(for date: Date) -> String {
        String(
            format: NSLocalizedString(
                "frequent_background_location_updates_device_list_notice_expires_format",
                comment: "Expiration line shown in the device list notice for temporary frequent background updates"
            ),
            Self.expirationFormatter.string(from: date)
        )
    }

    private static let expirationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

struct AllowedDeviceListSettingsContent: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.animationsAllowed) private var animationsAllowed
    @State private var isActivatingAllowedDeviceList = false
    @State private var activationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.allowedDeviceListEnabled {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .contentTransition(.symbolEffect(.replace))
                    Text("allowed_device_list_enabled_status")
                        .font(.body)
                }
                .miataruStateTransition(animationsAllowed)

                SettingsDescriptionText("allowed_device_list_enabled_explanation")
                    .miataruStateTransition(animationsAllowed)
            } else {
                Button {
                    Task {
                        await activateAllowedDeviceList()
                    }
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.blue)
                            .contentTransition(.symbolEffect(.replace))
                        Text("allowed_device_list_enable_button")

                        if isActivatingAllowedDeviceList {
                            Spacer()
                            ProgressView()
                                .miataruOverlayTransition(animationsAllowed)
                        }
                    }
                }
                .disabled(isActivatingAllowedDeviceList)
                .miataruAnimated(value: isActivatingAllowedDeviceList, animationsAllowed: animationsAllowed)

                if let error = activationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .miataruStateTransition(animationsAllowed)
                }

                SettingsDescriptionText("allowed_device_list_disabled_explanation")
                    .miataruStateTransition(animationsAllowed)
            }
        }
        .miataruAnimated(value: settings.allowedDeviceListEnabled, animationsAllowed: animationsAllowed)
        .miataruAnimated(value: activationError, animationsAllowed: animationsAllowed)
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
