/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_9_OnboardingUnknownVisitorAlertsView.swift
 * miataru
 *
 * Created by Codex on 09.03.26.
 */

import SwiftUI

struct iPhone_9_OnboardingUnknownVisitorAlertsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var isUpdatingUnknownVisitorAlerts = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("onboarding_unknown_visitor_alerts_title", tableName: "OnboardingQR")
                .font(.largeTitle)
                .fontWeight(.bold)

            Image("yourlocationyourcontrol")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)

            Text("onboarding_unknown_visitor_alerts_intro_text", tableName: "OnboardingQR")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("onboarding_unknown_visitor_alerts_example_title", tableName: "OnboardingQR")
                    .font(.headline)
                Text("onboarding_unknown_visitor_alerts_example_message", tableName: "OnboardingQR")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)

            Toggle(String(localized: "unknown_visitor_alerts_toggle", table: "Devices"),
                isOn: Binding(
                    get: { settings.unknownVisitorAlertsEnabled },
                    set: { newValue in
                        updateUnknownVisitorAlerts(newValue)
                    }
                )
            )
            .disabled(isUpdatingUnknownVisitorAlerts)
            .padding(.horizontal)

            Text("explanation_unknown_visitor_alerts_toggle", tableName: "LocationTracking")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if settings.unknownVisitorAlertsPermissionDenied {
                VStack(spacing: 8) {
                    Text("unknown_visitor_alerts_permission_denied_message", tableName: "Devices")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button(String(localized: "unknown_visitor_alerts_open_settings_button", table: "Devices")) {
                        LocationManager.shared.openAppSettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func updateUnknownVisitorAlerts(_ newValue: Bool) {
        isUpdatingUnknownVisitorAlerts = true
        Task { @MainActor in
            await settings.setUnknownVisitorAlertsEnabledFromUser(newValue)
            isUpdatingUnknownVisitorAlerts = false
        }
    }
}

#Preview {
    iPhone_9_OnboardingUnknownVisitorAlertsView()
}
