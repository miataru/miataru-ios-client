/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SettingsConfiguration.swift
 * miataru
 *
 * Created by Codex on 14.03.26.
 */

import Foundation

enum SettingsKeys {
    static let mapType = "map_type"
    static let disableDeviceAutolock = "disable_device_autolock_while_in_foreground"
    static let preventScreenRotation = "prevent_screen_rotation"
    static let mapUpdateInterval = "map_update_interval"
    static let outsideMapUpdateInterval = "outside_map_update_interval"
    static let mapZoomLevel = "map_zoom_level"
    static let indicateAccuracyOnMap = "indicate_accuracy_on_map"
    static let groupsZoomToFit = "groups_zoom_to_fit"
    static let miataruServerURL = "miataru_server_url"
    static let trackAndReportLocation = "track_and_report_location"
    static let trackAndReportLocationDisabledByDeviceKeyAuth = "track_and_report_location_disabled_by_device_key_auth"
    static let saveLocationHistoryOnServer = "save_location_history_on_server"
    static let locationDataRetentionTime = "location_data_retention_time"
    static let historyNumberOfDays = "history_number_of_days"
    static let locationActivityType = "location_activity_type"
    static let locationSensitivityLevel = "location_sensitivity_level"
    static let autoRefreshDeviceList = "auto_refresh_device_list"
    static let unknownVisitorAlertsEnabled = "unknown_visitor_alerts_enabled"
    static let showCurrentSpeedOnMap = "show_current_speed_on_map"
    static let showOffscreenArrowsForOtherDevices = "show_offscreen_arrows_for_other_devices"
    static let showRouteProgress = "show_route_progress"
    static let locationUpdateOutboxRetentionMode = "location_update_outbox_retention_mode"
    static let locationUpdateOutboxMaxItems = "location_update_outbox_max_items"
    static let lastOpenedDeviceID = "last_opened_device_id"
    static let reverseGeocodingThresholdMeters = "reverse_geocoding_threshold_meters"
    static let navigationTransportType = "navigation_transport_type"
    static let pulsingMapMarkers = "pulsating_map_markers"
    static let automaticRouteUpdateDuringNavigation = "automatic_route_update_during_navigation"
    static let deviceKey = "device_key"
    static let deviceKeyLastChanged = "device_key_last_changed"
    static let deviceKeyAuthBlocked = "device_key_auth_blocked"
    static let deviceKeyAuthBlockedKey = "device_key_auth_blocked_key"
    static let allowedDeviceListEnabled = "allowed_device_list_enabled"
}

enum SettingsDefaultValues {
    static let disableDeviceAutolock = false
    static let preventScreenRotation = false
    static let indicateAccuracyOnMap = true
    static let groupsZoomToFit = true
    static let miataruServerURL = "https://service.miataru.com"
    static let trackAndReportLocation = false
    static let trackAndReportLocationDisabledByDeviceKeyAuth = false
    static let saveLocationHistoryOnServer = false
    static let locationDataRetentionTime = 1440
    static let mapType = 1
    static let mapUpdateInterval = 30
    static let outsideMapUpdateInterval = 60
    static let mapZoomLevel = 5
    static let historyNumberOfDays = 10_000_000
    static let locationActivityType = 0
    static let locationSensitivityLevel = 2
    static let autoRefreshDeviceList = true
    static let unknownVisitorAlertsEnabled = false
    static let showCurrentSpeedOnMap = true
    static let showOffscreenArrowsForOtherDevices = true
    static let showRouteProgress = true
    static let locationUpdateOutboxRetentionMode = LocationUpdateOutboxRetentionMode.twentyFourHours.rawValue
    static let locationUpdateOutboxMaxItems = 500
    static let reverseGeocodingThresholdMeters = 1000
    static let navigationTransportType = 2
    static let pulsingMapMarkers = true
    static let automaticRouteUpdateDuringNavigation = true
    static let allowedDeviceListEnabled = false

    static let registrations: [String: Any] = [
        SettingsKeys.mapType: String(mapType),
        SettingsKeys.disableDeviceAutolock: disableDeviceAutolock,
        SettingsKeys.preventScreenRotation: preventScreenRotation,
        SettingsKeys.mapUpdateInterval: String(mapUpdateInterval),
        SettingsKeys.outsideMapUpdateInterval: String(outsideMapUpdateInterval),
        SettingsKeys.mapZoomLevel: String(mapZoomLevel),
        SettingsKeys.indicateAccuracyOnMap: indicateAccuracyOnMap,
        SettingsKeys.groupsZoomToFit: groupsZoomToFit,
        SettingsKeys.miataruServerURL: miataruServerURL,
        SettingsKeys.trackAndReportLocation: trackAndReportLocation,
        SettingsKeys.trackAndReportLocationDisabledByDeviceKeyAuth: trackAndReportLocationDisabledByDeviceKeyAuth,
        SettingsKeys.saveLocationHistoryOnServer: saveLocationHistoryOnServer,
        SettingsKeys.locationDataRetentionTime: String(locationDataRetentionTime),
        SettingsKeys.historyNumberOfDays: String(historyNumberOfDays),
        SettingsKeys.locationActivityType: locationActivityType,
        SettingsKeys.locationSensitivityLevel: locationSensitivityLevel,
        SettingsKeys.autoRefreshDeviceList: autoRefreshDeviceList,
        SettingsKeys.unknownVisitorAlertsEnabled: unknownVisitorAlertsEnabled,
        SettingsKeys.showCurrentSpeedOnMap: showCurrentSpeedOnMap,
        SettingsKeys.showOffscreenArrowsForOtherDevices: showOffscreenArrowsForOtherDevices,
        SettingsKeys.showRouteProgress: showRouteProgress,
        SettingsKeys.locationUpdateOutboxRetentionMode: String(locationUpdateOutboxRetentionMode),
        SettingsKeys.locationUpdateOutboxMaxItems: String(locationUpdateOutboxMaxItems),
        SettingsKeys.reverseGeocodingThresholdMeters: String(reverseGeocodingThresholdMeters),
        SettingsKeys.navigationTransportType: String(navigationTransportType),
        SettingsKeys.pulsingMapMarkers: pulsingMapMarkers,
        SettingsKeys.automaticRouteUpdateDuringNavigation: automaticRouteUpdateDuringNavigation,
        SettingsKeys.allowedDeviceListEnabled: allowedDeviceListEnabled,
    ]
}

enum LocationUpdateOutboxRetentionMode: Int {
    case twentyFourHours = 0
    case sevenDays = 1
    case thirtyDays = 2
    case unlimited = 3

    var timeToLive: TimeInterval? {
        switch self {
        case .twentyFourHours:
            return 24 * 60 * 60
        case .sevenDays:
            return 7 * 24 * 60 * 60
        case .thirtyDays:
            return 30 * 24 * 60 * 60
        case .unlimited:
            return nil
        }
    }
}

enum SettingsMigration {
    static let existingInstallDefaultsV315Marker = "settings_existing_install_defaults_v315_applied"

    private static let onboardingCompletedKey = "hasCompletedOnboarding"
    private static let postUpdateOnboardingKey = "hasShownPostUpdateOnboarding"

    private static let migratedBooleanKeys = [
        SettingsKeys.automaticRouteUpdateDuringNavigation,
        SettingsKeys.showRouteProgress,
        SettingsKeys.groupsZoomToFit,
        SettingsKeys.autoRefreshDeviceList,
        SettingsKeys.showCurrentSpeedOnMap,
        SettingsKeys.indicateAccuracyOnMap,
        SettingsKeys.showOffscreenArrowsForOtherDevices,
        SettingsKeys.pulsingMapMarkers,
    ]

    static func applyExistingInstallDefaultsIfNeeded(defaults: UserDefaults = .standard,
                                                     skipForFreshUITestReset: Bool = false) {
        guard !defaults.bool(forKey: existingInstallDefaultsV315Marker) else { return }
        defer {
            defaults.set(true, forKey: existingInstallDefaultsV315Marker)
        }

        guard !skipForFreshUITestReset,
              shouldApplyExistingInstallDefaults(defaults: defaults) else {
            return
        }

        for key in migratedBooleanKeys {
            defaults.set(true, forKey: key)
        }
    }

    static func shouldApplyExistingInstallDefaults(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: onboardingCompletedKey)
            || defaults.bool(forKey: postUpdateOnboardingKey)
            || defaults.object(forKey: SettingsKeys.trackAndReportLocation) != nil
            || defaults.object(forKey: SettingsKeys.miataruServerURL) != nil
            || defaults.object(forKey: SettingsKeys.deviceKey) != nil
            || defaults.object(forKey: SettingsKeys.allowedDeviceListEnabled) != nil
    }
}
