//
//  SettingsManager.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

import Foundation

class SettingsManager {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard
    
    private init() {}
    
    // MARK: - Keys
    private enum Keys {
        static let mapType = "map_type"
        static let disableDeviceAutolock = "disable_device_autolock_while_in_foreground"
        static let mapUpdateInterval = "map_update_interval"
        static let mapZoomLevel = "map_zoom_level"
        static let indicateAccuracyOnMap = "indicate_accuracy_on_map"
        static let groupsZoomToFit = "groups_zoom_to_fit"
        static let miataruServerURL = "miataru_server_url"
        static let trackAndReportLocation = "track_and_report_location"
        static let saveLocationHistoryOnServer = "save_location_history_on_server"
        static let historyNumberOfDays = "history_number_of_days"
    }
    
    // MARK: - Properties
    var disableDeviceAutolock: Bool {
        get { defaults.bool(forKey: Keys.disableDeviceAutolock) }
        set { defaults.set(newValue, forKey: Keys.disableDeviceAutolock) }
    }
    
    var indicateAccuracyOnMap: Bool {
        get { defaults.bool(forKey: Keys.indicateAccuracyOnMap) }
        set { defaults.set(newValue, forKey: Keys.indicateAccuracyOnMap) }
    }
    
    var groupsZoomToFit: Bool {
        get { defaults.bool(forKey: Keys.groupsZoomToFit) }
        set { defaults.set(newValue, forKey: Keys.groupsZoomToFit) }
    }
    
    var miataruServerURL: String? {
        get { defaults.string(forKey: Keys.miataruServerURL) }
        set { defaults.set(newValue, forKey: Keys.miataruServerURL) }
    }
    
    var trackAndReportLocation: Bool {
        get { defaults.bool(forKey: Keys.trackAndReportLocation) }
        set { defaults.set(newValue, forKey: Keys.trackAndReportLocation) }
    }
    
    var saveLocationHistoryOnServer: Bool {
        get { defaults.bool(forKey: Keys.saveLocationHistoryOnServer) }
        set { defaults.set(newValue, forKey: Keys.saveLocationHistoryOnServer) }
    }
    
    var locationDataRetentionTime: Int {
        get { Int(defaults.string(forKey: "location_data_retention_time") ?? "30") ?? 30 }
        set { defaults.set(String(newValue), forKey: "location_data_retention_time") }
    }
    
    var mapType: Int {
        get { Int(defaults.string(forKey: Keys.mapType) ?? "1") ?? 1 }
        set { defaults.set(String(newValue), forKey: Keys.mapType) }
    }
    
    var mapUpdateInterval: Int {
        get { Int(defaults.string(forKey: Keys.mapUpdateInterval) ?? "30") ?? 30 }
        set { defaults.set(String(newValue), forKey: Keys.mapUpdateInterval) }
    }
    
    var mapZoomLevel: Int {
        get { Int(defaults.string(forKey: Keys.mapZoomLevel) ?? "1") ?? 1 }
        set { defaults.set(String(newValue), forKey: Keys.mapZoomLevel) }
    }
    
    var historyNumberOfDays: Int {
        get { Int(defaults.string(forKey: Keys.historyNumberOfDays) ?? "5") ?? 5 }
        set { defaults.set(String(newValue), forKey: Keys.historyNumberOfDays) }
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
            print("Settings.bundle gefunden: \(settingsBundle)")
            print("Root.plist gefunden: \(plistPath)")
            print("PreferenceSpecifiers: \(preferences)")
            var defaultsToRegister: [String: Any] = [:]
            for item in preferences {
                if let key = item["Key"] as? String, let defaultValue = item["DefaultValue"] {
                    print("Key: \(key), DefaultValue: \(defaultValue)")
                    if defaults.object(forKey: key) == nil {
                        defaultsToRegister[key] = defaultValue
                    }
                }
            }
            defaults.register(defaults: defaultsToRegister)
            print("Registrierte Defaults: \(defaultsToRegister)")
        } else {
            print("Settings.bundle oder Root.plist nicht gefunden!")
        }
    }
} 
