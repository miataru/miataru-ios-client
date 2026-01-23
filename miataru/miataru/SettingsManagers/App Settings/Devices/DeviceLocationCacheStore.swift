/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLocationCacheStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import UIKit
import Combine
import CoreLocation

@objc(CachedDeviceLocation)
class CachedDeviceLocation: NSObject, NSCoding, NSSecureCoding, Identifiable {
    @objc var deviceID: String
    @objc var latitude: Double
    @objc var longitude: Double
    @objc var accuracy: Double
    @objc var timestamp: Date
    @objc var country: String?
    @objc var locality: String?
    var timeZone: TimeZone?
    var batteryLevel: Double?
    var altitude: Double?
    var speed: Double?
    
    var id: String { deviceID }
    
    init(deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date, country: String? = nil, locality: String? = nil, timeZone: TimeZone? = nil, batteryLevel: Double? = nil, altitude: Double? = nil, speed: Double? = nil) {
        self.deviceID = deviceID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.country = country
        self.locality = locality
        self.timeZone = timeZone
        self.batteryLevel = batteryLevel
        self.altitude = altitude
        self.speed = speed
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.deviceID = aDecoder.decodeObject(forKey: "deviceID") as? String ?? ""
        self.latitude = aDecoder.decodeDouble(forKey: "latitude")
        self.longitude = aDecoder.decodeDouble(forKey: "longitude")
        self.accuracy = aDecoder.decodeDouble(forKey: "accuracy")
        self.timestamp = aDecoder.decodeObject(forKey: "timestamp") as? Date ?? Date()
        self.country = aDecoder.decodeObject(forKey: "country") as? String
        self.locality = aDecoder.decodeObject(forKey: "locality") as? String
        if let timeZoneIdentifier = aDecoder.decodeObject(forKey: "timeZoneIdentifier") as? String {
            self.timeZone = TimeZone(identifier: timeZoneIdentifier)
        } else {
            self.timeZone = nil
        }
        self.batteryLevel = aDecoder.decodeObject(forKey: "batteryLevel") as? Double
        self.altitude = aDecoder.decodeObject(forKey: "altitude") as? Double
        self.speed = aDecoder.decodeObject(forKey: "speed") as? Double
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(deviceID, forKey: "deviceID")
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(accuracy, forKey: "accuracy")
        aCoder.encode(timestamp, forKey: "timestamp")
        aCoder.encode(country, forKey: "country")
        aCoder.encode(locality, forKey: "locality")
        aCoder.encode(timeZone?.identifier, forKey: "timeZoneIdentifier")
        aCoder.encode(batteryLevel, forKey: "batteryLevel")
        aCoder.encode(altitude, forKey: "altitude")
        aCoder.encode(speed, forKey: "speed")
    }
    
    static var supportsSecureCoding: Bool {
        return true
    }
}

class DeviceLocationCacheStore: ObservableObject {
    static let shared = DeviceLocationCacheStore()
    
    @Published var locations: [CachedDeviceLocation] = [] {
        didSet {
            save()
        }
    }
    
    /// Set of device IDs that have looked for the current user's device in the past 90 seconds
    @Published var recentVisitorDeviceIDs: Set<String> = []
    private let fileName = "deviceLocations.plist"
    private let geocoder = CLGeocoder()
    private var geocodeQueue: [String] = []
    private var isProcessingGeocode: Bool = false
    private var geocodeDistanceThresholdMeters: CLLocationDistance {
        CLLocationDistance(SettingsManager.shared.reverseGeocodingThresholdMeters)
    }
    
    private var fileURL: URL {
        AppDirectories.applicationSupportFile(named: fileName)
    }
    
    private init() {
        self.locations = load()
        // Enqueue reverse geocoding for any cached entries missing placemarks or timezone
        for loc in locations where (loc.country == nil && loc.locality == nil) || loc.timeZone == nil {
            enqueueGeocodingIfNeeded(for: loc.deviceID)
        }
    }
    
    private func save() {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: locations, requiringSecureCoding: true)
            try data.write(to: fileURL)
        } catch {
            debugLog("Error saving device locations: \(error)")
        }
    }

    private func load() -> [CachedDeviceLocation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            if let locations = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, CachedDeviceLocation.self, NSDate.self, NSString.self], from: data) as? [CachedDeviceLocation] {
                return locations
            }
        } catch {
            debugLog("Error loading device locations: \(error)")
            // Remove incompatible cache file to prevent repeated load failures
            try? FileManager.default.removeItem(at: fileURL)
        }
        return []
    }

    func setLocation(for deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date, batteryLevel: Double? = nil, altitude: Double? = nil, speed: Double? = nil) {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            let existing = locations[idx]
            let moved = existing.latitude != latitude || existing.longitude != longitude
            let updated = CachedDeviceLocation(
                deviceID: deviceID,
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                timestamp: timestamp,
                // Preserve previous placemark to avoid UI flicker; will be updated by geocoding
                country: existing.country,
                locality: existing.locality,
                timeZone: existing.timeZone,
                batteryLevel: batteryLevel,
                altitude: altitude,
                speed: speed ?? existing.speed
            )
            locations[idx] = updated
            if moved {
                // Re-geocode only on significant movement or if no placemark exists yet
                let hasPlacemark = (existing.country != nil) || (existing.locality != nil)
                let oldLoc = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                let newLoc = CLLocation(latitude: latitude, longitude: longitude)
                let distance = oldLoc.distance(from: newLoc)
                if !hasPlacemark || distance >= geocodeDistanceThresholdMeters {
                    enqueueGeocodingIfNeeded(for: deviceID, force: true)
                }
            }
            WidgetDataSyncCoordinator.syncAllDevices()
        } else {
            let newLocation = CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp, batteryLevel: batteryLevel, altitude: altitude, speed: speed)
            locations.append(newLocation)
            // New entry: if no placemark present, enqueue
            enqueueGeocodingIfNeeded(for: deviceID)
            WidgetDataSyncCoordinator.syncAllDevices()
        }

        // Widget snapshots are now generated inside the widget extension to avoid
        // app/widget write races on the same files.
        // (Intentionally no app-side snapshot generation here.)
    }

    func getLocation(for deviceID: String) -> CachedDeviceLocation? {
        return locations.first(where: { $0.deviceID == deviceID })
    }

    func getPlacemark(for deviceID: String) -> (country: String?, locality: String?)? {
        guard let loc = locations.first(where: { $0.deviceID == deviceID }) else { return nil }
        return (loc.country, loc.locality)
    }

    func setPlacemark(for deviceID: String, country: String?, locality: String?, timeZone: TimeZone? = nil) {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            let loc = locations[idx]
            let updated = CachedDeviceLocation(
                deviceID: loc.deviceID,
                latitude: loc.latitude,
                longitude: loc.longitude,
                accuracy: loc.accuracy,
                timestamp: loc.timestamp,
                country: country,
                locality: locality,
                timeZone: timeZone ?? loc.timeZone,
                batteryLevel: loc.batteryLevel,
                altitude: loc.altitude
            )
            locations[idx] = updated
            WidgetDataSyncCoordinator.syncAllDevices()
        }
    }
    
    func removeLocation(for deviceID: String) {
        locations.removeAll { $0.deviceID == deviceID }
        WidgetDataSyncCoordinator.syncAllDevices()
    }

    // MARK: - Reverse Geocoding Queue
    func enqueueGeocodingIfNeeded(for deviceID: String, force: Bool = false) {
        // If not forced and placemark already present with timezone, skip
        if !force {
            if let location = getLocation(for: deviceID),
               let placemark = getPlacemark(for: deviceID),
               (placemark.country != nil || placemark.locality != nil),
               location.timeZone != nil {
                return
            }
        }
        guard let _ = getLocation(for: deviceID) else { return }
        // Avoid duplicates in queue
        if !geocodeQueue.contains(deviceID) {
            geocodeQueue.append(deviceID)
        }
        processNextGeocode()
    }
    
    func getTimeZone(for deviceID: String) -> TimeZone? {
        return getLocation(for: deviceID)?.timeZone
    }
    
    func forceGeocodingForAllDevices() {
        for location in locations {
            enqueueGeocodingIfNeeded(for: location.deviceID, force: true)
        }
    }
    
    /// Sets the device IDs that have looked for the current user's device in the past 90 seconds
    func setRecentVisitorDeviceIDs(_ deviceIDs: Set<String>) {
        recentVisitorDeviceIDs = deviceIDs
    }
    
    /// Checks if a device has looked for the current user's device in the past 90 seconds
    func hasRecentVisitor(deviceID: String) -> Bool {
        return recentVisitorDeviceIDs.contains(deviceID)
    }

    private func processNextGeocode() {
        guard !isProcessingGeocode else { return }
        guard !geocodeQueue.isEmpty else { return }
        isProcessingGeocode = true
        let nextDeviceID = geocodeQueue.removeFirst()
        guard let cached = getLocation(for: nextDeviceID) else {
            isProcessingGeocode = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.processNextGeocode()
            }
            return
        }
        let location = CLLocation(latitude: cached.latitude, longitude: cached.longitude)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self = self else { return }
            let pm = placemarks?.first
            DispatchQueue.main.async {
                if let pm = pm {
                    let country = pm.country
                    let locality = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea
                    let timeZone = pm.timeZone
                    self.setPlacemark(for: nextDeviceID, country: country, locality: locality, timeZone: timeZone)
                }
                self.isProcessingGeocode = false
                // Be polite with geocoder
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.processNextGeocode()
                }
            }
        }
    }
} 
