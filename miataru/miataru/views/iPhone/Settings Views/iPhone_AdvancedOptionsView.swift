/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_AdvancedOptionsView.swift
 * miataru
 *
 * Created by Codex on 14.03.26.
 */

import SwiftUI

struct iPhone_AdvancedOptionsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @State private var isRequestingSmartFrequentNotificationPermission = false
    @State private var smartFrequentNotificationPermissionDenied = false

    var body: some View {
        Form {
            if trackingPermissionVisibility.showsAlwaysPermissionNotice {
                Section {
                    AlwaysLocationPermissionRequiredNotice()
                }
            }

            if trackingPermissionVisibility.showsTrackingDependentSettings {
                Section(header: Text("activity_type_accuracy_settings_title")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("activity_type_tracking_accuracy_title")
                            .font(.headline)
                        Picker("", selection: $settings.locationActivityType) {
                            Text("activity_type_other").tag(0)
                            Text("activity_type_fitness").tag(2)
                            Text("activity_type_automotive").tag(1)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("activity_type_accuracy_explanation")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("location_sensitivity_title")
                            .font(.headline)
                        Picker("", selection: $settings.locationSensitivityLevel) {
                            Text("location_tracking_update_sensitivity_very_sensitive_short").tag(1)
                            Text("location_tracking_update_sensitivity_default_short").tag(2)
                            Text("location_tracking_update_sensitivity_balanced_short").tag(3)
                            Text("location_tracking_update_sensitivity_battery_saver_short").tag(4)
                            Text("location_tracking_update_sensitivity_minimal_short").tag(5)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("location_sensitivity_explanation")
                }

                Section(header: Text("background_location_updates_section_title")) {
                    Toggle("smart_frequent_background_location_updates_title", isOn: $settings.smartFrequentBackgroundLocationUpdatesEnabled)
                        .accessibilityIdentifier("settings_smart_frequent_background_location_updates_toggle")
                        .disabled(settings.frequentBackgroundLocationUpdatesEnabled)
                    SettingsDescriptionText("smart_frequent_background_location_updates_explanation")
                    if settings.frequentBackgroundLocationUpdatesEnabled {
                        SettingsDescriptionText("smart_frequent_background_locked_by_manual_explanation")
                    }

                    if settings.smartFrequentBackgroundLocationUpdatesEnabled {
                        Picker("smart_frequent_background_speed_threshold_title", selection: $settings.smartFrequentBackgroundSpeedThresholdKmh) {
                            Text("2kmh").tag(2)
                            Text("5kmh").tag(5)
                            Text("10kmh").tag(10)
                            Text("15kmh").tag(15)
                            Text("20kmh").tag(20)
                            Text("30kmh").tag(30)
                        }
                        SettingsDescriptionText("smart_frequent_background_speed_threshold_explanation")

                        Picker("smart_frequent_background_speed_detection_title", selection: $settings.smartFrequentBackgroundSpeedDetectionMode) {
                            Text("smart_frequent_background_speed_detection_hybrid").tag(SmartFrequentBackgroundSpeedDetectionMode.hybrid.rawValue)
                            Text("smart_frequent_background_speed_detection_gps_only").tag(SmartFrequentBackgroundSpeedDetectionMode.gpsOnly.rawValue)
                        }
                        SettingsDescriptionText("smart_frequent_background_speed_detection_explanation")

                        Picker("smart_frequent_background_inactivity_window_title", selection: $settings.smartFrequentBackgroundInactivityWindow) {
                            Text("5minutes").tag(SmartFrequentBackgroundInactivityWindow.fiveMinutes.rawValue)
                            Text("10minutes").tag(SmartFrequentBackgroundInactivityWindow.tenMinutes.rawValue)
                            Text("15minutes").tag(SmartFrequentBackgroundInactivityWindow.fifteenMinutes.rawValue)
                            Text("30minutes").tag(SmartFrequentBackgroundInactivityWindow.thirtyMinutes.rawValue)
                        }
                        SettingsDescriptionText("smart_frequent_background_inactivity_window_explanation")

                        Toggle("smart_frequent_background_mode_change_notifications_title", isOn: smartFrequentModeChangeNotificationsBinding)
                            .accessibilityIdentifier("settings_smart_frequent_background_mode_change_notifications_toggle")
                            .disabled(isRequestingSmartFrequentNotificationPermission)
                        SettingsDescriptionText("smart_frequent_background_mode_change_notifications_explanation")
                        if smartFrequentNotificationPermissionDenied {
                            VStack(alignment: .leading, spacing: 8) {
                                SettingsWarningText("smart_frequent_background_mode_change_notifications_permission_denied_message")
                                Button("smart_frequent_background_mode_change_notifications_open_settings_button") {
                                    LocationManager.shared.openAppSettings()
                                }
                                .font(.caption)
                            }
                        }

                        Toggle("frequent_background_location_updates_title", isOn: $settings.frequentBackgroundLocationUpdatesEnabled)
                            .accessibilityIdentifier("settings_frequent_background_location_updates_toggle")
                        SettingsDescriptionText("frequent_background_location_updates_manual_explanation")

                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            SettingsWarningText("frequent_background_location_updates_battery_warning")
                        }

                        Picker("background_location_distance_filter_title", selection: $settings.frequentBackgroundLocationDistanceFilter) {
                            Text("100m").tag(100)
                            Text("50m").tag(50)
                            Text("25m").tag(25)
                            Text("10m").tag(10)
                            Text("5m").tag(5)
                        }
                        SettingsDescriptionText(frequentBackgroundDistanceFilterExplanationKey)

                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            Picker("frequent_background_location_updates_duration_title", selection: $settings.frequentBackgroundLocationUpdateDuration) {
                                Text("1hour").tag(FrequentBackgroundLocationUpdateDuration.oneHour.rawValue)
                                Text("2hours").tag(FrequentBackgroundLocationUpdateDuration.twoHours.rawValue)
                                Text("3hours").tag(FrequentBackgroundLocationUpdateDuration.threeHours.rawValue)
                                Text("4hours").tag(FrequentBackgroundLocationUpdateDuration.fourHours.rawValue)
                                Text("12hours").tag(FrequentBackgroundLocationUpdateDuration.twelveHours.rawValue)
                                Text("24hours").tag(FrequentBackgroundLocationUpdateDuration.twentyFourHours.rawValue)
                                Text("frequent_background_location_updates_duration_unlimited").tag(FrequentBackgroundLocationUpdateDuration.unlimited.rawValue)
                            }
                            SettingsDescriptionText(frequentBackgroundDurationExplanationKey)
                        }

                        Picker("frequent_background_battery_auto_disable_level_title", selection: $settings.frequentBackgroundBatteryAutoDisableLevel) {
                            Text(verbatim: "10%").tag(10)
                            Text(verbatim: "20%").tag(20)
                            Text(verbatim: "30%").tag(30)
                            Text(verbatim: "40%").tag(40)
                            Text(verbatim: "50%").tag(50)
                        }
                        Text(frequentBackgroundBatteryAutoDisableLevelExplanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Picker("frequent_background_location_delivery_mode_title", selection: $settings.frequentBackgroundLocationDeliveryMode) {
                            Text("frequent_background_location_delivery_immediate").tag(FrequentBackgroundLocationDeliveryMode.immediate.rawValue)
                            Text("frequent_background_location_delivery_30s").tag(FrequentBackgroundLocationDeliveryMode.everyThirtySeconds.rawValue)
                            Text("frequent_background_location_delivery_1m").tag(FrequentBackgroundLocationDeliveryMode.everyMinute.rawValue)
                            Text("frequent_background_location_delivery_5m").tag(FrequentBackgroundLocationDeliveryMode.everyFiveMinutes.rawValue)
                            Text("frequent_background_location_delivery_10m").tag(FrequentBackgroundLocationDeliveryMode.everyTenMinutes.rawValue)
                        }
                        SettingsDescriptionText(frequentBackgroundDeliveryExplanationKey)

                        Picker("frequent_background_visitor_check_interval_title", selection: $settings.frequentBackgroundVisitorCheckInterval) {
                            Text("frequent_background_visitor_check_every_update").tag(FrequentBackgroundVisitorCheckInterval.everyUpdate.rawValue)
                            Text("frequent_background_visitor_check_1m").tag(FrequentBackgroundVisitorCheckInterval.everyMinute.rawValue)
                            Text("frequent_background_visitor_check_5m").tag(FrequentBackgroundVisitorCheckInterval.everyFiveMinutes.rawValue)
                            Text("frequent_background_visitor_check_10m").tag(FrequentBackgroundVisitorCheckInterval.tenMinutes.rawValue)
                            Text("frequent_background_visitor_check_30m").tag(FrequentBackgroundVisitorCheckInterval.everyThirtyMinutes.rawValue)
                            Text("frequent_background_visitor_check_60m").tag(FrequentBackgroundVisitorCheckInterval.everyHour.rawValue)
                        }
                        SettingsDescriptionText(frequentBackgroundVisitorCheckExplanationKey)
                    }
                }
            }

            Section(header: Text("app_behaviour")) {
                Toggle("pulsating_map_markers", isOn: $settings.pulsingMapMarkers)
                    .accessibilityIdentifier("settings_pulsing_map_markers_toggle")
                SettingsDescriptionText("explanation_pulsating_map_markers")

                Toggle("indicate_location_accuracy", isOn: $settings.indicateAccuracyOnMap)
                SettingsDescriptionText("explanation_indicate_location_accuracy")

                Toggle("show_offscreen_arrows_for_other_devices", isOn: $settings.showOffscreenArrowsForOtherDevices)
                SettingsDescriptionText("explanation_show_offscreen_arrows_for_other_devices")

                Toggle("auto_refresh_device_list", isOn: $settings.autoRefreshDeviceList)
                SettingsDescriptionText("explanation_auto_refresh_device_list")

                Toggle("show_current_speed_on_map", isOn: $settings.showCurrentSpeedOnMap)
                SettingsDescriptionText("explanation_show_current_speed_on_map")

                if trackingPermissionVisibility.showsTrackingDependentSettings {
                    Picker("location_update_outbox_retention_title", selection: $settings.locationUpdateOutboxRetentionMode) {
                        Text("location_update_outbox_retention_24h").tag(LocationUpdateOutboxRetentionMode.twentyFourHours.rawValue)
                        Text("location_update_outbox_retention_7d").tag(LocationUpdateOutboxRetentionMode.sevenDays.rawValue)
                        Text("location_update_outbox_retention_30d").tag(LocationUpdateOutboxRetentionMode.thirtyDays.rawValue)
                        Text("location_update_outbox_retention_unlimited").tag(LocationUpdateOutboxRetentionMode.unlimited.rawValue)
                    }

                    Picker("location_update_outbox_max_items_title", selection: $settings.locationUpdateOutboxMaxItems) {
                        Text("500").tag(500)
                        Text("1000").tag(1000)
                        Text("2500").tag(2500)
                        Text("5000").tag(5000)
                        Text("10000").tag(10_000)
                    }
                    SettingsDescriptionText("explanation_location_update_outbox_policy")
                }
            }

            Section(header: Text("map_configuration")) {
                Picker("map_update_interval", selection: $settings.mapUpdateInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                SettingsDescriptionText("explanation_map_update_interval")

                Picker("outside_map_update_interval", selection: $settings.outsideMapUpdateInterval) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("15s").tag(15)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                SettingsDescriptionText("explanation_outside_map_update_interval")

                Toggle("zoom_to_fit_for_groups", isOn: $settings.groupsZoomToFit)
                SettingsDescriptionText("explanation_zoom_to_fit_for_groups")

                Picker("reverse_geocoding_threshold", selection: $settings.reverseGeocodingThresholdMeters) {
                    Text("reverse_geocode_every_update").tag(0)
                    Text("100m").tag(100)
                    Text("1000m").tag(1000)
                    Text("10km").tag(10_000)
                }
                SettingsDescriptionText("explanation_reverse_geocoding_threshold")
            }

            Section(header: Text("navigation")) {
                Toggle("navigation_auto_route_update", isOn: $settings.automaticRouteUpdateDuringNavigation)
                SettingsDescriptionText("explanation_navigation_auto_route_update")

                Toggle("show_route_progress", isOn: $settings.showRouteProgress)
                SettingsDescriptionText("explanation_show_route_progress")
            }
        }
        .navigationTitle("advanced_options")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen_settings_advanced_options")
    }

    private var trackingPermissionVisibility: TrackingPermissionSettingsVisibility {
        TrackingPermissionSettingsGate.visibility(
            trackAndReportLocation: settings.trackAndReportLocation,
            authorizationStatus: locationManager.authorizationStatus
        )
    }

    private var frequentBackgroundDistanceFilterExplanationKey: LocalizedStringKey {
        switch settings.frequentBackgroundLocationDistanceFilter {
        case 5:
            return "background_location_distance_filter_5m_explanation"
        case 10:
            return "background_location_distance_filter_10m_explanation"
        case 25:
            return "background_location_distance_filter_25m_explanation"
        case 50:
            return "background_location_distance_filter_50m_explanation"
        default:
            return "background_location_distance_filter_100m_explanation"
        }
    }

    private var smartFrequentModeChangeNotificationsBinding: Binding<Bool> {
        Binding(
            get: { settings.smartFrequentBackgroundModeChangeNotificationsEnabled },
            set: { updateSmartFrequentModeChangeNotifications($0) }
        )
    }

    private func updateSmartFrequentModeChangeNotifications(_ enabled: Bool) {
        guard enabled else {
            smartFrequentNotificationPermissionDenied = false
            settings.smartFrequentBackgroundModeChangeNotificationsEnabled = false
            return
        }

        isRequestingSmartFrequentNotificationPermission = true
        Task { @MainActor in
            let granted = await FrequentBackgroundTrackingReminderService.shared.requestSmartFrequentModeChangeNotificationAuthorization()
            settings.smartFrequentBackgroundModeChangeNotificationsEnabled = granted
            smartFrequentNotificationPermissionDenied = !granted
            isRequestingSmartFrequentNotificationPermission = false
        }
    }

    private var frequentBackgroundDurationExplanationKey: LocalizedStringKey {
        switch settings.frequentBackgroundLocationUpdateDurationMode {
        case .oneHour:
            return "frequent_background_location_duration_1h_explanation"
        case .twoHours:
            return "frequent_background_location_duration_2h_explanation"
        case .threeHours:
            return "frequent_background_location_duration_3h_explanation"
        case .fourHours:
            return "frequent_background_location_duration_4h_explanation"
        case .twelveHours:
            return "frequent_background_location_duration_12h_explanation"
        case .twentyFourHours:
            return "frequent_background_location_duration_24h_explanation"
        case .unlimited:
            return "frequent_background_location_duration_never_explanation"
        }
    }

    private var frequentBackgroundDeliveryExplanationKey: LocalizedStringKey {
        switch settings.frequentBackgroundLocationDeliveryModeSelection {
        case .immediate:
            return "frequent_background_location_delivery_immediate_explanation"
        case .everyThirtySeconds:
            return "frequent_background_location_delivery_30s_explanation"
        case .everyMinute:
            return "frequent_background_location_delivery_1m_explanation"
        case .everyFiveMinutes:
            return "frequent_background_location_delivery_5m_explanation"
        case .everyTenMinutes:
            return "frequent_background_location_delivery_10m_explanation"
        }
    }

    private var frequentBackgroundBatteryAutoDisableLevelExplanation: String {
        let defaultPercent = Self.localizedPercentString(from: SettingsDefaultValues.frequentBackgroundBatteryAutoDisableLevel)
        let format = NSLocalizedString(
            "frequent_background_battery_auto_disable_level_explanation",
            comment: "Explanation for low-battery auto-disable threshold in frequent background location updates; placeholder is the localized default percentage"
        )
        return String(format: format, locale: .current, defaultPercent)
    }

    private var frequentBackgroundVisitorCheckExplanationKey: LocalizedStringKey {
        switch settings.frequentBackgroundVisitorCheckIntervalSelection {
        case .everyUpdate:
            return "frequent_background_visitor_check_every_update_explanation"
        case .everyMinute:
            return "frequent_background_visitor_check_1m_explanation"
        case .everyFiveMinutes:
            return "frequent_background_visitor_check_5m_explanation"
        case .tenMinutes:
            return "frequent_background_visitor_check_10m_explanation"
        case .everyThirtyMinutes:
            return "frequent_background_visitor_check_30m_explanation"
        case .everyHour:
            return "frequent_background_visitor_check_60m_explanation"
        }
    }

    private static func localizedPercentString(from percent: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: Double(percent) / 100)) ?? "\(percent)%"
    }
}

#Preview {
    iPhone_AdvancedOptionsView()
}
