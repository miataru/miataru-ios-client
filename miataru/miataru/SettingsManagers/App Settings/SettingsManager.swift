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
        didSet { defaults.set(disableDeviceAutolock, forKey: Keys.disableDeviceAutolock) }
    }
    @Published var indicateAccuracyOnMap: Bool {
        didSet { defaults.set(indicateAccuracyOnMap, forKey: Keys.indicateAccuracyOnMap) }
    }
    @Published var groupsZoomToFit: Bool {
        didSet { defaults.set(groupsZoomToFit, forKey: Keys.groupsZoomToFit) }
    }
    @Published var miataruServerURL: String {
        didSet {
            defaults.set(miataruServerURL, forKey: Keys.miataruServerURL)
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
            defaults.set(trackAndReportLocation, forKey: Keys.trackAndReportLocation)
            // Check location permissions when tracking is enabled
            if trackAndReportLocation {
                checkAndRequestLocationPermissions()
            }
        }
    }
    @Published var saveLocationHistoryOnServer: Bool {
        didSet { defaults.set(saveLocationHistoryOnServer, forKey: Keys.saveLocationHistoryOnServer) }
    }
    @Published var locationDataRetentionTime: Int {
        didSet { defaults.set(String(locationDataRetentionTime), forKey: "location_data_retention_time") }
    }
    @Published var mapType: Int {
        didSet { defaults.set(String(mapType), forKey: Keys.mapType) }
    }
    @Published var mapUpdateInterval: Int {
        didSet { defaults.set(String(mapUpdateInterval), forKey: Keys.mapUpdateInterval) }
    }
    @Published var outsideMapUpdateInterval: Int {
        didSet { defaults.set(String(outsideMapUpdateInterval), forKey: Keys.outsideMapUpdateInterval) }
    }
    @Published var mapZoomLevel: Int {
        didSet { defaults.set(String(mapZoomLevel), forKey: Keys.mapZoomLevel) }
    }
    @Published var historyNumberOfDays: Int {
        didSet { defaults.set(String(historyNumberOfDays), forKey: Keys.historyNumberOfDays) }
    }
    @Published var locationActivityType: Int {
        didSet { defaults.set(locationActivityType, forKey: Keys.locationActivityType) }
    }
    @Published var locationSensitivityLevel: Int {
        didSet { defaults.set(locationSensitivityLevel, forKey: Keys.locationSensitivityLevel) }
    }
    @Published var autoRefreshDeviceList: Bool {
        didSet { defaults.set(autoRefreshDeviceList, forKey: Keys.autoRefreshDeviceList) }
    }
    @Published var showCurrentSpeedOnMap: Bool {
        didSet { defaults.set(showCurrentSpeedOnMap, forKey: Keys.showCurrentSpeedOnMap) }
    }
    @Published var showOffscreenArrowsForOtherDevices: Bool {
        didSet { defaults.set(showOffscreenArrowsForOtherDevices, forKey: Keys.showOffscreenArrowsForOtherDevices) }
    }
    // Removed: showOtherDevicesOnMap
    @Published var showRouteProgress: Bool {
        didSet { defaults.set(showRouteProgress, forKey: Keys.showRouteProgress) }
    }

    // Global toggle for pulsing animation on map markers
    @Published var pulsingMapMarkers: Bool {
        didSet { defaults.set(pulsingMapMarkers, forKey: Keys.pulsingMapMarkers) }
    }

    // Automatically recalculate the route during navigation
    @Published var automaticRouteUpdateDuringNavigation: Bool {
        didSet { defaults.set(automaticRouteUpdateDuringNavigation, forKey: Keys.automaticRouteUpdateDuringNavigation) }
    }

    @Published var deviceKey: String? {
        didSet {
            if let key = deviceKey, !key.isEmpty {
                defaults.set(key, forKey: Keys.deviceKey)
            } else {
                defaults.removeObject(forKey: Keys.deviceKey)
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
                defaults.set(date, forKey: Keys.deviceKeyLastChanged)
            } else {
                defaults.removeObject(forKey: Keys.deviceKeyLastChanged)
            }
        }
    }

    @Published var deviceKeyAuthBlocked: Bool {
        didSet { defaults.set(deviceKeyAuthBlocked, forKey: Keys.deviceKeyAuthBlocked) }
    }

    @Published var deviceKeyAuthBlockedKey: String? {
        didSet {
            if let key = deviceKeyAuthBlockedKey, !key.isEmpty {
                defaults.set(key, forKey: Keys.deviceKeyAuthBlockedKey)
            } else {
                defaults.removeObject(forKey: Keys.deviceKeyAuthBlockedKey)
            }
        }
    }

    @Published var lastOpenedDeviceID: String? {
        didSet {
            if let id = lastOpenedDeviceID {
                defaults.set(id, forKey: Keys.lastOpenedDeviceID)
            } else {
                defaults.removeObject(forKey: Keys.lastOpenedDeviceID)
            }
        }
    }
    
    @Published var reverseGeocodingThresholdMeters: Int {
        didSet { defaults.set(String(reverseGeocodingThresholdMeters), forKey: Keys.reverseGeocodingThresholdMeters) }
    }
    
    @Published var navigationTransportType: Int {
        didSet { defaults.set(navigationTransportType, forKey: Keys.navigationTransportType) }
    }
    
    @Published var allowedDeviceListEnabled: Bool {
        didSet { defaults.set(allowedDeviceListEnabled, forKey: Keys.allowedDeviceListEnabled) }
    }
    
    // MARK: - Keys
    private enum Keys {
        static let mapType = "map_type"
        static let disableDeviceAutolock = "disable_device_autolock_while_in_foreground"
        static let mapUpdateInterval = "map_update_interval"
        static let outsideMapUpdateInterval = "outside_map_update_interval"
        static let mapZoomLevel = "map_zoom_level"
        static let indicateAccuracyOnMap = "indicate_accuracy_on_map"
        static let groupsZoomToFit = "groups_zoom_to_fit"
        static let miataruServerURL = "miataru_server_url"
        static let trackAndReportLocation = "track_and_report_location"
        static let saveLocationHistoryOnServer = "save_location_history_on_server"
        static let historyNumberOfDays = "history_number_of_days"
        static let locationActivityType = "location_activity_type"
        static let locationSensitivityLevel = "location_sensitivity_level"
        static let autoRefreshDeviceList = "auto_refresh_device_list"
        static let showCurrentSpeedOnMap = "show_current_speed_on_map"
        static let showOffscreenArrowsForOtherDevices = "show_offscreen_arrows_for_other_devices"
        static let showRouteProgress = "show_route_progress"
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
    
    // MARK: - Location Permission Management
    private func checkAndRequestLocationPermissions() {
        // Reuse the existing LocationManager instance instead of creating a duplicate
        LocationManager.shared.requestLocationPermission()
    }
    
    // MARK: - Initialwerte laden
    init() {
        let d = UserDefaults.standard
        self.disableDeviceAutolock = d.object(forKey: Keys.disableDeviceAutolock) as? Bool ?? false
        self.indicateAccuracyOnMap = d.object(forKey: Keys.indicateAccuracyOnMap) as? Bool ?? true
        self.groupsZoomToFit = d.object(forKey: Keys.groupsZoomToFit) as? Bool ?? true
        self.miataruServerURL = d.string(forKey: Keys.miataruServerURL) ?? "https://service.miataru.com"
        self.trackAndReportLocation = d.object(forKey: Keys.trackAndReportLocation) as? Bool ?? false
        self.saveLocationHistoryOnServer = d.object(forKey: Keys.saveLocationHistoryOnServer) as? Bool ?? false
        self.locationDataRetentionTime = Int(d.string(forKey: "location_data_retention_time") ?? "1440") ?? 1440
        self.mapType = Int(d.string(forKey: Keys.mapType) ?? "1") ?? 1
        self.mapUpdateInterval = Int(d.string(forKey: Keys.mapUpdateInterval) ?? "30") ?? 30
        self.outsideMapUpdateInterval = Int(d.string(forKey: Keys.outsideMapUpdateInterval) ?? "30") ?? 30
        self.mapZoomLevel = Int(d.string(forKey: Keys.mapZoomLevel) ?? "1") ?? 1
        self.historyNumberOfDays = Int(d.string(forKey: Keys.historyNumberOfDays) ?? "10000000") ?? 10000000
        self.locationActivityType = Int(d.string(forKey: Keys.locationActivityType) ?? "0") ?? 0
        self.locationSensitivityLevel = Int(d.string(forKey: Keys.locationSensitivityLevel) ?? "2") ?? 2
        self.autoRefreshDeviceList = d.object(forKey: Keys.autoRefreshDeviceList) as? Bool ?? true
        self.showCurrentSpeedOnMap = d.object(forKey: Keys.showCurrentSpeedOnMap) as? Bool ?? true
        self.showOffscreenArrowsForOtherDevices = d.object(forKey: Keys.showOffscreenArrowsForOtherDevices) as? Bool ?? false
        self.showRouteProgress = d.object(forKey: Keys.showRouteProgress) as? Bool ?? false
        self.lastOpenedDeviceID = d.string(forKey: Keys.lastOpenedDeviceID)
        // Default: 1000m, Off=0, 100m=100, 10km=10000
        self.reverseGeocodingThresholdMeters = Int(d.string(forKey: Keys.reverseGeocodingThresholdMeters) ?? "1000") ?? 1000
        self.navigationTransportType = Int(d.string(forKey: Keys.navigationTransportType) ?? "2") ?? 2
        self.pulsingMapMarkers = d.object(forKey: Keys.pulsingMapMarkers) as? Bool ?? true
        self.automaticRouteUpdateDuringNavigation = d.object(forKey: Keys.automaticRouteUpdateDuringNavigation) as? Bool ?? true
        self.deviceKey = d.string(forKey: Keys.deviceKey)
        self.deviceKeyLastChanged = d.object(forKey: Keys.deviceKeyLastChanged) as? Date
        self.deviceKeyAuthBlocked = d.object(forKey: Keys.deviceKeyAuthBlocked) as? Bool ?? false
        self.deviceKeyAuthBlockedKey = d.string(forKey: Keys.deviceKeyAuthBlockedKey)
        self.allowedDeviceListEnabled = d.object(forKey: Keys.allowedDeviceListEnabled) as? Bool ?? false
    }
    
    // MARK: - Synchronize
    func synchronize() {
        defaults.synchronize()
    }
    
    // MARK: - Default-Werte aus Settings.bundle laden
    func registerDefaultsFromSettingsBundle() {
        if let settingsBundle = Bundle.main.path(forResource: "Settings", ofType: "bundle"),
           let settings = Bundle(path: settingsBundle),
           let plistPath = settings.path(forResource: "Root", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: plistPath) as? [String: Any],
           let preferences = dict["PreferenceSpecifiers"] as? [[String: Any]] {
            //print("Settings.bundle gefunden: \(settingsBundle)")
            //print("Root.plist gefunden: \(plistPath)")
            //print("PreferenceSpecifiers: \(preferences)")
            var defaultsToRegister: [String: Any] = [:]
            for item in preferences {
                if let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] {
                    //print("Key: \(key), DefaultValue: \(defaultValue)")
                    if defaults.object(forKey: key) == nil {
                        defaultsToRegister[key] = defaultValue
                    }
                }
            }
            defaults.register(defaults: defaultsToRegister)
            //print("Registrierte Defaults: \(defaultsToRegister)")
        } else {
            debugLog("Settings.bundle oder Root.plist nicht gefunden!")
        }
    }
    
    static let shared = SettingsManager()
} 
