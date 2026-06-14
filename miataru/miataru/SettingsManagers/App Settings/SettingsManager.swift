/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * SettingsManager.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import Combine

class SettingsManager: ObservableObject {
    private let defaults: UserDefaults
    private var isApplyingExternalDefaultsRefresh = false
    
    // MARK: - Properties
    @Published var disableDeviceAutolock: Bool {
        didSet { defaults.set(disableDeviceAutolock, forKey: SettingsKeys.disableDeviceAutolock) }
    }
    @Published var preventScreenRotation: Bool {
        didSet { defaults.set(preventScreenRotation, forKey: SettingsKeys.preventScreenRotation) }
    }
    @Published var indicateAccuracyOnMap: Bool {
        didSet { defaults.set(indicateAccuracyOnMap, forKey: SettingsKeys.indicateAccuracyOnMap) }
    }
    @Published var groupsZoomToFit: Bool {
        didSet { defaults.set(groupsZoomToFit, forKey: SettingsKeys.groupsZoomToFit) }
    }
    @Published var miataruServerURL: String {
        didSet {
            defaults.set(miataruServerURL, forKey: SettingsKeys.miataruServerURL)
            WidgetDataSyncCoordinator.syncWidgetConfig(
                serverURL: miataruServerURL,
                deviceIDs: KnownDeviceStore.shared.devices.map { $0.DeviceID },
                ownDeviceID: thisDeviceIDManager.shared.deviceID,
                ownDeviceKey: deviceKey
            )
        }
    }
    @Published var trackAndReportLocation: Bool {
        didSet { 
            defaults.set(trackAndReportLocation, forKey: SettingsKeys.trackAndReportLocation)
            // Check location permissions when tracking is enabled
            if trackAndReportLocation && !isApplyingExternalDefaultsRefresh {
                checkAndRequestLocationPermissions()
            }
        }
    }
    @Published var trackAndReportLocationDisabledByDeviceKeyAuth: Bool {
        didSet { defaults.set(trackAndReportLocationDisabledByDeviceKeyAuth, forKey: SettingsKeys.trackAndReportLocationDisabledByDeviceKeyAuth) }
    }
    @Published var saveLocationHistoryOnServer: Bool {
        didSet { defaults.set(saveLocationHistoryOnServer, forKey: SettingsKeys.saveLocationHistoryOnServer) }
    }
    @Published var locationDataRetentionTime: Int {
        didSet { defaults.set(String(locationDataRetentionTime), forKey: SettingsKeys.locationDataRetentionTime) }
    }
    @Published var mapType: Int {
        didSet { defaults.set(String(mapType), forKey: SettingsKeys.mapType) }
    }
    @Published var mapUpdateInterval: Int {
        didSet { defaults.set(String(mapUpdateInterval), forKey: SettingsKeys.mapUpdateInterval) }
    }
    @Published var outsideMapUpdateInterval: Int {
        didSet { defaults.set(String(outsideMapUpdateInterval), forKey: SettingsKeys.outsideMapUpdateInterval) }
    }
    @Published var mapZoomLevel: Int {
        didSet { defaults.set(String(mapZoomLevel), forKey: SettingsKeys.mapZoomLevel) }
    }
    @Published var historyNumberOfDays: Int {
        didSet { defaults.set(String(historyNumberOfDays), forKey: SettingsKeys.historyNumberOfDays) }
    }
    @Published var locationActivityType: Int {
        didSet { defaults.set(locationActivityType, forKey: SettingsKeys.locationActivityType) }
    }
    @Published var locationSensitivityLevel: Int {
        didSet { defaults.set(locationSensitivityLevel, forKey: SettingsKeys.locationSensitivityLevel) }
    }
    @Published var smartFrequentBackgroundLocationUpdatesEnabled: Bool {
        didSet {
            if !smartFrequentBackgroundLocationUpdatesEnabled,
               frequentBackgroundLocationUpdatesEnabled {
                smartFrequentBackgroundLocationUpdatesEnabled = true
                return
            }
            defaults.set(smartFrequentBackgroundLocationUpdatesEnabled, forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
        }
    }
    @Published var smartFrequentBackgroundSpeedThresholdKmh: Int {
        didSet {
            let normalizedValue = SmartFrequentBackgroundSpeedThreshold.normalized(smartFrequentBackgroundSpeedThresholdKmh)
            if smartFrequentBackgroundSpeedThresholdKmh != normalizedValue {
                smartFrequentBackgroundSpeedThresholdKmh = normalizedValue
                return
            }
            defaults.set(String(smartFrequentBackgroundSpeedThresholdKmh), forKey: SettingsKeys.smartFrequentBackgroundSpeedThresholdKmh)
        }
    }
    @Published var smartFrequentBackgroundSpeedDetectionMode: Int {
        didSet {
            let normalizedValue = SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(smartFrequentBackgroundSpeedDetectionMode)
            if smartFrequentBackgroundSpeedDetectionMode != normalizedValue {
                smartFrequentBackgroundSpeedDetectionMode = normalizedValue
                return
            }
            defaults.set(String(smartFrequentBackgroundSpeedDetectionMode), forKey: SettingsKeys.smartFrequentBackgroundSpeedDetectionMode)
        }
    }
    @Published var smartFrequentBackgroundInactivityWindow: Int {
        didSet {
            let normalizedValue = SmartFrequentBackgroundInactivityWindow.normalizedRawValue(smartFrequentBackgroundInactivityWindow)
            if smartFrequentBackgroundInactivityWindow != normalizedValue {
                smartFrequentBackgroundInactivityWindow = normalizedValue
                return
            }
            defaults.set(String(smartFrequentBackgroundInactivityWindow), forKey: SettingsKeys.smartFrequentBackgroundInactivityWindow)
        }
    }
    @Published var smartFrequentBackgroundModeChangeNotificationsEnabled: Bool {
        didSet {
            defaults.set(smartFrequentBackgroundModeChangeNotificationsEnabled, forKey: SettingsKeys.smartFrequentBackgroundModeChangeNotificationsEnabled)
        }
    }
    @Published var frequentBackgroundLocationUpdatesEnabled: Bool {
        didSet {
            if frequentBackgroundLocationUpdatesEnabled,
               !smartFrequentBackgroundLocationUpdatesEnabled {
                smartFrequentBackgroundLocationUpdatesEnabled = true
            }
            defaults.set(frequentBackgroundLocationUpdatesEnabled, forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)
            if frequentBackgroundLocationUpdatesEnabled {
                if !oldValue || frequentBackgroundLocationUpdatesExpiresAt == nil {
                    refreshFrequentBackgroundLocationUpdatesExpiration()
                }
            } else if frequentBackgroundLocationUpdatesExpiresAt != nil {
                frequentBackgroundLocationUpdatesExpiresAt = nil
            }
        }
    }
    @Published var frequentBackgroundLocationDistanceFilter: Int {
        didSet {
            let normalizedValue = FrequentBackgroundLocationDistanceFilter.normalized(frequentBackgroundLocationDistanceFilter)
            if frequentBackgroundLocationDistanceFilter != normalizedValue {
                frequentBackgroundLocationDistanceFilter = normalizedValue
                return
            }
            defaults.set(String(frequentBackgroundLocationDistanceFilter), forKey: SettingsKeys.frequentBackgroundLocationDistanceFilter)
        }
    }
    @Published var frequentBackgroundLocationUpdateDuration: Int {
        didSet {
            let normalizedValue = FrequentBackgroundLocationUpdateDuration.normalizedRawValue(frequentBackgroundLocationUpdateDuration)
            if frequentBackgroundLocationUpdateDuration != normalizedValue {
                frequentBackgroundLocationUpdateDuration = normalizedValue
                return
            }
            defaults.set(String(frequentBackgroundLocationUpdateDuration), forKey: SettingsKeys.frequentBackgroundLocationUpdateDuration)
            if frequentBackgroundLocationUpdatesEnabled {
                refreshFrequentBackgroundLocationUpdatesExpiration()
            }
        }
    }
    @Published var frequentBackgroundBatteryAutoDisableLevel: Int {
        didSet {
            let normalizedValue = FrequentBackgroundBatteryAutoDisableLevel.normalized(frequentBackgroundBatteryAutoDisableLevel)
            if frequentBackgroundBatteryAutoDisableLevel != normalizedValue {
                frequentBackgroundBatteryAutoDisableLevel = normalizedValue
                return
            }
            defaults.set(String(frequentBackgroundBatteryAutoDisableLevel), forKey: SettingsKeys.frequentBackgroundBatteryAutoDisableLevel)
        }
    }
    @Published var frequentBackgroundLocationUpdatesExpiresAt: Date? {
        didSet {
            if let frequentBackgroundLocationUpdatesExpiresAt {
                defaults.set(frequentBackgroundLocationUpdatesExpiresAt, forKey: SettingsKeys.frequentBackgroundLocationUpdatesExpiresAt)
            } else {
                defaults.removeObject(forKey: SettingsKeys.frequentBackgroundLocationUpdatesExpiresAt)
            }
        }
    }
    @Published var frequentBackgroundLocationDeliveryMode: Int {
        didSet {
            let normalizedValue = FrequentBackgroundLocationDeliveryMode.normalizedRawValue(frequentBackgroundLocationDeliveryMode)
            if frequentBackgroundLocationDeliveryMode != normalizedValue {
                frequentBackgroundLocationDeliveryMode = normalizedValue
                return
            }
            defaults.set(String(frequentBackgroundLocationDeliveryMode), forKey: SettingsKeys.frequentBackgroundLocationDeliveryMode)
        }
    }
    @Published var frequentBackgroundVisitorCheckInterval: Int {
        didSet {
            let normalizedValue = FrequentBackgroundVisitorCheckInterval.normalizedRawValue(frequentBackgroundVisitorCheckInterval)
            if frequentBackgroundVisitorCheckInterval != normalizedValue {
                frequentBackgroundVisitorCheckInterval = normalizedValue
                return
            }
            defaults.set(String(frequentBackgroundVisitorCheckInterval), forKey: SettingsKeys.frequentBackgroundVisitorCheckInterval)
        }
    }
    @Published var locationTrackingHealthReminderIntervalDays: Int {
        didSet {
            let normalizedValue = LocationTrackingHealthReminderInterval.normalizedRawValue(locationTrackingHealthReminderIntervalDays)
            if locationTrackingHealthReminderIntervalDays != normalizedValue {
                locationTrackingHealthReminderIntervalDays = normalizedValue
                return
            }
            defaults.set(String(locationTrackingHealthReminderIntervalDays), forKey: SettingsKeys.locationTrackingHealthReminderIntervalDays)
        }
    }
    @Published var autoRefreshDeviceList: Bool {
        didSet { defaults.set(autoRefreshDeviceList, forKey: SettingsKeys.autoRefreshDeviceList) }
    }
    @Published var unknownVisitorAlertsEnabled: Bool {
        didSet { defaults.set(unknownVisitorAlertsEnabled, forKey: SettingsKeys.unknownVisitorAlertsEnabled) }
    }
    @Published var unknownVisitorAlertsPermissionDenied: Bool = false
    @Published var showCurrentSpeedOnMap: Bool {
        didSet { defaults.set(showCurrentSpeedOnMap, forKey: SettingsKeys.showCurrentSpeedOnMap) }
    }
    @Published var showOffscreenArrowsForOtherDevices: Bool {
        didSet { defaults.set(showOffscreenArrowsForOtherDevices, forKey: SettingsKeys.showOffscreenArrowsForOtherDevices) }
    }
    // Removed: showOtherDevicesOnMap
    @Published var showRouteProgress: Bool {
        didSet { defaults.set(showRouteProgress, forKey: SettingsKeys.showRouteProgress) }
    }

    @Published var locationUpdateOutboxRetentionMode: Int {
        didSet { defaults.set(String(locationUpdateOutboxRetentionMode), forKey: SettingsKeys.locationUpdateOutboxRetentionMode) }
    }

    @Published var locationUpdateOutboxMaxItems: Int {
        didSet { defaults.set(String(locationUpdateOutboxMaxItems), forKey: SettingsKeys.locationUpdateOutboxMaxItems) }
    }

    @Published var locationDiagnosticsLoggingEnabled: Bool {
        didSet {
            defaults.set(locationDiagnosticsLoggingEnabled, forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
            Task { @MainActor in
                LocationDiagnosticsLogStore.shared.setEnabled(locationDiagnosticsLoggingEnabled)
            }
        }
    }

    var locationUpdateOutboxRetentionTimeToLive: TimeInterval? {
        let mode = LocationUpdateOutboxRetentionMode(rawValue: locationUpdateOutboxRetentionMode) ?? .twentyFourHours
        return mode.timeToLive
    }

    var smartFrequentBackgroundSpeedDetectionModeSelection: SmartFrequentBackgroundSpeedDetectionMode {
        SmartFrequentBackgroundSpeedDetectionMode(rawValue: smartFrequentBackgroundSpeedDetectionMode) ?? .hybrid
    }

    var smartFrequentBackgroundInactivityWindowSelection: SmartFrequentBackgroundInactivityWindow {
        SmartFrequentBackgroundInactivityWindow(rawValue: smartFrequentBackgroundInactivityWindow) ?? .tenMinutes
    }

    var frequentBackgroundLocationUpdateDurationMode: FrequentBackgroundLocationUpdateDuration {
        FrequentBackgroundLocationUpdateDuration(rawValue: frequentBackgroundLocationUpdateDuration) ?? .fourHours
    }

    var frequentBackgroundLocationDeliveryModeSelection: FrequentBackgroundLocationDeliveryMode {
        FrequentBackgroundLocationDeliveryMode(rawValue: frequentBackgroundLocationDeliveryMode) ?? .immediate
    }

    var frequentBackgroundVisitorCheckIntervalSelection: FrequentBackgroundVisitorCheckInterval {
        FrequentBackgroundVisitorCheckInterval(rawValue: frequentBackgroundVisitorCheckInterval) ?? .tenMinutes
    }

    var locationTrackingHealthReminderIntervalSelection: LocationTrackingHealthReminderInterval {
        LocationTrackingHealthReminderInterval(rawValue: locationTrackingHealthReminderIntervalDays) ?? .fiveDays
    }

    // Global toggle for pulsing animation on map markers
    @Published var pulsingMapMarkers: Bool {
        didSet { defaults.set(pulsingMapMarkers, forKey: SettingsKeys.pulsingMapMarkers) }
    }

    // Automatically recalculate the route during navigation
    @Published var automaticRouteUpdateDuringNavigation: Bool {
        didSet { defaults.set(automaticRouteUpdateDuringNavigation, forKey: SettingsKeys.automaticRouteUpdateDuringNavigation) }
    }

    @Published var deviceKey: String? {
        didSet {
            if let key = deviceKey, !key.isEmpty {
                defaults.set(key, forKey: SettingsKeys.deviceKey)
            } else {
                defaults.removeObject(forKey: SettingsKeys.deviceKey)
            }
            WidgetDataSyncCoordinator.syncWidgetConfig(
                serverURL: miataruServerURL,
                deviceIDs: KnownDeviceStore.shared.devices.map { $0.DeviceID },
                ownDeviceID: thisDeviceIDManager.shared.deviceID,
                ownDeviceKey: deviceKey
            )
            if deviceKeyAuthBlocked,
               let blockedKey = deviceKeyAuthBlockedKey,
               let currentKey = deviceKey,
               !currentKey.isEmpty,
               blockedKey != currentKey {
                deviceKeyAuthBlocked = false
                deviceKeyAuthBlockedKey = nil
            }
        }
    }

    @Published var deviceKeyLastChanged: Date? {
        didSet {
            if let date = deviceKeyLastChanged {
                defaults.set(date, forKey: SettingsKeys.deviceKeyLastChanged)
            } else {
                defaults.removeObject(forKey: SettingsKeys.deviceKeyLastChanged)
            }
        }
    }

    @Published var deviceKeyAuthBlocked: Bool {
        didSet { defaults.set(deviceKeyAuthBlocked, forKey: SettingsKeys.deviceKeyAuthBlocked) }
    }

    @Published var deviceKeyAuthBlockedKey: String? {
        didSet {
            if let key = deviceKeyAuthBlockedKey, !key.isEmpty {
                defaults.set(key, forKey: SettingsKeys.deviceKeyAuthBlockedKey)
            } else {
                defaults.removeObject(forKey: SettingsKeys.deviceKeyAuthBlockedKey)
            }
        }
    }

    @Published var lastOpenedDeviceID: String? {
        didSet {
            if let id = lastOpenedDeviceID {
                defaults.set(id, forKey: SettingsKeys.lastOpenedDeviceID)
            } else {
                defaults.removeObject(forKey: SettingsKeys.lastOpenedDeviceID)
            }
        }
    }
    
    @Published var reverseGeocodingThresholdMeters: Int {
        didSet { defaults.set(String(reverseGeocodingThresholdMeters), forKey: SettingsKeys.reverseGeocodingThresholdMeters) }
    }
    
    @Published var navigationTransportType: Int {
        didSet { defaults.set(navigationTransportType, forKey: SettingsKeys.navigationTransportType) }
    }
    
    @Published var allowedDeviceListEnabled: Bool {
        didSet { defaults.set(allowedDeviceListEnabled, forKey: SettingsKeys.allowedDeviceListEnabled) }
    }
    
    // MARK: - Location Permission Management
    private func checkAndRequestLocationPermissions() {
        // Reuse the existing LocationManager instance instead of creating a duplicate
        LocationManager.shared.requestLocationPermission()
    }

    private static func persistedInt(forKey key: String,
                                     defaults: UserDefaults,
                                     defaultValue: Int) -> Int {
        if let stringValue = defaults.string(forKey: key),
           let parsedValue = Int(stringValue) {
            return parsedValue
        }

        if let numericValue = defaults.object(forKey: key) as? NSNumber {
            return numericValue.intValue
        }

        return defaultValue
    }
    
    // MARK: - Initialwerte laden
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        SettingsMigration.applySmartFrequentBackgroundMigrationIfNeeded(defaults: d)
        SettingsMigration.normalizeSmartFrequentBackgroundPrerequisiteIfNeeded(defaults: d)
        d.register(defaults: SettingsDefaultValues.registrations)
        self.disableDeviceAutolock = d.bool(forKey: SettingsKeys.disableDeviceAutolock)
        self.preventScreenRotation = d.bool(forKey: SettingsKeys.preventScreenRotation)
        self.indicateAccuracyOnMap = d.bool(forKey: SettingsKeys.indicateAccuracyOnMap)
        self.groupsZoomToFit = d.bool(forKey: SettingsKeys.groupsZoomToFit)
        self.miataruServerURL = d.string(forKey: SettingsKeys.miataruServerURL) ?? SettingsDefaultValues.miataruServerURL
        self.trackAndReportLocation = d.bool(forKey: SettingsKeys.trackAndReportLocation)
        self.trackAndReportLocationDisabledByDeviceKeyAuth = d.bool(forKey: SettingsKeys.trackAndReportLocationDisabledByDeviceKeyAuth)
        self.saveLocationHistoryOnServer = d.bool(forKey: SettingsKeys.saveLocationHistoryOnServer)
        self.locationDataRetentionTime = Self.persistedInt(forKey: SettingsKeys.locationDataRetentionTime, defaults: d, defaultValue: SettingsDefaultValues.locationDataRetentionTime)
        self.mapType = Self.persistedInt(forKey: SettingsKeys.mapType, defaults: d, defaultValue: SettingsDefaultValues.mapType)
        self.mapUpdateInterval = Self.persistedInt(forKey: SettingsKeys.mapUpdateInterval, defaults: d, defaultValue: SettingsDefaultValues.mapUpdateInterval)
        self.outsideMapUpdateInterval = Self.persistedInt(forKey: SettingsKeys.outsideMapUpdateInterval, defaults: d, defaultValue: SettingsDefaultValues.outsideMapUpdateInterval)
        self.mapZoomLevel = Self.persistedInt(forKey: SettingsKeys.mapZoomLevel, defaults: d, defaultValue: SettingsDefaultValues.mapZoomLevel)
        self.historyNumberOfDays = Self.persistedInt(forKey: SettingsKeys.historyNumberOfDays, defaults: d, defaultValue: SettingsDefaultValues.historyNumberOfDays)
        self.locationActivityType = Self.persistedInt(forKey: SettingsKeys.locationActivityType, defaults: d, defaultValue: SettingsDefaultValues.locationActivityType)
        self.locationSensitivityLevel = Self.persistedInt(forKey: SettingsKeys.locationSensitivityLevel, defaults: d, defaultValue: SettingsDefaultValues.locationSensitivityLevel)
        self.smartFrequentBackgroundLocationUpdatesEnabled = d.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled)
        self.smartFrequentBackgroundSpeedThresholdKmh = SmartFrequentBackgroundSpeedThreshold.normalized(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundSpeedThresholdKmh, defaults: d, defaultValue: SettingsDefaultValues.smartFrequentBackgroundSpeedThresholdKmh))
        self.smartFrequentBackgroundSpeedDetectionMode = SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundSpeedDetectionMode, defaults: d, defaultValue: SettingsDefaultValues.smartFrequentBackgroundSpeedDetectionMode))
        self.smartFrequentBackgroundInactivityWindow = SmartFrequentBackgroundInactivityWindow.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundInactivityWindow, defaults: d, defaultValue: SettingsDefaultValues.smartFrequentBackgroundInactivityWindow))
        self.smartFrequentBackgroundModeChangeNotificationsEnabled = d.bool(forKey: SettingsKeys.smartFrequentBackgroundModeChangeNotificationsEnabled)
        self.frequentBackgroundLocationUpdatesEnabled = d.bool(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)
        self.frequentBackgroundLocationDistanceFilter = FrequentBackgroundLocationDistanceFilter.normalized(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationDistanceFilter, defaults: d, defaultValue: SettingsDefaultValues.frequentBackgroundLocationDistanceFilter))
        self.frequentBackgroundLocationUpdateDuration = FrequentBackgroundLocationUpdateDuration.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationUpdateDuration, defaults: d, defaultValue: SettingsDefaultValues.frequentBackgroundLocationUpdateDuration))
        self.frequentBackgroundBatteryAutoDisableLevel = FrequentBackgroundBatteryAutoDisableLevel.normalized(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundBatteryAutoDisableLevel, defaults: d, defaultValue: SettingsDefaultValues.frequentBackgroundBatteryAutoDisableLevel))
        self.frequentBackgroundLocationUpdatesExpiresAt = d.object(forKey: SettingsKeys.frequentBackgroundLocationUpdatesExpiresAt) as? Date
        self.frequentBackgroundLocationDeliveryMode = FrequentBackgroundLocationDeliveryMode.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationDeliveryMode, defaults: d, defaultValue: SettingsDefaultValues.frequentBackgroundLocationDeliveryMode))
        self.frequentBackgroundVisitorCheckInterval = FrequentBackgroundVisitorCheckInterval.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundVisitorCheckInterval, defaults: d, defaultValue: SettingsDefaultValues.frequentBackgroundVisitorCheckInterval))
        self.locationTrackingHealthReminderIntervalDays = LocationTrackingHealthReminderInterval.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.locationTrackingHealthReminderIntervalDays, defaults: d, defaultValue: SettingsDefaultValues.locationTrackingHealthReminderIntervalDays))
        self.autoRefreshDeviceList = d.bool(forKey: SettingsKeys.autoRefreshDeviceList)
        self.unknownVisitorAlertsEnabled = d.bool(forKey: SettingsKeys.unknownVisitorAlertsEnabled)
        self.showCurrentSpeedOnMap = d.bool(forKey: SettingsKeys.showCurrentSpeedOnMap)
        self.showOffscreenArrowsForOtherDevices = d.bool(forKey: SettingsKeys.showOffscreenArrowsForOtherDevices)
        self.showRouteProgress = d.bool(forKey: SettingsKeys.showRouteProgress)
        self.locationUpdateOutboxRetentionMode = Self.persistedInt(forKey: SettingsKeys.locationUpdateOutboxRetentionMode, defaults: d, defaultValue: SettingsDefaultValues.locationUpdateOutboxRetentionMode)
        self.locationUpdateOutboxMaxItems = Self.persistedInt(forKey: SettingsKeys.locationUpdateOutboxMaxItems, defaults: d, defaultValue: SettingsDefaultValues.locationUpdateOutboxMaxItems)
        self.locationDiagnosticsLoggingEnabled = d.bool(forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        self.lastOpenedDeviceID = d.string(forKey: SettingsKeys.lastOpenedDeviceID)
        self.reverseGeocodingThresholdMeters = Self.persistedInt(forKey: SettingsKeys.reverseGeocodingThresholdMeters, defaults: d, defaultValue: SettingsDefaultValues.reverseGeocodingThresholdMeters)
        self.navigationTransportType = Self.persistedInt(forKey: SettingsKeys.navigationTransportType, defaults: d, defaultValue: SettingsDefaultValues.navigationTransportType)
        self.pulsingMapMarkers = d.bool(forKey: SettingsKeys.pulsingMapMarkers)
        self.automaticRouteUpdateDuringNavigation = d.bool(forKey: SettingsKeys.automaticRouteUpdateDuringNavigation)
        self.deviceKey = d.string(forKey: SettingsKeys.deviceKey)
        self.deviceKeyLastChanged = d.object(forKey: SettingsKeys.deviceKeyLastChanged) as? Date
        self.deviceKeyAuthBlocked = d.bool(forKey: SettingsKeys.deviceKeyAuthBlocked)
        self.deviceKeyAuthBlockedKey = d.string(forKey: SettingsKeys.deviceKeyAuthBlockedKey)
        self.allowedDeviceListEnabled = d.bool(forKey: SettingsKeys.allowedDeviceListEnabled)
    }
    
    // MARK: - Synchronize
    func synchronize() {
        defaults.synchronize()
    }

    @discardableResult
    func refreshFromUserDefaultsForAppActivation(now: Date = Date()) -> Bool {
        defaults.register(defaults: SettingsDefaultValues.registrations)

        var changed = false
        func assignIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<SettingsManager, T>, _ newValue: T) {
            guard self[keyPath: keyPath] != newValue else { return }
            self[keyPath: keyPath] = newValue
            changed = true
        }

        isApplyingExternalDefaultsRefresh = true
        defer { isApplyingExternalDefaultsRefresh = false }

        assignIfChanged(\.disableDeviceAutolock, defaults.bool(forKey: SettingsKeys.disableDeviceAutolock))
        assignIfChanged(\.preventScreenRotation, defaults.bool(forKey: SettingsKeys.preventScreenRotation))
        assignIfChanged(\.indicateAccuracyOnMap, defaults.bool(forKey: SettingsKeys.indicateAccuracyOnMap))
        assignIfChanged(\.groupsZoomToFit, defaults.bool(forKey: SettingsKeys.groupsZoomToFit))
        assignIfChanged(\.miataruServerURL, defaults.string(forKey: SettingsKeys.miataruServerURL) ?? SettingsDefaultValues.miataruServerURL)
        assignIfChanged(\.trackAndReportLocation, defaults.bool(forKey: SettingsKeys.trackAndReportLocation))
        assignIfChanged(\.saveLocationHistoryOnServer, defaults.bool(forKey: SettingsKeys.saveLocationHistoryOnServer))
        assignIfChanged(\.locationDataRetentionTime, Self.persistedInt(forKey: SettingsKeys.locationDataRetentionTime, defaults: defaults, defaultValue: SettingsDefaultValues.locationDataRetentionTime))
        assignIfChanged(\.mapType, Self.persistedInt(forKey: SettingsKeys.mapType, defaults: defaults, defaultValue: SettingsDefaultValues.mapType))
        assignIfChanged(\.mapUpdateInterval, Self.persistedInt(forKey: SettingsKeys.mapUpdateInterval, defaults: defaults, defaultValue: SettingsDefaultValues.mapUpdateInterval))
        assignIfChanged(\.outsideMapUpdateInterval, Self.persistedInt(forKey: SettingsKeys.outsideMapUpdateInterval, defaults: defaults, defaultValue: SettingsDefaultValues.outsideMapUpdateInterval))
        assignIfChanged(\.mapZoomLevel, Self.persistedInt(forKey: SettingsKeys.mapZoomLevel, defaults: defaults, defaultValue: SettingsDefaultValues.mapZoomLevel))
        assignIfChanged(\.historyNumberOfDays, Self.persistedInt(forKey: SettingsKeys.historyNumberOfDays, defaults: defaults, defaultValue: SettingsDefaultValues.historyNumberOfDays))
        assignIfChanged(\.locationActivityType, Self.persistedInt(forKey: SettingsKeys.locationActivityType, defaults: defaults, defaultValue: SettingsDefaultValues.locationActivityType))
        assignIfChanged(\.locationSensitivityLevel, Self.persistedInt(forKey: SettingsKeys.locationSensitivityLevel, defaults: defaults, defaultValue: SettingsDefaultValues.locationSensitivityLevel))
        let frequentEnabledBeforeRefresh = frequentBackgroundLocationUpdatesEnabled
        let frequentDurationBeforeRefresh = frequentBackgroundLocationUpdateDuration

        assignIfChanged(\.smartFrequentBackgroundSpeedThresholdKmh, SmartFrequentBackgroundSpeedThreshold.normalized(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundSpeedThresholdKmh, defaults: defaults, defaultValue: SettingsDefaultValues.smartFrequentBackgroundSpeedThresholdKmh)))
        assignIfChanged(\.smartFrequentBackgroundSpeedDetectionMode, SmartFrequentBackgroundSpeedDetectionMode.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundSpeedDetectionMode, defaults: defaults, defaultValue: SettingsDefaultValues.smartFrequentBackgroundSpeedDetectionMode)))
        assignIfChanged(\.smartFrequentBackgroundInactivityWindow, SmartFrequentBackgroundInactivityWindow.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.smartFrequentBackgroundInactivityWindow, defaults: defaults, defaultValue: SettingsDefaultValues.smartFrequentBackgroundInactivityWindow)))
        assignIfChanged(\.smartFrequentBackgroundModeChangeNotificationsEnabled, defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundModeChangeNotificationsEnabled))
        assignIfChanged(\.frequentBackgroundLocationDistanceFilter, FrequentBackgroundLocationDistanceFilter.normalized(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationDistanceFilter, defaults: defaults, defaultValue: SettingsDefaultValues.frequentBackgroundLocationDistanceFilter)))
        assignIfChanged(\.frequentBackgroundLocationUpdateDuration, FrequentBackgroundLocationUpdateDuration.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationUpdateDuration, defaults: defaults, defaultValue: SettingsDefaultValues.frequentBackgroundLocationUpdateDuration)))
        assignIfChanged(\.frequentBackgroundBatteryAutoDisableLevel, FrequentBackgroundBatteryAutoDisableLevel.normalized(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundBatteryAutoDisableLevel, defaults: defaults, defaultValue: SettingsDefaultValues.frequentBackgroundBatteryAutoDisableLevel)))
        assignIfChanged(\.frequentBackgroundLocationDeliveryMode, FrequentBackgroundLocationDeliveryMode.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundLocationDeliveryMode, defaults: defaults, defaultValue: SettingsDefaultValues.frequentBackgroundLocationDeliveryMode)))
        assignIfChanged(\.frequentBackgroundVisitorCheckInterval, FrequentBackgroundVisitorCheckInterval.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.frequentBackgroundVisitorCheckInterval, defaults: defaults, defaultValue: SettingsDefaultValues.frequentBackgroundVisitorCheckInterval)))
        assignIfChanged(\.locationTrackingHealthReminderIntervalDays, LocationTrackingHealthReminderInterval.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.locationTrackingHealthReminderIntervalDays, defaults: defaults, defaultValue: SettingsDefaultValues.locationTrackingHealthReminderIntervalDays)))

        let externalFrequentEnabled = defaults.bool(forKey: SettingsKeys.frequentBackgroundLocationUpdatesEnabled)
        let externalSmartEnabled = defaults.bool(forKey: SettingsKeys.smartFrequentBackgroundLocationUpdatesEnabled) || externalFrequentEnabled
        assignIfChanged(\.frequentBackgroundLocationUpdatesEnabled, externalFrequentEnabled)
        assignIfChanged(\.smartFrequentBackgroundLocationUpdatesEnabled, externalSmartEnabled)

        let shouldRefreshFrequentExpiration = externalFrequentEnabled && (
            !frequentEnabledBeforeRefresh ||
            frequentDurationBeforeRefresh != frequentBackgroundLocationUpdateDuration ||
            frequentBackgroundLocationUpdatesExpiresAt == nil
        )
        if shouldRefreshFrequentExpiration {
            assignIfChanged(
                \.frequentBackgroundLocationUpdatesExpiresAt,
                frequentBackgroundLocationUpdateDurationMode.expirationDate(from: now)
            )
        }

        assignIfChanged(\.autoRefreshDeviceList, defaults.bool(forKey: SettingsKeys.autoRefreshDeviceList))
        assignIfChanged(\.unknownVisitorAlertsEnabled, defaults.bool(forKey: SettingsKeys.unknownVisitorAlertsEnabled))
        assignIfChanged(\.showCurrentSpeedOnMap, defaults.bool(forKey: SettingsKeys.showCurrentSpeedOnMap))
        assignIfChanged(\.showOffscreenArrowsForOtherDevices, defaults.bool(forKey: SettingsKeys.showOffscreenArrowsForOtherDevices))
        assignIfChanged(\.showRouteProgress, defaults.bool(forKey: SettingsKeys.showRouteProgress))
        assignIfChanged(\.locationUpdateOutboxRetentionMode, LocationUpdateOutboxRetentionMode.normalizedRawValue(Self.persistedInt(forKey: SettingsKeys.locationUpdateOutboxRetentionMode, defaults: defaults, defaultValue: SettingsDefaultValues.locationUpdateOutboxRetentionMode)))
        assignIfChanged(\.locationUpdateOutboxMaxItems, Self.persistedInt(forKey: SettingsKeys.locationUpdateOutboxMaxItems, defaults: defaults, defaultValue: SettingsDefaultValues.locationUpdateOutboxMaxItems))
        assignIfChanged(\.locationDiagnosticsLoggingEnabled, defaults.bool(forKey: SettingsKeys.locationDiagnosticsLoggingEnabled))
        assignIfChanged(\.reverseGeocodingThresholdMeters, Self.persistedInt(forKey: SettingsKeys.reverseGeocodingThresholdMeters, defaults: defaults, defaultValue: SettingsDefaultValues.reverseGeocodingThresholdMeters))
        assignIfChanged(\.navigationTransportType, Self.persistedInt(forKey: SettingsKeys.navigationTransportType, defaults: defaults, defaultValue: SettingsDefaultValues.navigationTransportType))
        assignIfChanged(\.pulsingMapMarkers, defaults.bool(forKey: SettingsKeys.pulsingMapMarkers))
        assignIfChanged(\.automaticRouteUpdateDuringNavigation, defaults.bool(forKey: SettingsKeys.automaticRouteUpdateDuringNavigation))
        assignIfChanged(\.allowedDeviceListEnabled, defaults.bool(forKey: SettingsKeys.allowedDeviceListEnabled))

        let frequentWasEnabled = frequentBackgroundLocationUpdatesEnabled
        let expirationWas = frequentBackgroundLocationUpdatesExpiresAt
        ensureFrequentBackgroundLocationUpdatesExpiration(now: now)
        if frequentWasEnabled != frequentBackgroundLocationUpdatesEnabled ||
            expirationWas != frequentBackgroundLocationUpdatesExpiresAt {
            changed = true
        }

        return changed
    }

    func refreshFrequentBackgroundLocationUpdatesExpiration(now: Date = Date()) {
        frequentBackgroundLocationUpdatesExpiresAt = frequentBackgroundLocationUpdateDurationMode.expirationDate(from: now)
    }

    func ensureFrequentBackgroundLocationUpdatesExpiration(now: Date = Date()) {
        guard frequentBackgroundLocationUpdatesEnabled else {
            if frequentBackgroundLocationUpdatesExpiresAt != nil {
                frequentBackgroundLocationUpdatesExpiresAt = nil
            }
            return
        }

        if frequentBackgroundLocationUpdateDurationMode == .unlimited {
            if frequentBackgroundLocationUpdatesExpiresAt != nil {
                frequentBackgroundLocationUpdatesExpiresAt = nil
            }
            return
        }

        if let expiresAt = frequentBackgroundLocationUpdatesExpiresAt {
            if expiresAt <= now {
                frequentBackgroundLocationUpdatesEnabled = false
            }
        } else {
            refreshFrequentBackgroundLocationUpdatesExpiration(now: now)
        }
    }

    @discardableResult
    func disableExpiredFrequentBackgroundLocationUpdatesIfNeeded(now: Date = Date()) -> Bool {
        guard frequentBackgroundLocationUpdatesEnabled,
              let expiresAt = frequentBackgroundLocationUpdatesExpiresAt,
              expiresAt <= now else {
            return false
        }

        frequentBackgroundLocationUpdatesEnabled = false
        return true
    }

    @MainActor
    func setUnknownVisitorAlertsEnabledFromUser(_ enabled: Bool) async {
        let result = await UnknownVisitorAlertService.shared.setFeatureEnabled(enabled)
        switch result {
        case .enabled:
            unknownVisitorAlertsEnabled = true
            unknownVisitorAlertsPermissionDenied = false
        case .disabled:
            unknownVisitorAlertsEnabled = false
            unknownVisitorAlertsPermissionDenied = false
        case .denied:
            unknownVisitorAlertsEnabled = false
            unknownVisitorAlertsPermissionDenied = true
        }
    }
    
    // MARK: - Laufzeit-Defaults registrieren
    func registerDefaultsFromSettingsBundle() {
        // Runtime defaults live centrally in Swift so fresh installs and tests stay
        // deterministic. Settings.bundle mirrors the same values for iOS Settings.
        defaults.register(defaults: SettingsDefaultValues.registrations)
    }
    
    static let shared = SettingsManager()
} 
