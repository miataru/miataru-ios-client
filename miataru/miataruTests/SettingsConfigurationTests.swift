/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SettingsConfigurationTests.swift
 * miataruTests
 *
 * Created by Codex on 14.03.26.
 */

import Testing
import Foundation
import CoreLocation
import UIKit
@testable import miataru

struct SettingsConfigurationTests {
    private let expectedLocales: Set<String> = ["da", "de", "en", "es", "fi", "fr", "it", "ja", "nl", "zh-Hans"]

    @Test("Existing-install settings migration applies once and only to targeted keys")
    func existingInstallSettingsMigrationAppliesOnce() throws {
        let suiteName = "SettingsConfigurationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: SettingsKeys.automaticRouteUpdateDuringNavigation)
        defaults.set(false, forKey: SettingsKeys.showRouteProgress)
        defaults.set(false, forKey: SettingsKeys.groupsZoomToFit)
        defaults.set(false, forKey: SettingsKeys.autoRefreshDeviceList)
        defaults.set(false, forKey: SettingsKeys.showCurrentSpeedOnMap)
        defaults.set(false, forKey: SettingsKeys.indicateAccuracyOnMap)
        defaults.set(false, forKey: SettingsKeys.showOffscreenArrowsForOtherDevices)
        defaults.set(false, forKey: SettingsKeys.pulsingMapMarkers)
        defaults.set(false, forKey: SettingsKeys.trackAndReportLocation)
        defaults.set("https://custom.example", forKey: SettingsKeys.miataruServerURL)
        defaults.set(15, forKey: SettingsKeys.mapZoomLevel)

        SettingsMigration.applyExistingInstallDefaultsIfNeeded(defaults: defaults)

        #expect(defaults.bool(forKey: SettingsKeys.automaticRouteUpdateDuringNavigation))
        #expect(defaults.bool(forKey: SettingsKeys.showRouteProgress))
        #expect(defaults.bool(forKey: SettingsKeys.groupsZoomToFit))
        #expect(defaults.bool(forKey: SettingsKeys.autoRefreshDeviceList))
        #expect(defaults.bool(forKey: SettingsKeys.showCurrentSpeedOnMap))
        #expect(defaults.bool(forKey: SettingsKeys.indicateAccuracyOnMap))
        #expect(defaults.bool(forKey: SettingsKeys.showOffscreenArrowsForOtherDevices))
        #expect(defaults.bool(forKey: SettingsKeys.pulsingMapMarkers))
        #expect(defaults.bool(forKey: SettingsMigration.existingInstallDefaultsV315Marker))
        #expect(!defaults.bool(forKey: SettingsKeys.trackAndReportLocation))
        #expect(defaults.string(forKey: SettingsKeys.miataruServerURL) == "https://custom.example")
        #expect(defaults.integer(forKey: SettingsKeys.mapZoomLevel) == 15)

        defaults.set(false, forKey: SettingsKeys.showRouteProgress)
        SettingsMigration.applyExistingInstallDefaultsIfNeeded(defaults: defaults)
        #expect(!defaults.bool(forKey: SettingsKeys.showRouteProgress))
    }

    @Test("Smart frequent migration preserves existing manual frequent users")
    func smartFrequentMigrationPreservesExistingManualFrequentUsers() throws {
        let suiteName = "SmartFrequentMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)

        SettingsMigration.applySmartFrequentBackgroundMigrationIfNeeded(defaults: defaults)

        #expect(defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled))
        #expect(defaults.bool(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled))
        #expect(defaults.bool(forKey: SettingsMigration.smartFrequentBackgroundV1Marker))

        defaults.set(false, forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
        SettingsMigration.applySmartFrequentBackgroundMigrationIfNeeded(defaults: defaults)
        #expect(!defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled))
    }

    @Test("Manual frequent normalization keeps smart prerequisite enabled after migration")
    func manualFrequentNormalizationKeepsSmartPrerequisiteEnabledAfterMigration() throws {
        let suiteName = "SmartFrequentPrerequisiteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: SettingsMigration.smartFrequentBackgroundV1Marker)
        defaults.set(false, forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
        defaults.set(true, forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)

        SettingsMigration.applySmartFrequentBackgroundMigrationIfNeeded(defaults: defaults)
        #expect(!defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled))

        SettingsMigration.normalizeSmartFrequentBackgroundPrerequisiteIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled))
        #expect(defaults.bool(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled))
    }

    @Test("Tracking permission visibility requires Always for dependent settings")
    func trackingPermissionVisibilityRequiresAlwaysForDependentSettings() {
        let statuses: [CLAuthorizationStatus] = [
            .authorizedAlways,
            .authorizedWhenInUse,
            .denied,
            .restricted,
            .notDetermined,
        ]

        for status in statuses {
            let visibility = TrackingPermissionSettingsGate.visibility(
                trackAndReportLocation: false,
                authorizationStatus: status
            )
            #expect(!visibility.showsTrackingDependentSettings, "Disabled tracking should hide dependent settings for status \(status.rawValue)")
            #expect(!visibility.showsAlwaysPermissionNotice, "Disabled tracking should not show Always notice for status \(status.rawValue)")
        }

        let alwaysVisibility = TrackingPermissionSettingsGate.visibility(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways
        )
        #expect(alwaysVisibility.showsTrackingDependentSettings)
        #expect(!alwaysVisibility.showsAlwaysPermissionNotice)

        let missingAlwaysStatuses: [CLAuthorizationStatus] = [
            .authorizedWhenInUse,
            .denied,
            .restricted,
            .notDetermined,
        ]
        for status in missingAlwaysStatuses {
            let visibility = TrackingPermissionSettingsGate.visibility(
                trackAndReportLocation: true,
                authorizationStatus: status
            )
            #expect(!visibility.showsTrackingDependentSettings, "Missing Always should hide dependent settings for status \(status.rawValue)")
            #expect(visibility.showsAlwaysPermissionNotice, "Missing Always should show notice for status \(status.rawValue)")
        }
    }

    @Test("Settings localization keys exist for all app locales")
    func settingsLocalizationKeysExistForAllLocales() throws {
        let requiredKeys = [
            "advanced_options",
            "advanced_options_and_tracking_status",
            "always_location_permission_required_title",
            "always_location_permission_required_message",
            "always_location_permission_required_steps",
            "activity_type_accuracy_settings_title",
            "activity_type_tracking_accuracy_title",
            "activity_type_accuracy_explanation",
            "location_sensitivity_title",
            "location_sensitivity_explanation",
            "background_location_updates_section_title",
            "smart_frequent_background_location_updates_title",
            "smart_frequent_background_location_updates_explanation",
            "smart_frequent_background_locked_by_manual_explanation",
            "smart_frequent_background_speed_threshold_title",
            "smart_frequent_background_speed_threshold_explanation",
            "smart_frequent_background_speed_detection_title",
            "smart_frequent_background_speed_detection_hybrid",
            "smart_frequent_background_speed_detection_gps_only",
            "smart_frequent_background_speed_detection_explanation",
            "smart_frequent_background_inactivity_window_title",
            "smart_frequent_background_inactivity_window_explanation",
            "smart_frequent_background_mode_change_notifications_title",
            "smart_frequent_background_mode_change_notifications_explanation",
            "smart_frequent_background_mode_change_notifications_permission_denied_message",
            "smart_frequent_background_mode_change_notifications_open_settings_button",
            "smart_frequent_background_activated_notification_title",
            "smart_frequent_background_activated_notification_body",
            "smart_frequent_background_deactivated_notification_title",
            "smart_frequent_background_deactivated_notification_body",
            "smart_frequent_background_waiting_hint",
            "frequent_background_location_updates_title",
            "frequent_background_location_updates_manual_explanation",
            "frequent_background_location_updates_battery_warning",
            "frequent_background_battery_auto_disable_level_title",
            "frequent_background_battery_auto_disable_level_explanation",
            "frequent_background_location_battery_auto_disabled_notification_title",
            "frequent_background_location_battery_auto_disabled_notification_body_format",
            "frequent_background_location_reminder_notification_title",
            "frequent_background_location_reminder_notification_body",
            "frequent_background_location_expired_notification_title",
            "frequent_background_location_expired_notification_body",
            "background_location_distance_filter_title",
            "background_location_distance_filter_5m_explanation",
            "background_location_distance_filter_10m_explanation",
            "background_location_distance_filter_100m_explanation",
            "background_location_distance_filter_50m_explanation",
            "background_location_distance_filter_25m_explanation",
            "frequent_background_location_updates_duration_title",
            "frequent_background_location_updates_duration_unlimited",
            "1hour",
            "2hours",
            "3hours",
            "4hours",
            "12hours",
            "24hours",
            "frequent_background_location_duration_1h_explanation",
            "frequent_background_location_duration_2h_explanation",
            "frequent_background_location_duration_3h_explanation",
            "frequent_background_location_duration_4h_explanation",
            "frequent_background_location_duration_12h_explanation",
            "frequent_background_location_duration_24h_explanation",
            "frequent_background_location_duration_never_explanation",
            "frequent_background_location_delivery_mode_title",
            "frequent_background_location_delivery_immediate",
            "frequent_background_location_delivery_30s",
            "frequent_background_location_delivery_1m",
            "frequent_background_location_delivery_5m",
            "frequent_background_location_delivery_10m",
            "frequent_background_location_delivery_immediate_explanation",
            "frequent_background_location_delivery_30s_explanation",
            "frequent_background_location_delivery_1m_explanation",
            "frequent_background_location_delivery_5m_explanation",
            "frequent_background_location_delivery_10m_explanation",
            "frequent_background_visitor_check_interval_title",
            "frequent_background_visitor_check_every_update",
            "frequent_background_visitor_check_1m",
            "frequent_background_visitor_check_5m",
            "frequent_background_visitor_check_10m",
            "frequent_background_visitor_check_30m",
            "frequent_background_visitor_check_60m",
            "frequent_background_visitor_check_every_update_explanation",
            "frequent_background_visitor_check_1m_explanation",
            "frequent_background_visitor_check_5m_explanation",
            "frequent_background_visitor_check_10m_explanation",
            "frequent_background_visitor_check_30m_explanation",
            "frequent_background_visitor_check_60m_explanation",
            "frequent_background_location_updates_active_hint_format",
            "Location updates in the background use the battery-saving standard mode.",
            "tracking_mode_manual_frequent_background_updates_format",
            "tracking_mode_smart_frequent_background_updates_format",
            "tracking_mode_smart_waiting",
            "tracking_mode_battery_saving_standard",
            "background_tracking_mode_title",
            "background_tracking_expires_at_label",
            "background_tracking_mode_foreground_live",
            "background_tracking_mode_frequent_format",
            "background_tracking_mode_smart_frequent_format",
            "background_tracking_mode_smart_waiting",
            "background_tracking_mode_significant_change",
            "background_tracking_expires_never",
            "location_update_count_foreground_live_label",
            "location_update_count_significant_change_label",
            "location_update_count_smart_frequent_label",
            "location_update_count_manual_frequent_label",
            "location_permission_state_title",
            "smart_frequent_background_last_activation_label",
            "smart_frequent_background_no_activation_yet",
            "smart_frequent_background_last_movement_label",
            "smart_frequent_background_next_timeout_label",
            "smart_frequent_background_no_movement_yet",
            "smart_frequent_background_no_timeout_pending",
            "smart_frequent_background_activation_speed_format",
            "smart_frequent_background_activation_movement",
            "location_update_mode_significant_change",
            "location_update_mode_smart_frequent",
            "location_update_mode_manual_frequent",
            "2kmh",
            "5kmh",
            "10kmh",
            "15kmh",
            "20kmh",
            "30kmh",
            "5minutes",
            "10minutes",
            "15minutes",
            "location_track",
            "explanation_location_track",
            "save_location_history_to_server",
            "explanation_save_location_history_to_server",
            "store_history_before_autoremove",
            "explanation_store_history_before_autoremove",
            "server_url",
            "explanation_server_url",
            "app_behaviour",
            "deactivate_device_lock",
            "explanation_deactivate_device_lock",
            "prevent_screen_rotation",
            "explanation_prevent_screen_rotation",
            "pulsating_map_markers",
            "explanation_pulsating_map_markers",
            "indicate_location_accuracy",
            "explanation_indicate_location_accuracy",
            "show_offscreen_arrows_for_other_devices",
            "explanation_show_offscreen_arrows_for_other_devices",
            "auto_refresh_device_list",
            "explanation_auto_refresh_device_list",
            "show_current_speed_on_map",
            "explanation_show_current_speed_on_map",
            "location_update_outbox_retention_title",
            "location_update_outbox_retention_24h",
            "location_update_outbox_retention_7d",
            "location_update_outbox_retention_30d",
            "location_update_outbox_retention_unlimited",
            "location_update_outbox_max_items_title",
            "explanation_location_update_outbox_policy",
            "location_update_outbox_server_change_title",
            "location_update_outbox_server_change_message",
            "location_update_outbox_send_to_new_server_button",
            "location_update_outbox_discard_pending_button",
            "location_update_outbox_flush_button",
            "map_configuration",
            "map_type",
            "explanation_map_type",
            "map_update_interval",
            "explanation_map_update_interval",
            "outside_map_update_interval",
            "explanation_outside_map_update_interval",
            "map_zoom_level",
            "explanation_map_zoom_level",
            "zoom_to_fit_for_groups",
            "explanation_zoom_to_fit_for_groups",
            "reverse_geocoding_threshold",
            "explanation_reverse_geocoding_threshold",
            "navigation",
            "transport_mode",
            "explanation_navigation_mode",
            "navigation_auto_route_update",
            "explanation_navigation_auto_route_update",
            "show_route_progress",
            "explanation_show_route_progress",
            "explanation_unknown_visitor_alerts_toggle",
            "allowed_device_list_enabled_explanation",
            "allowed_device_list_disabled_explanation",
        ]

        let strings = try loadStringCatalog()

        for key in requiredKeys {
            let keyEntry = try #require(strings[key] as? [String: Any], "Missing localization key: \(key)")
            let localizations = try #require(keyEntry["localizations"] as? [String: Any], "Missing localizations block for key: \(key)")

            let localeSet = Set(localizations.keys)
            #expect(localeSet == expectedLocales, "Locales mismatch for key \(key): \(localeSet)")

            for locale in expectedLocales {
                let localeEntry = try #require(localizations[locale] as? [String: Any], "Missing locale \(locale) for key \(key)")
                let stringUnit = try #require(localeEntry["stringUnit"] as? [String: Any], "Missing stringUnit for key \(key), locale \(locale)")
                let value = try #require(stringUnit["value"] as? String, "Missing value for key \(key), locale \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty value for key \(key), locale \(locale)")
            }
        }
    }

    @Test("App string catalog has no stale or new translation units")
    func appStringCatalogHasNoStaleOrNewTranslationUnits() throws {
        let strings = try loadStringCatalog()

        let staleKeys = strings.compactMap { key, rawEntry -> String? in
            guard let entry = rawEntry as? [String: Any],
                  entry["extractionState"] as? String == "stale" else {
                return nil
            }
            return key
        }
        #expect(staleKeys.isEmpty, "Stale localization keys: \(staleKeys.sorted())")

        var newUnits: [String] = []
        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                continue
            }
            for (locale, rawLocaleEntry) in localizations {
                guard let localeEntry = rawLocaleEntry as? [String: Any],
                      let stringUnit = localeEntry["stringUnit"] as? [String: Any],
                      stringUnit["state"] as? String == "new" else {
                    continue
                }
                newUnits.append("\(key) [\(locale)]")
            }
        }
        #expect(newUnits.isEmpty, "New localization units: \(newUnits.sorted())")
    }

    @Test("Settings.bundle strings contain renamed labels and picker options for all locales")
    func settingsBundleStringsContainRequiredKeysForAllLocales() throws {
        let requiredKeys = [
            "track_and_history",
            "location_track",
            "save_location_history_to_server",
            "store_history_before_autoremove",
            "activity_type_accuracy_settings_title",
            "activity_type_tracking_accuracy_title",
            "activity_type_other",
            "activity_type_fitness",
            "activity_type_automotive",
            "location_sensitivity_title",
            "background_location_updates_section_title",
            "smart_frequent_background_location_updates_title",
            "smart_frequent_background_speed_threshold_title",
            "smart_frequent_background_speed_detection_title",
            "smart_frequent_background_speed_detection_hybrid",
            "smart_frequent_background_speed_detection_gps_only",
            "smart_frequent_background_inactivity_window_title",
            "smart_frequent_background_mode_change_notifications_title",
            "frequent_background_location_updates_title",
            "background_location_distance_filter_title",
            "frequent_background_location_updates_duration_title",
            "frequent_background_location_updates_duration_unlimited",
            "frequent_background_battery_auto_disable_level_title",
            "frequent_background_location_delivery_mode_title",
            "frequent_background_location_delivery_immediate",
            "frequent_background_location_delivery_30s",
            "frequent_background_location_delivery_1m",
            "frequent_background_location_delivery_5m",
            "frequent_background_location_delivery_10m",
            "frequent_background_visitor_check_interval_title",
            "frequent_background_visitor_check_every_update",
            "frequent_background_visitor_check_1m",
            "frequent_background_visitor_check_5m",
            "frequent_background_visitor_check_10m",
            "frequent_background_visitor_check_30m",
            "frequent_background_visitor_check_60m",
            "1hour",
            "2hours",
            "3hours",
            "4hours",
            "12hours",
            "24hours",
            "100m",
            "50m",
            "25m",
            "2kmh",
            "5kmh",
            "10kmh",
            "15kmh",
            "20kmh",
            "30kmh",
            "5minutes",
            "10minutes",
            "15minutes",
            "server_url",
            "app_behaviour",
            "deactivate_device_lock",
            "prevent_screen_rotation",
            "indicate_location_accuracy",
            "show_offscreen_arrows_for_other_devices",
            "auto_refresh_device_list",
            "show_current_speed_on_map",
            "location_update_outbox_retention_title",
            "location_update_outbox_retention_24h",
            "location_update_outbox_retention_7d",
            "location_update_outbox_retention_30d",
            "location_update_outbox_retention_unlimited",
            "location_update_outbox_max_items_title",
            "map_configuration",
            "map_type",
            "default_map",
            "hybrid_map",
            "sat_map",
            "map_update_interval",
            "outside_map_update_interval",
            "map_zoom_level",
            "zoom_to_fit_for_groups",
            "reverse_geocoding_threshold",
            "reverse_geocode_every_update",
            "navigation",
            "transport_mode",
            "transport_walk",
            "transport_car",
            "transport_transit",
            "show_route_progress",
            "advanced_options",
            "pulsating_map_markers",
            "navigation_auto_route_update",
        ]

        for locale in expectedLocales {
            let dictionary = try loadSettingsBundleStrings(locale: locale)

            for key in requiredKeys {
                let value = try #require(dictionary[key], "Missing key \(key) in Settings.bundle locale \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty value for key \(key) in Settings.bundle locale \(locale)")
            }
        }
    }

    @Test("Settings.bundle plist defaults match the runtime settings defaults")
    func settingsBundleDefaultsMatchRuntimeSettingsDefaults() throws {
        let specifiers = try loadSettingsBundleSpecifiers()
        let defaultsByKey = Dictionary(uniqueKeysWithValues: specifiers.compactMap { specifier -> (String, Any)? in
            guard let key = specifier["Key"] as? String,
                  let defaultValue = specifier["DefaultValue"] else {
                return nil
            }
            return (key, defaultValue)
        })

        #expect(defaultsByKey[SettingsKeys.trackAndReportLocation] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.locationActivityType] as? String == "0")
        #expect(defaultsByKey[SettingsKeys.locationSensitivityLevel] as? String == "2")
        #expect(defaultsByKey[SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.smartFrequentBackgroundSpeedThresholdKmh] as? String == "10")
        #expect(defaultsByKey[SettingsKeys.smartFrequentBackgroundSpeedDetectionMode] as? String == "0")
        #expect(defaultsByKey[SettingsKeys.smartFrequentBackgroundInactivityWindow] as? String == "600")
        #expect(defaultsByKey[SettingsKeys.smartFrequentBackgroundModeChangeNotificationsEnabled] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundLocationUpdatesEnabled] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundLocationDistanceFilter] as? String == "100")
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundLocationUpdateDuration] as? String == "14400")
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundBatteryAutoDisableLevel] as? String == "30")
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundLocationDeliveryMode] as? String == "0")
        #expect(defaultsByKey[SettingsKeys.frequentBackgroundVisitorCheckInterval] as? String == "600")
        #expect(defaultsByKey[SettingsKeys.disableDeviceAutolock] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.preventScreenRotation] as? Bool == false)
        #expect(defaultsByKey[SettingsKeys.pulsingMapMarkers] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.indicateAccuracyOnMap] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.showOffscreenArrowsForOtherDevices] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.autoRefreshDeviceList] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.showCurrentSpeedOnMap] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.locationUpdateOutboxRetentionMode] as? String == "0")
        #expect(defaultsByKey[SettingsKeys.locationUpdateOutboxMaxItems] as? String == "500")
        #expect(defaultsByKey[SettingsKeys.mapType] as? String == "1")
        #expect(defaultsByKey[SettingsKeys.mapUpdateInterval] as? String == "30")
        #expect(defaultsByKey[SettingsKeys.outsideMapUpdateInterval] as? String == "60")
        #expect(defaultsByKey[SettingsKeys.mapZoomLevel] as? String == "5")
        #expect(defaultsByKey[SettingsKeys.groupsZoomToFit] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.reverseGeocodingThresholdMeters] as? String == "1000")
        #expect(defaultsByKey[SettingsKeys.navigationTransportType] as? String == "2")
        #expect(defaultsByKey[SettingsKeys.automaticRouteUpdateDuringNavigation] as? Bool == true)
        #expect(defaultsByKey[SettingsKeys.showRouteProgress] as? Bool == true)

        let distanceFilterSpecifier = try #require(specifiers.first {
            $0["Key"] as? String == SettingsKeys.frequentBackgroundLocationDistanceFilter
        })
        #expect(distanceFilterSpecifier["Titles"] as? [String] == ["100m", "50m", "25m", "10m", "5m"])
        #expect(distanceFilterSpecifier["Values"] as? [String] == ["100", "50", "25", "10", "5"])
    }

    @Test("Frequent background location update settings normalize and expire as expected")
    func frequentBackgroundLocationUpdateSettingsNormalizeAndExpire() {
        #expect(SmartFrequentBackgroundSpeedThreshold.normalized(2) == 2)
        #expect(SmartFrequentBackgroundSpeedThreshold.normalized(5) == 5)
        #expect(SmartFrequentBackgroundSpeedThreshold.normalized(10) == 10)
        #expect(SmartFrequentBackgroundSpeedThreshold.normalized(30) == 30)
        #expect(SmartFrequentBackgroundSpeedThreshold.normalized(7) == SettingsDefaultValues.smartFrequentBackgroundSpeedThresholdKmh)
        #expect(SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(SmartFrequentBackgroundSpeedDetectionMode.hybrid.rawValue) == 0)
        #expect(SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(SmartFrequentBackgroundSpeedDetectionMode.gpsOnly.rawValue) == 1)
        #expect(SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(12) == SettingsDefaultValues.smartFrequentBackgroundSpeedDetectionMode)
        #expect(SmartFrequentBackgroundInactivityWindow.tenMinutes.timeInterval == 600)
        #expect(SmartFrequentBackgroundInactivityWindow.normalizedRawValue(SmartFrequentBackgroundInactivityWindow.thirtyMinutes.rawValue) == 1_800)
        #expect(SmartFrequentBackgroundInactivityWindow.normalizedRawValue(123) == SettingsDefaultValues.smartFrequentBackgroundInactivityWindow)

        #expect(FrequentBackgroundLocationDistanceFilter.normalized(100) == 100)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(50) == 50)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(25) == 25)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(10) == 10)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(5) == 5)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(3) == SettingsDefaultValues.frequentBackgroundLocationDistanceFilter)

        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(FrequentBackgroundLocationUpdateDuration.oneHour.rawValue) == 3_600)
        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(FrequentBackgroundLocationUpdateDuration.twoHours.rawValue) == 7_200)
        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(FrequentBackgroundLocationUpdateDuration.threeHours.rawValue) == 10_800)
        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(123) == SettingsDefaultValues.frequentBackgroundLocationUpdateDuration)

        let startDate = Date(timeIntervalSince1970: 1_000)
        #expect(FrequentBackgroundLocationUpdateDuration.twoHours.expirationDate(from: startDate) == startDate.addingTimeInterval(7_200))
        #expect(FrequentBackgroundLocationUpdateDuration.threeHours.expirationDate(from: startDate) == startDate.addingTimeInterval(10_800))
        #expect(FrequentBackgroundLocationUpdateDuration.fourHours.expirationDate(from: startDate) == startDate.addingTimeInterval(14_400))
        #expect(FrequentBackgroundLocationUpdateDuration.unlimited.expirationDate(from: startDate) == nil)

        #expect(FrequentBackgroundBatteryAutoDisableLevel.normalized(10) == 10)
        #expect(FrequentBackgroundBatteryAutoDisableLevel.normalized(30) == 30)
        #expect(FrequentBackgroundBatteryAutoDisableLevel.normalized(50) == 50)
        #expect(FrequentBackgroundBatteryAutoDisableLevel.normalized(25) == SettingsDefaultValues.frequentBackgroundBatteryAutoDisableLevel)

        #expect(FrequentBackgroundLocationDeliveryMode.immediate.delay == nil)
        #expect(FrequentBackgroundLocationDeliveryMode.everyThirtySeconds.delay == 30)
        #expect(FrequentBackgroundLocationDeliveryMode.normalizedRawValue(FrequentBackgroundLocationDeliveryMode.everyTenMinutes.rawValue) == 600)
        #expect(FrequentBackgroundLocationDeliveryMode.normalizedRawValue(123) == SettingsDefaultValues.frequentBackgroundLocationDeliveryMode)

        #expect(FrequentBackgroundVisitorCheckInterval.everyUpdate.minimumInterval == nil)
        #expect(FrequentBackgroundVisitorCheckInterval.tenMinutes.minimumInterval == 600)
        #expect(FrequentBackgroundVisitorCheckInterval.normalizedRawValue(FrequentBackgroundVisitorCheckInterval.everyHour.rawValue) == 3_600)
        #expect(FrequentBackgroundVisitorCheckInterval.normalizedRawValue(123) == SettingsDefaultValues.frequentBackgroundVisitorCheckInterval)
    }

    @Test("App activation refresh imports external tracking and frequent defaults")
    func appActivationRefreshImportsExternalTrackingAndFrequentDefaults() throws {
        let suiteName = "SettingsActivationRefreshTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.register(defaults: SettingsDefaultValues.registrations)

        let manager = SettingsManager(defaults: defaults)
        let now = Date(timeIntervalSince1970: 50_000)

        #expect(!manager.trackAndReportLocation)
        #expect(!manager.frequentBackgroundLocationUpdatesEnabled)
        #expect(!manager.smartFrequentBackgroundLocationUpdatesEnabled)

        defaults.set(true, forKey: SettingsKeys.trackAndReportLocation)
        defaults.set(true, forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)
        defaults.set(false, forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
        defaults.set("7200", forKey: SettingsKeys.frequentBackgroundLocationUpdateDuration)
        defaults.set("3", forKey: SettingsKeys.frequentBackgroundLocationDistanceFilter)

        #expect(manager.refreshFromUserDefaultsForAppActivation(now: now))
        #expect(manager.trackAndReportLocation)
        #expect(manager.frequentBackgroundLocationUpdatesEnabled)
        #expect(manager.smartFrequentBackgroundLocationUpdatesEnabled)
        #expect(manager.frequentBackgroundLocationUpdateDuration == FrequentBackgroundLocationUpdateDuration.twoHours.rawValue)
        #expect(manager.frequentBackgroundLocationDistanceFilter == SettingsDefaultValues.frequentBackgroundLocationDistanceFilter)
        #expect(manager.frequentBackgroundLocationUpdatesExpiresAt == now.addingTimeInterval(7_200))
        #expect(!manager.refreshFromUserDefaultsForAppActivation(now: now))
    }

    @Test("Location diagnostics log is opt-in, persistent, capped, and exports rounded locations")
    @MainActor
    func locationDiagnosticsLogIsOptInPersistentCappedAndExportsRoundedLocations() throws {
        let suiteName = "LocationDiagnosticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("diagnostics.json")

        let store = LocationDiagnosticsLogStore(userDefaults: defaults, fileURL: fileURL, maxEntries: 2)
        #expect(!store.isEnabled)
        store.append(
            level: .info,
            event: "disabled",
            summary: "Disabled log",
            result: "ignored"
        )
        #expect(store.entries.isEmpty)

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 52.1234567, longitude: 13.9876543),
            altitude: 0,
            horizontalAccuracy: 12.34,
            verticalAccuracy: 8,
            course: -1,
            speed: 3.2,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )

        store.setEnabled(true)
        store.append(level: .info, event: "first", summary: "First", result: "stored")
        store.append(level: .warning, event: "second", summary: "Second", result: "stored")
        store.append(
            level: .error,
            event: "third",
            summary: "Third",
            result: "stored",
            context: LocationDiagnosticsLogStore.roundedLocationContext(location)
        )

        #expect(store.entries.map(\.event) == ["second", "third"])

        let reloadedStore = LocationDiagnosticsLogStore(userDefaults: defaults, fileURL: fileURL, maxEntries: 2)
        #expect(reloadedStore.isEnabled)
        #expect(reloadedStore.entries.map(\.event) == ["second", "third"])

        let exportData = try reloadedStore.exportData(appVersion: "9.9", build: "42")
        let exportedString = try #require(String(data: exportData, encoding: .utf8))
        #expect(!exportedString.localizedCaseInsensitiveContains("devicekey"))
        let exportObject = try #require(JSONSerialization.jsonObject(with: exportData) as? [String: Any])
        #expect(exportObject["appVersion"] as? String == "9.9")
        #expect(exportObject["build"] as? String == "42")
        #expect(exportObject["entryCount"] as? Int == 2)
        let entries = try #require(exportObject["entries"] as? [[String: Any]])
        let context = try #require(entries.last?["context"] as? [String: Any])
        #expect(context["locationLatitude"] as? Double == 52.1235)
        #expect(context["locationLongitude"] as? Double == 13.9877)
        #expect(exportObject["schemaVersion"] as? Int == LocationDiagnosticsLogStore.schemaVersion)
        #expect(exportObject["droppedEntryCount"] as? Int == 1)
        #expect((exportObject["coalescedCounts"] as? [[String: Any]])?.isEmpty == true)
    }

    @Test("Location diagnostics keeps critical entries while coalescing noisy updates")
    @MainActor
    func locationDiagnosticsKeepsCriticalEntriesWhileCoalescingNoisyUpdates() throws {
        let suiteName = "LocationDiagnosticsCoalescingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationDiagnosticsCoalescingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("diagnostics.json")

        let store = LocationDiagnosticsLogStore(
            userDefaults: defaults,
            fileURL: fileURL,
            maxEntries: 3,
            coalescedCountLimit: 10
        )
        store.setEnabled(true)
        store.append(level: .warning, event: "backgroundTrackingGap", summary: "Gap", result: "suspicious")
        for index in 1...120 {
            store.appendCoalesced(
                level: .info,
                event: "locationCallback",
                summary: "Callback",
                result: "processing",
                coalescingKey: "locationCallback|background|frequent",
                context: ["index": .integer(index)],
                sampleEvery: 25
            )
        }

        #expect(store.entries.contains { $0.event == "backgroundTrackingGap" })
        #expect(store.entries.count <= 3)
        #expect(store.coalescedCounts.count == 1)
        #expect(store.coalescedCounts.first?.count == 120)

        let exportData = try store.exportData(appVersion: "9.9", build: "42")
        let exportObject = try #require(JSONSerialization.jsonObject(with: exportData) as? [String: Any])
        let coalescedCounts = try #require(exportObject["coalescedCounts"] as? [[String: Any]])
        #expect(coalescedCounts.first?["count"] as? Int == 120)
        #expect((exportObject["droppedEntryCount"] as? Int ?? 0) > 0)
        #expect(exportObject["oldestEntryAt"] != nil)
    }

    @Test("Location diagnostics loads legacy entry array files")
    @MainActor
    func locationDiagnosticsLoadsLegacyEntryArrayFiles() throws {
        let suiteName = "LocationDiagnosticsLegacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocationDiagnosticsLegacyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fileURL = directoryURL.appendingPathComponent("diagnostics.json")

        let legacyJSON = """
        [
          {
            "id": "00000000-0000-0000-0000-000000000001",
            "timestamp": "2026-06-05T12:00:00Z",
            "level": "info",
            "event": "legacyEvent",
            "summary": "Legacy",
            "result": "stored",
            "reason": null,
            "checks": [],
            "context": {}
          }
        ]
        """
        try legacyJSON.data(using: .utf8)?.write(to: fileURL, options: .atomic)

        let store = LocationDiagnosticsLogStore(userDefaults: defaults, fileURL: fileURL)
        #expect(store.entries.count == 1)
        #expect(store.entries.first?.event == "legacyEvent")
        #expect(store.entries.first?.retentionClass == .critical)
        #expect(store.coalescedCounts.isEmpty)
    }

    private func loadStringCatalog() throws -> [String: Any] {
        let data = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/Assets/Localizable.xcstrings"))
        let jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(jsonObject["strings"] as? [String: Any])
    }

    private func loadSettingsBundleStrings(locale: String) throws -> [String: String] {
        let url = repoRootURL().appendingPathComponent("miataru/SettingsManagers/App Settings/Settings.bundle/\(locale).lproj/Root.strings")
        let dictionary = try #require(NSDictionary(contentsOf: url) as? [String: String], "Unable to parse Settings.bundle strings for locale \(locale)")
        return dictionary
    }

    private func loadSettingsBundleSpecifiers() throws -> [[String: Any]] {
        let url = repoRootURL().appendingPathComponent("miataru/SettingsManagers/App Settings/Settings.bundle/Root.plist")
        let data = try Data(contentsOf: url)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return try #require(plist["PreferenceSpecifiers"] as? [[String: Any]])
    }

    private func repoRootURL() -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent() // miataruTests
            .deletingLastPathComponent() // project root folder in repo
    }
}
