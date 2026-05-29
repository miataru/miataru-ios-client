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

    @Test("Settings localization keys exist for all app locales")
    func settingsLocalizationKeysExistForAllLocales() throws {
        let requiredKeys = [
            "advanced_options",
            "advanced_options_and_tracking_status",
            "activity_type_accuracy_settings_title",
            "activity_type_tracking_accuracy_title",
            "activity_type_accuracy_explanation",
            "location_sensitivity_title",
            "location_sensitivity_explanation",
            "background_location_updates_section_title",
            "frequent_background_location_updates_title",
            "frequent_background_location_updates_explanation",
            "frequent_background_location_updates_central_explanation",
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
            "background_location_distance_filter_100m_explanation",
            "background_location_distance_filter_50m_explanation",
            "background_location_distance_filter_25m_explanation",
            "frequent_background_location_updates_duration_title",
            "frequent_background_location_updates_duration_unlimited",
            "frequent_background_location_duration_1h_explanation",
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
            "tracking_mode_frequent_background_updates_format",
            "background_tracking_mode_title",
            "background_tracking_expires_at_label",
            "background_tracking_mode_frequent_format",
            "background_tracking_mode_significant_change",
            "background_tracking_expires_never",
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
            "4hours",
            "100m",
            "50m",
            "25m",
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
    }

    @Test("Frequent background location update settings normalize and expire as expected")
    func frequentBackgroundLocationUpdateSettingsNormalizeAndExpire() {
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(100) == 100)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(50) == 50)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(25) == 25)
        #expect(FrequentBackgroundLocationDistanceFilter.normalized(10) == SettingsDefaultValues.frequentBackgroundLocationDistanceFilter)

        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(FrequentBackgroundLocationUpdateDuration.oneHour.rawValue) == 3_600)
        #expect(FrequentBackgroundLocationUpdateDuration.normalizedRawValue(123) == SettingsDefaultValues.frequentBackgroundLocationUpdateDuration)

        let startDate = Date(timeIntervalSince1970: 1_000)
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

    @Test("Background location configuration preserves significant-change default")
    func backgroundLocationConfigurationPreservesSignificantChangeDefault() {
        let defaultConfiguration = LocationManager.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 25
        )
        #expect(defaultConfiguration.usesSignificantChangeMonitoring)
        #expect(defaultConfiguration.distanceFilter == kCLDistanceFilterNone)

        let frequentConfiguration = LocationManager.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50
        )
        #expect(!frequentConfiguration.usesSignificantChangeMonitoring)
        #expect(frequentConfiguration.distanceFilter == 50)
        #expect(frequentConfiguration.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)

        let normalizedConfiguration = LocationManager.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 10
        )
        #expect(!normalizedConfiguration.usesSignificantChangeMonitoring)
        #expect(normalizedConfiguration.distanceFilter == CLLocationDistance(SettingsDefaultValues.frequentBackgroundLocationDistanceFilter))
    }

    @Test("Location tracking mode resolver keeps foreground, navigation, and background policies distinct")
    func locationTrackingModeResolverKeepsForegroundNavigationAndBackgroundPoliciesDistinct() {
        #expect(LocationManager.resolvedTrackingMode(
            isTracking: false,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: true
        ) == .stopped)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .denied,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: true
        ) == .stopped)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: true
        ) == .foregroundHighAccuracy)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 25,
            hasNavigationLocationSession: true
        ) == .backgroundSignificantChange)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .stopped)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundFrequent(distanceFilter: 50, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 10,
            hasNavigationLocationSession: true
        ) == .backgroundFrequent(
            distanceFilter: CLLocationDistance(SettingsDefaultValues.frequentBackgroundLocationDistanceFilter),
            desiredAccuracy: kCLLocationAccuracyHundredMeters
        ))

        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundSignificantChange)
    }

    @Test("Location service command plan keeps primary recovery anchor separate from frequent updates")
    func locationServiceCommandPlanKeepsPrimaryRecoveryAnchorSeparateFromFrequentUpdates() {
        let frequentPlan = LocationManager.locationServiceCommandPlan(
            for: .backgroundFrequent(
                distanceFilter: 50,
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters
            ),
            shouldMaintainRecoveryAnchor: true
        )
        #expect(frequentPlan.primary == [
            .stopUpdatingLocation,
            .startMonitoringSignificantLocationChanges
        ])
        #expect(frequentPlan.secondary == [
            .stopMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: true,
                distanceFilter: 50,
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters
            )
        ])

        let standardPlan = LocationManager.locationServiceCommandPlan(
            for: .backgroundSignificantChange,
            shouldMaintainRecoveryAnchor: true
        )
        #expect(standardPlan.primary == [
            .stopUpdatingLocation,
            .startMonitoringSignificantLocationChanges
        ])
        #expect(standardPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let foregroundPlan = LocationManager.locationServiceCommandPlan(
            for: .foregroundHighAccuracy,
            shouldMaintainRecoveryAnchor: true
        )
        #expect(foregroundPlan.primary == [
            .startMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: false,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyBestForNavigation
            )
        ])
        #expect(foregroundPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let foregroundWhenInUsePlan = LocationManager.locationServiceCommandPlan(
            for: .foregroundHighAccuracy,
            shouldMaintainRecoveryAnchor: false
        )
        #expect(foregroundWhenInUsePlan.primary == [
            .stopMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: false,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyBestForNavigation
            )
        ])
        #expect(foregroundWhenInUsePlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let stoppedPlan = LocationManager.locationServiceCommandPlan(
            for: .stopped,
            shouldMaintainRecoveryAnchor: false
        )
        #expect(stoppedPlan.primary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])
        #expect(stoppedPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])
    }

    @Test("Background lifecycle context keeps frequent mode active even before UIKit reports background")
    func backgroundLifecycleContextKeepsFrequentModeActiveBeforeUIKitStateCatchesUp() {
        let forcedBackgroundState = LocationManager.effectiveApplicationStateForTracking(
            currentState: .active,
            context: .forceBackground
        )
        #expect(forcedBackgroundState == .background)
        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: forcedBackgroundState,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundFrequent(distanceFilter: 50, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))

        let forcedForegroundState = LocationManager.effectiveApplicationStateForTracking(
            currentState: .background,
            context: .forceForeground
        )
        #expect(forcedForegroundState == .active)
        #expect(LocationManager.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: forcedForegroundState,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)
    }

    @Test("Significant-change recovery anchor is kept only for active Always-authorized tracking")
    func significantChangeRecoveryAnchorRequiresActiveAlwaysAuthorizedTracking() {
        #expect(LocationManager.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))

        #expect(!LocationManager.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationManager.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedWhenInUse,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationManager.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: true
        ))
    }

    @Test("Tracking is restored after launch only when the user setting still permits it")
    func trackingRestoreAfterLaunchRequiresEnabledTrackingWithoutAuthBlock() {
        #expect(LocationManager.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationManager.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: false,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationManager.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: true
        ))
        #expect(AppDelegate.didLaunchForLocation([.location: true]))
        #expect(!AppDelegate.didLaunchForLocation(nil))
        #expect(AppDelegate.shouldRestoreLocationLaunch([.location: true], didRestore: false))
        #expect(!AppDelegate.shouldRestoreLocationLaunch([.location: true], didRestore: true))
        #expect(!AppDelegate.shouldRestoreLocationLaunch(nil, didRestore: false))
    }

    @Test("Duplicate location callbacks are suppressed before upload")
    func duplicateLocationCallbacksAreSuppressedBeforeUpload() throws {
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp
        )
        let sameCallback = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 12,
            horizontalAccuracy: 3,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp
        )
        let laterCallback = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp.addingTimeInterval(1)
        )

        let key = try #require(LocationManager.locationSubmissionDeduplicationKey(for: location))
        #expect(LocationManager.shouldSubmitLocationForUpload(location, lastSubmittedKey: nil))
        #expect(!LocationManager.shouldSubmitLocationForUpload(sameCallback, lastSubmittedKey: key))
        #expect(LocationManager.shouldSubmitLocationForUpload(laterCallback, lastSubmittedKey: key))
    }

    @Test("Background battery threshold only disables frequent mode when active and known")
    func backgroundBatteryThresholdOnlyDisablesFrequentModeWhenActiveAndKnown() {
        #expect(LocationManager.batteryPercent(from: 0.301) == 30)
        #expect(LocationManager.batteryPercent(from: -1) == nil)

        #expect(LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 30,
            thresholdPercent: 30
        ))
        #expect(LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 29,
            thresholdPercent: 25
        ))
        #expect(!LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 31,
            thresholdPercent: 30
        ))
        #expect(!LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: false,
            batteryPercent: 20,
            thresholdPercent: 30
        ))
        #expect(!LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: nil,
            thresholdPercent: 30
        ))
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
