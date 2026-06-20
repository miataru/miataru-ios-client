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
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(LocalizedStringKey(key), tableName: SettingsTextTable.tableName(for: key))
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsWarningText: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(LocalizedStringKey(key), tableName: SettingsTextTable.tableName(for: key))
            .font(.caption)
            .foregroundColor(.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum SettingsTextTable {
    static func tableName(for key: String) -> String? {
        if key.hasPrefix("allowed_device_list_") || key.hasPrefix("unknown_visitor_") || key.hasPrefix("device_key_") {
            return "Devices"
        }
        if key.hasPrefix("location_sensitivity_") {
            return "MapNavigationHistory"
        }
        if key.hasPrefix("explanation_server_url") {
            return "SettingsDiagnostics"
        }
        if key == "explanation_deactivate_device_lock" {
            return nil
        }
        if key.hasPrefix("activity_type_")
            || key.hasPrefix("background_")
            || key.hasPrefix("frequent_background_")
            || key.hasPrefix("known_visitor_notification_")
            || key.hasPrefix("smart_frequent_")
            || key.hasPrefix("location_tracking_")
            || key.hasPrefix("location_update_outbox_")
            || key.hasPrefix("explanation_") {
            return "LocationTracking"
        }
        return nil
    }
}

struct AlwaysLocationPermissionRequiredNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "location.badge.exclamationmark")
                    .foregroundColor(.orange)
                Text("always_location_permission_required_title", tableName: "LocationTracking")
                    .font(.headline)
            }

            Text("always_location_permission_required_message", tableName: "LocationTracking")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("always_location_permission_required_steps", tableName: "LocationTracking")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("always_location_permission_required_notice")
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
                        Text("frequent_background_location_updates_device_list_notice", tableName: "LocationTracking")
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
        .accessibilityHint(Text("frequent_background_location_updates_device_list_notice_hint", tableName: "LocationTracking"))
    }

    private func expirationText(for date: Date) -> String {
        String(
            format: NSLocalizedString("frequent_background_location_updates_device_list_notice_expires_format", tableName: "LocationTracking", comment: "Expiration line shown in the device list notice for temporary frequent background updates"
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
    @State private var isActivatingAllowedDeviceList = false
    @State private var activationError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.allowedDeviceListEnabled {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("allowed_device_list_enabled_status", tableName: "Devices")
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
                        Text("allowed_device_list_enable_button", tableName: "Devices")

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
            Text("allowed_device_list_section_title", tableName: "Devices")
                .font(.headline)

            AllowedDeviceListSettingsContent()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityIdentifier("location_status_access_control_card")
    }
}
