/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SettingsConfiguration.swift
 * miataru
 *
 * Created by Codex on 14.03.26.
 */

import Foundation
import CoreLocation

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
    static let smartFrequentBackgroundLocationUpdatesEnabled = "smart_frequent_background_location_updates_enabled"
    static let smartFrequentBackgroundSpeedThresholdKmh = "smart_frequent_background_speed_threshold_kmh"
    static let smartFrequentBackgroundSpeedDetectionMode = "smart_frequent_background_speed_detection_mode"
    static let smartFrequentBackgroundInactivityWindow = "smart_frequent_background_inactivity_window"
    static let smartFrequentBackgroundModeChangeNotificationsEnabled = "smart_frequent_background_mode_change_notifications_enabled"
    static let frequentBackgroundLocationUpdatesEnabled = "frequent_background_location_updates_enabled"
    static let frequentBackgroundLocationDistanceFilter = "frequent_background_location_distance_filter"
    static let frequentBackgroundLocationUpdateDuration = "frequent_background_location_update_duration"
    static let frequentBackgroundLocationUpdatesExpiresAt = "frequent_background_location_updates_expires_at"
    static let frequentBackgroundBatteryAutoDisableLevel = "frequent_background_battery_auto_disable_level"
    static let frequentBackgroundLocationDeliveryMode = "frequent_background_location_delivery_mode"
    static let frequentBackgroundVisitorCheckInterval = "frequent_background_visitor_check_interval"
    static let autoRefreshDeviceList = "auto_refresh_device_list"
    static let unknownVisitorAlertsEnabled = "unknown_visitor_alerts_enabled"
    static let showCurrentSpeedOnMap = "show_current_speed_on_map"
    static let showOffscreenArrowsForOtherDevices = "show_offscreen_arrows_for_other_devices"
    static let showRouteProgress = "show_route_progress"
    static let locationUpdateOutboxRetentionMode = "location_update_outbox_retention_mode"
    static let locationUpdateOutboxMaxItems = "location_update_outbox_max_items"
    static let locationDiagnosticsLoggingEnabled = "location_diagnostics_logging_enabled"
    static let locationDiagnosticsSourceID = "location_diagnostics_source_id"
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
    static let locationDataRetentionTime = 30
    static let mapType = 1
    static let mapUpdateInterval = 30
    static let outsideMapUpdateInterval = 60
    static let mapZoomLevel = 5
    static let historyNumberOfDays = 10_000_000
    static let locationActivityType = 0
    static let locationSensitivityLevel = 2
    static let smartFrequentBackgroundLocationUpdatesEnabled = false
    static let smartFrequentBackgroundSpeedThresholdKmh = 10
    static let smartFrequentBackgroundSpeedDetectionMode = SmartFrequentBackgroundSpeedDetectionMode.hybrid.rawValue
    static let smartFrequentBackgroundInactivityWindow = SmartFrequentBackgroundInactivityWindow.tenMinutes.rawValue
    static let smartFrequentBackgroundModeChangeNotificationsEnabled = false
    static let frequentBackgroundLocationUpdatesEnabled = false
    static let frequentBackgroundLocationDistanceFilter = 100
    static let frequentBackgroundLocationUpdateDuration = FrequentBackgroundLocationUpdateDuration.fourHours.rawValue
    static let frequentBackgroundBatteryAutoDisableLevel = 30
    static let frequentBackgroundLocationDeliveryMode = FrequentBackgroundLocationDeliveryMode.immediate.rawValue
    static let frequentBackgroundVisitorCheckInterval = FrequentBackgroundVisitorCheckInterval.tenMinutes.rawValue
    static let autoRefreshDeviceList = true
    static let unknownVisitorAlertsEnabled = false
    static let showCurrentSpeedOnMap = true
    static let showOffscreenArrowsForOtherDevices = true
    static let showRouteProgress = true
    static let locationUpdateOutboxRetentionMode = LocationUpdateOutboxRetentionMode.twentyFourHours.rawValue
    static let locationUpdateOutboxMaxItems = 500
    static let locationDiagnosticsLoggingEnabled = false
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
        SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled: smartFrequentBackgroundLocationUpdatesEnabled,
        SettingsKeys.smartFrequentBackgroundSpeedThresholdKmh: String(smartFrequentBackgroundSpeedThresholdKmh),
        SettingsKeys.smartFrequentBackgroundSpeedDetectionMode: String(smartFrequentBackgroundSpeedDetectionMode),
        SettingsKeys.smartFrequentBackgroundInactivityWindow: String(smartFrequentBackgroundInactivityWindow),
        SettingsKeys.smartFrequentBackgroundModeChangeNotificationsEnabled: smartFrequentBackgroundModeChangeNotificationsEnabled,
        SettingsKeys.frequentBackgroundLocationUpdatesEnabled: frequentBackgroundLocationUpdatesEnabled,
        SettingsKeys.frequentBackgroundLocationDistanceFilter: String(frequentBackgroundLocationDistanceFilter),
        SettingsKeys.frequentBackgroundLocationUpdateDuration: String(frequentBackgroundLocationUpdateDuration),
        SettingsKeys.frequentBackgroundBatteryAutoDisableLevel: String(frequentBackgroundBatteryAutoDisableLevel),
        SettingsKeys.frequentBackgroundLocationDeliveryMode: String(frequentBackgroundLocationDeliveryMode),
        SettingsKeys.frequentBackgroundVisitorCheckInterval: String(frequentBackgroundVisitorCheckInterval),
        SettingsKeys.autoRefreshDeviceList: autoRefreshDeviceList,
        SettingsKeys.unknownVisitorAlertsEnabled: unknownVisitorAlertsEnabled,
        SettingsKeys.showCurrentSpeedOnMap: showCurrentSpeedOnMap,
        SettingsKeys.showOffscreenArrowsForOtherDevices: showOffscreenArrowsForOtherDevices,
        SettingsKeys.showRouteProgress: showRouteProgress,
        SettingsKeys.locationUpdateOutboxRetentionMode: String(locationUpdateOutboxRetentionMode),
        SettingsKeys.locationUpdateOutboxMaxItems: String(locationUpdateOutboxMaxItems),
        SettingsKeys.locationDiagnosticsLoggingEnabled: locationDiagnosticsLoggingEnabled,
        SettingsKeys.reverseGeocodingThresholdMeters: String(reverseGeocodingThresholdMeters),
        SettingsKeys.navigationTransportType: String(navigationTransportType),
        SettingsKeys.pulsingMapMarkers: pulsingMapMarkers,
        SettingsKeys.automaticRouteUpdateDuringNavigation: automaticRouteUpdateDuringNavigation,
        SettingsKeys.allowedDeviceListEnabled: allowedDeviceListEnabled,
    ]
}

struct TrackingPermissionSettingsVisibility: Equatable {
    let showsTrackingDependentSettings: Bool
    let showsAlwaysPermissionNotice: Bool
}

enum TrackingPermissionSettingsGate {
    static func visibility(
        trackAndReportLocation: Bool,
        authorizationStatus: CLAuthorizationStatus
    ) -> TrackingPermissionSettingsVisibility {
        guard trackAndReportLocation else {
            return TrackingPermissionSettingsVisibility(
                showsTrackingDependentSettings: false,
                showsAlwaysPermissionNotice: false
            )
        }

        let hasAlwaysAuthorization = authorizationStatus == .authorizedAlways
        return TrackingPermissionSettingsVisibility(
            showsTrackingDependentSettings: hasAlwaysAuthorization,
            showsAlwaysPermissionNotice: !hasAlwaysAuthorization
        )
    }
}

enum SmartFrequentBackgroundSpeedThreshold {
    static let allowedValues = [2, 5, 10, 15, 20, 30]

    static func normalized(_ value: Int) -> Int {
        allowedValues.contains(value) ? value : SettingsDefaultValues.smartFrequentBackgroundSpeedThresholdKmh
    }
}

enum SmartFrequentBackgroundSpeedDetectionMode: Int, CaseIterable {
    case hybrid = 0
    case gpsOnly = 1

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.smartFrequentBackgroundSpeedDetectionMode
    }
}

enum SmartFrequentBackgroundInactivityWindow: Int, CaseIterable {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800

    var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.smartFrequentBackgroundInactivityWindow
    }
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

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.locationUpdateOutboxRetentionMode
    }
}

enum FrequentBackgroundLocationUpdateDuration: Int, CaseIterable {
    case unlimited = 0
    case oneHour = 3_600
    case twoHours = 7_200
    case threeHours = 10_800
    case fourHours = 14_400
    case twelveHours = 43_200
    case twentyFourHours = 86_400

    var timeInterval: TimeInterval? {
        self == .unlimited ? nil : TimeInterval(rawValue)
    }

    func expirationDate(from startDate: Date) -> Date? {
        guard let timeInterval else { return nil }
        return startDate.addingTimeInterval(timeInterval)
    }

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.frequentBackgroundLocationUpdateDuration
    }
}

enum FrequentBackgroundLocationDistanceFilter {
    static let allowedValues = [100, 50, 25, 10, 5]

    static func normalized(_ value: Int) -> Int {
        allowedValues.contains(value) ? value : SettingsDefaultValues.frequentBackgroundLocationDistanceFilter
    }
}

enum FrequentBackgroundBatteryAutoDisableLevel {
    static let allowedValues = [10, 20, 30, 40, 50]

    static func normalized(_ value: Int) -> Int {
        allowedValues.contains(value) ? value : SettingsDefaultValues.frequentBackgroundBatteryAutoDisableLevel
    }
}

enum FrequentBackgroundLocationDeliveryMode: Int, CaseIterable {
    case immediate = 0
    case everyThirtySeconds = 30
    case everyMinute = 60
    case everyFiveMinutes = 300
    case everyTenMinutes = 600

    var delay: TimeInterval? {
        self == .immediate ? nil : TimeInterval(rawValue)
    }

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.frequentBackgroundLocationDeliveryMode
    }
}

enum FrequentBackgroundVisitorCheckInterval: Int, CaseIterable {
    case everyUpdate = 0
    case everyMinute = 60
    case everyFiveMinutes = 300
    case tenMinutes = 600
    case everyThirtyMinutes = 1_800
    case everyHour = 3_600

    var minimumInterval: TimeInterval? {
        self == .everyUpdate ? nil : TimeInterval(rawValue)
    }

    static func normalizedRawValue(_ value: Int) -> Int {
        Self(rawValue: value)?.rawValue ?? SettingsDefaultValues.frequentBackgroundVisitorCheckInterval
    }
}

enum SettingsMigration {
    static let existingInstallDefaultsV315Marker = "settings_existing_install_defaults_v315_applied"
    static let smartFrequentBackgroundV1Marker = "settings_smart_frequent_background_v1_applied"

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

    static func applySmartFrequentBackgroundMigrationIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: smartFrequentBackgroundV1Marker) else { return }
        defer {
            defaults.set(true, forKey: smartFrequentBackgroundV1Marker)
        }

        normalizeSmartFrequentBackgroundPrerequisiteIfNeeded(defaults: defaults)
    }

    static func normalizeSmartFrequentBackgroundPrerequisiteIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled) != nil,
              defaults.bool(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled) else {
            return
        }

        defaults.set(true, forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
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
