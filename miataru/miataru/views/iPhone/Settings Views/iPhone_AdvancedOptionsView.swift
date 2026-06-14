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
                Section(header: Text("activity_type_accuracy_settings_title", tableName: "LocationTracking")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("activity_type_tracking_accuracy_title", tableName: "LocationTracking")
                            .font(.headline)
                        Picker("", selection: $settings.locationActivityType) {
                            Text("activity_type_other", tableName: "LocationTracking").tag(0)
                            Text("activity_type_fitness", tableName: "LocationTracking").tag(2)
                            Text("activity_type_automotive", tableName: "LocationTracking").tag(1)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("activity_type_accuracy_explanation")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("location_sensitivity_title", tableName: "MapNavigationHistory")
                            .font(.headline)
                        Picker("", selection: $settings.locationSensitivityLevel) {
                            Text("location_tracking_update_sensitivity_very_sensitive_short", tableName: "LocationTracking").tag(1)
                            Text("location_tracking_update_sensitivity_default_short", tableName: "LocationTracking").tag(2)
                            Text("location_tracking_update_sensitivity_balanced_short", tableName: "LocationTracking").tag(3)
                            Text("location_tracking_update_sensitivity_battery_saver_short", tableName: "LocationTracking").tag(4)
                            Text("location_tracking_update_sensitivity_minimal_short", tableName: "LocationTracking").tag(5)
                        }
                        .pickerStyle(.menu)
                    }

                    SettingsDescriptionText("location_sensitivity_explanation")
                }

                Section(header: Text("background_location_updates_section_title", tableName: "LocationTracking")) {
                    Toggle(String(localized: "smart_frequent_background_location_updates_title", table: "LocationTracking"), isOn: $settings.smartFrequentBackgroundLocationUpdatesEnabled)
                        .accessibilityIdentifier("settings_smart_frequent_background_location_updates_toggle")
                        .disabled(settings.frequentBackgroundLocationUpdatesEnabled)
                    SettingsDescriptionText("smart_frequent_background_location_updates_explanation")
                    if settings.frequentBackgroundLocationUpdatesEnabled {
                        SettingsDescriptionText("smart_frequent_background_locked_by_manual_explanation")
                    }

                    Picker(String(localized: "location_tracking_health_reminder_interval_title", table: "LocationTracking"), selection: $settings.locationTrackingHealthReminderIntervalDays) {
                        Text("5days", tableName: "Common").tag(LocationTrackingHealthReminderInterval.fiveDays.rawValue)
                        Text("7days", tableName: "Common").tag(LocationTrackingHealthReminderInterval.sevenDays.rawValue)
                        Text("14days", tableName: "Common").tag(LocationTrackingHealthReminderInterval.fourteenDays.rawValue)
                        Text("30days", tableName: "Common").tag(LocationTrackingHealthReminderInterval.thirtyDays.rawValue)
                    }
                    SettingsDescriptionText("location_tracking_health_reminder_interval_explanation")

                    if settings.smartFrequentBackgroundLocationUpdatesEnabled {
                        Picker(String(localized: "smart_frequent_background_speed_threshold_title", table: "LocationTracking"), selection: $settings.smartFrequentBackgroundSpeedThresholdKmh) {
                            Text("2kmh", tableName: "Common").tag(2)
                            Text("5kmh", tableName: "Common").tag(5)
                            Text("10kmh", tableName: "Common").tag(10)
                            Text("15kmh", tableName: "Common").tag(15)
                            Text("20kmh", tableName: "Common").tag(20)
                            Text("30kmh", tableName: "Common").tag(30)
                        }
                        SettingsDescriptionText("smart_frequent_background_speed_threshold_explanation")

                        Picker(String(localized: "smart_frequent_background_speed_detection_title", table: "LocationTracking"), selection: $settings.smartFrequentBackgroundSpeedDetectionMode) {
                            Text("smart_frequent_background_speed_detection_hybrid", tableName: "LocationTracking").tag(SmartFrequentBackgroundSpeedDetectionMode.hybrid.rawValue)
                            Text("smart_frequent_background_speed_detection_gps_only", tableName: "LocationTracking").tag(SmartFrequentBackgroundSpeedDetectionMode.gpsOnly.rawValue)
                        }
                        SettingsDescriptionText("smart_frequent_background_speed_detection_explanation")

                        Picker(String(localized: "smart_frequent_background_inactivity_window_title", table: "LocationTracking"), selection: $settings.smartFrequentBackgroundInactivityWindow) {
                            Text("5minutes", tableName: "Common").tag(SmartFrequentBackgroundInactivityWindow.fiveMinutes.rawValue)
                            Text("10minutes", tableName: "Common").tag(SmartFrequentBackgroundInactivityWindow.tenMinutes.rawValue)
                            Text("15minutes", tableName: "Common").tag(SmartFrequentBackgroundInactivityWindow.fifteenMinutes.rawValue)
                            Text("30minutes", tableName: "Common").tag(SmartFrequentBackgroundInactivityWindow.thirtyMinutes.rawValue)
                        }
                        SettingsDescriptionText("smart_frequent_background_inactivity_window_explanation")

                        Picker(String(localized: "smart_frequent_background_exit_fence_radius_title", table: "LocationTracking"), selection: $settings.smartFrequentBackgroundExitFenceRadiusMeters) {
                            Text("300m", tableName: "Common").tag(300)
                            Text("200m", tableName: "Common").tag(200)
                            Text("150m", tableName: "Common").tag(150)
                            Text("100m", tableName: "Common").tag(100)
                            Text("75m", tableName: "Common").tag(75)
                            Text("50m", tableName: "Common").tag(50)
                        }
                        SettingsDescriptionText("smart_frequent_background_exit_fence_radius_explanation")

                        Toggle(String(localized: "smart_frequent_background_mode_change_notifications_title", table: "LocationTracking"), isOn: smartFrequentModeChangeNotificationsBinding)
                            .accessibilityIdentifier("settings_smart_frequent_background_mode_change_notifications_toggle")
                            .disabled(isRequestingSmartFrequentNotificationPermission)
                        SettingsDescriptionText("smart_frequent_background_mode_change_notifications_explanation")
                        if smartFrequentNotificationPermissionDenied {
                            VStack(alignment: .leading, spacing: 8) {
                                SettingsWarningText("smart_frequent_background_mode_change_notifications_permission_denied_message")
                                Button(String(localized: "smart_frequent_background_mode_change_notifications_open_settings_button", table: "LocationTracking")) {
                                    LocationManager.shared.openAppSettings()
                                }
                                .font(.caption)
                            }
                        }

                        Toggle(String(localized: "frequent_background_location_updates_title", table: "LocationTracking"), isOn: $settings.frequentBackgroundLocationUpdatesEnabled)
                            .accessibilityIdentifier("settings_frequent_background_location_updates_toggle")
                        SettingsDescriptionText("frequent_background_location_updates_manual_explanation")

                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            SettingsWarningText("frequent_background_location_updates_battery_warning")
                        }

                        Picker(String(localized: "background_location_distance_filter_title", table: "LocationTracking"), selection: $settings.frequentBackgroundLocationDistanceFilter) {
                            Text("100m", tableName: "Common").tag(100)
                            Text("50m", tableName: "Common").tag(50)
                            Text("25m", tableName: "Common").tag(25)
                            Text("10m", tableName: "Common").tag(10)
                            Text("5m", tableName: "Common").tag(5)
                        }
                        SettingsDescriptionText(frequentBackgroundDistanceFilterExplanationKey)

                        if settings.frequentBackgroundLocationUpdatesEnabled {
                            Picker(String(localized: "frequent_background_location_updates_duration_title", table: "LocationTracking"), selection: $settings.frequentBackgroundLocationUpdateDuration) {
                                Text("1hour", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.oneHour.rawValue)
                                Text("2hours", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.twoHours.rawValue)
                                Text("3hours", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.threeHours.rawValue)
                                Text("4hours", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.fourHours.rawValue)
                                Text("12hours", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.twelveHours.rawValue)
                                Text("24hours", tableName: "Common").tag(FrequentBackgroundLocationUpdateDuration.twentyFourHours.rawValue)
                                Text("frequent_background_location_updates_duration_unlimited", tableName: "LocationTracking").tag(FrequentBackgroundLocationUpdateDuration.unlimited.rawValue)
                            }
                            SettingsDescriptionText(frequentBackgroundDurationExplanationKey)
                        }

                        Picker(String(localized: "frequent_background_battery_auto_disable_level_title", table: "LocationTracking"), selection: $settings.frequentBackgroundBatteryAutoDisableLevel) {
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

                        Picker(String(localized: "frequent_background_location_delivery_mode_title", table: "LocationTracking"), selection: $settings.frequentBackgroundLocationDeliveryMode) {
                            Text("frequent_background_location_delivery_immediate", tableName: "LocationTracking").tag(FrequentBackgroundLocationDeliveryMode.immediate.rawValue)
                            Text("frequent_background_location_delivery_30s", tableName: "LocationTracking").tag(FrequentBackgroundLocationDeliveryMode.everyThirtySeconds.rawValue)
                            Text("frequent_background_location_delivery_1m", tableName: "LocationTracking").tag(FrequentBackgroundLocationDeliveryMode.everyMinute.rawValue)
                            Text("frequent_background_location_delivery_5m", tableName: "LocationTracking").tag(FrequentBackgroundLocationDeliveryMode.everyFiveMinutes.rawValue)
                            Text("frequent_background_location_delivery_10m", tableName: "LocationTracking").tag(FrequentBackgroundLocationDeliveryMode.everyTenMinutes.rawValue)
                        }
                        SettingsDescriptionText(frequentBackgroundDeliveryExplanationKey)

                        Picker(String(localized: "frequent_background_visitor_check_interval_title", table: "LocationTracking"), selection: $settings.frequentBackgroundVisitorCheckInterval) {
                            Text("frequent_background_visitor_check_every_update", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.everyUpdate.rawValue)
                            Text("frequent_background_visitor_check_1m", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.everyMinute.rawValue)
                            Text("frequent_background_visitor_check_5m", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.everyFiveMinutes.rawValue)
                            Text("frequent_background_visitor_check_10m", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.tenMinutes.rawValue)
                            Text("frequent_background_visitor_check_30m", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.everyThirtyMinutes.rawValue)
                            Text("frequent_background_visitor_check_60m", tableName: "LocationTracking").tag(FrequentBackgroundVisitorCheckInterval.everyHour.rawValue)
                        }
                        SettingsDescriptionText(frequentBackgroundVisitorCheckExplanationKey)
                    }
                }
            }

            Section(header: Text("app_behaviour", tableName: "SettingsDiagnostics")) {
                Toggle(String(localized: "pulsating_map_markers", table: "LocationTracking"), isOn: $settings.pulsingMapMarkers)
                    .accessibilityIdentifier("settings_pulsing_map_markers_toggle")
                SettingsDescriptionText("explanation_pulsating_map_markers")

                Toggle(String(localized: "indicate_location_accuracy", table: "LocationTracking"), isOn: $settings.indicateAccuracyOnMap)
                SettingsDescriptionText("explanation_indicate_location_accuracy")

                Toggle(String(localized: "show_offscreen_arrows_for_other_devices", table: "MapNavigationHistory"), isOn: $settings.showOffscreenArrowsForOtherDevices)
                SettingsDescriptionText("explanation_show_offscreen_arrows_for_other_devices")

                Toggle(String(localized: "auto_refresh_device_list", table: "LocationTracking"), isOn: $settings.autoRefreshDeviceList)
                SettingsDescriptionText("explanation_auto_refresh_device_list")

                Toggle(String(localized: "show_current_speed_on_map", table: "MapNavigationHistory"), isOn: $settings.showCurrentSpeedOnMap)
                SettingsDescriptionText("explanation_show_current_speed_on_map")

                if trackingPermissionVisibility.showsTrackingDependentSettings {
                    Picker(String(localized: "location_update_outbox_retention_title", table: "LocationTracking"), selection: $settings.locationUpdateOutboxRetentionMode) {
                        Text("location_update_outbox_retention_24h", tableName: "LocationTracking").tag(LocationUpdateOutboxRetentionMode.twentyFourHours.rawValue)
                        Text("location_update_outbox_retention_7d", tableName: "LocationTracking").tag(LocationUpdateOutboxRetentionMode.sevenDays.rawValue)
                        Text("location_update_outbox_retention_30d", tableName: "LocationTracking").tag(LocationUpdateOutboxRetentionMode.thirtyDays.rawValue)
                        Text("location_update_outbox_retention_unlimited", tableName: "LocationTracking").tag(LocationUpdateOutboxRetentionMode.unlimited.rawValue)
                    }

                    Picker(String(localized: "location_update_outbox_max_items_title", table: "LocationTracking"), selection: $settings.locationUpdateOutboxMaxItems) {
                        Text("500", tableName: "Common").tag(500)
                        Text("1000", tableName: "Common").tag(1000)
                        Text("2500", tableName: "Common").tag(2500)
                        Text("5000", tableName: "Common").tag(5000)
                        Text("10000", tableName: "Common").tag(10_000)
                    }
                    SettingsDescriptionText("explanation_location_update_outbox_policy")
                }
            }

            Section(header: Text("map_configuration", tableName: "MapNavigationHistory")) {
                Picker(String(localized: "map_update_interval", table: "MapNavigationHistory"), selection: $settings.mapUpdateInterval) {
                    Text("5s", tableName: "Common").tag(5)
                    Text("10s", tableName: "Common").tag(10)
                    Text("15s", tableName: "Common").tag(15)
                    Text("30s", tableName: "Common").tag(30)
                    Text("60s", tableName: "Common").tag(60)
                }
                SettingsDescriptionText("explanation_map_update_interval")

                Picker(String(localized: "outside_map_update_interval", table: "LocationTracking"), selection: $settings.outsideMapUpdateInterval) {
                    Text("5s", tableName: "Common").tag(5)
                    Text("10s", tableName: "Common").tag(10)
                    Text("15s", tableName: "Common").tag(15)
                    Text("30s", tableName: "Common").tag(30)
                    Text("60s", tableName: "Common").tag(60)
                }
                SettingsDescriptionText("explanation_outside_map_update_interval")

                Toggle(String(localized: "zoom_to_fit_for_groups", table: "LocationTracking"), isOn: $settings.groupsZoomToFit)
                SettingsDescriptionText("explanation_zoom_to_fit_for_groups")

                Picker(String(localized: "reverse_geocoding_threshold", table: "LocationTracking"), selection: $settings.reverseGeocodingThresholdMeters) {
                    Text("reverse_geocode_every_update").tag(0)
                    Text("100m", tableName: "Common").tag(100)
                    Text("1000m", tableName: "Common").tag(1000)
                    Text("10km", tableName: "Common").tag(10_000)
                }
                SettingsDescriptionText("explanation_reverse_geocoding_threshold")
            }

            Section(header: Text("navigation", tableName: "MapNavigationHistory")) {
                Toggle(String(localized: "navigation_auto_route_update", table: "MapNavigationHistory"), isOn: $settings.automaticRouteUpdateDuringNavigation)
                SettingsDescriptionText("explanation_navigation_auto_route_update")

                Toggle(String(localized: "show_route_progress", table: "MapNavigationHistory"), isOn: $settings.showRouteProgress)
                SettingsDescriptionText("explanation_show_route_progress")
            }
        }
        .navigationTitle(String(localized: "advanced_options", table: "SettingsDiagnostics"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen_settings_advanced_options")
    }

    private var trackingPermissionVisibility: TrackingPermissionSettingsVisibility {
        TrackingPermissionSettingsGate.visibility(
            trackAndReportLocation: settings.trackAndReportLocation,
            authorizationStatus: locationManager.authorizationStatus
        )
    }

    private var frequentBackgroundDistanceFilterExplanationKey: String {
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

    private var frequentBackgroundDurationExplanationKey: String {
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

    private var frequentBackgroundDeliveryExplanationKey: String {
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
        let format = NSLocalizedString("frequent_background_battery_auto_disable_level_explanation", tableName: "LocationTracking", comment: "Explanation for low-battery auto-disable threshold in frequent background location updates; placeholder is the localized default percentage"
        )
        return String(format: format, locale: .current, defaultPercent)
    }

    private var frequentBackgroundVisitorCheckExplanationKey: String {
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
