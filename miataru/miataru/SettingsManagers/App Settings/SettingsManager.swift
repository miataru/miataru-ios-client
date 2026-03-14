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
    private let defaults = UserDefaults.standard
    
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
            if trackAndReportLocation {
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
    init() {
        let d = UserDefaults.standard
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
        self.autoRefreshDeviceList = d.bool(forKey: SettingsKeys.autoRefreshDeviceList)
        self.unknownVisitorAlertsEnabled = d.bool(forKey: SettingsKeys.unknownVisitorAlertsEnabled)
        self.showCurrentSpeedOnMap = d.bool(forKey: SettingsKeys.showCurrentSpeedOnMap)
        self.showOffscreenArrowsForOtherDevices = d.bool(forKey: SettingsKeys.showOffscreenArrowsForOtherDevices)
        self.showRouteProgress = d.bool(forKey: SettingsKeys.showRouteProgress)
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
