//
//  SettingsManager.swift
//  miataru
//
//  Created by Daniel Kirstenpfad on 20.06.25.
//

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
        didSet { defaults.set(miataruServerURL, forKey: Keys.miataruServerURL) }
    }
    @Published var trackAndReportLocation: Bool {
        didSet { defaults.set(trackAndReportLocation, forKey: Keys.trackAndReportLocation) }
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
        static let locationActivityType = "location_activity_type"
        static let locationSensitivityLevel = "location_sensitivity_level"
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
        self.mapZoomLevel = Int(d.string(forKey: Keys.mapZoomLevel) ?? "1") ?? 1
        self.historyNumberOfDays = Int(d.string(forKey: Keys.historyNumberOfDays) ?? "10000000") ?? 10000000
        self.locationActivityType = Int(d.string(forKey: Keys.locationActivityType) ?? "0") ?? 0
        self.locationSensitivityLevel = d.object(forKey: Keys.locationSensitivityLevel) as? Int ?? 2
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
            print("Settings.bundle oder Root.plist nicht gefunden!")
        }
    }
    
    static let shared = SettingsManager()
} 
