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
    
    var id: String { deviceID }
    
    init(deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date, country: String? = nil, locality: String? = nil) {
        self.deviceID = deviceID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.timestamp = timestamp
        self.country = country
        self.locality = locality
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.deviceID = aDecoder.decodeObject(forKey: "deviceID") as? String ?? ""
        self.latitude = aDecoder.decodeDouble(forKey: "latitude")
        self.longitude = aDecoder.decodeDouble(forKey: "longitude")
        self.accuracy = aDecoder.decodeDouble(forKey: "accuracy")
        self.timestamp = aDecoder.decodeObject(forKey: "timestamp") as? Date ?? Date()
        self.country = aDecoder.decodeObject(forKey: "country") as? String
        self.locality = aDecoder.decodeObject(forKey: "locality") as? String
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(deviceID, forKey: "deviceID")
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(accuracy, forKey: "accuracy")
        aCoder.encode(timestamp, forKey: "timestamp")
        aCoder.encode(country, forKey: "country")
        aCoder.encode(locality, forKey: "locality")
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
    private let fileName = "deviceLocations.plist"
    
    private var fileURL: URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = urls[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "DefaultApp"
        let appDirectory = appSupportURL.appendingPathComponent(bundleID)
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirectory.appendingPathComponent(fileName)
    }
    
    private init() {
        self.locations = load()
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

    func setLocation(for deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date) {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            let existing = locations[idx]
            let moved = existing.latitude != latitude || existing.longitude != longitude
            let updated = CachedDeviceLocation(
                deviceID: deviceID,
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                timestamp: timestamp,
                country: moved ? nil : existing.country,
                locality: moved ? nil : existing.locality
            )
            locations[idx] = updated
        } else {
            locations.append(CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp))
        }
    }

    func getLocation(for deviceID: String) -> CachedDeviceLocation? {
        return locations.first(where: { $0.deviceID == deviceID })
    }

    func getPlacemark(for deviceID: String) -> (country: String?, locality: String?)? {
        guard let loc = locations.first(where: { $0.deviceID == deviceID }) else { return nil }
        return (loc.country, loc.locality)
    }

    func setPlacemark(for deviceID: String, country: String?, locality: String?) {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            let loc = locations[idx]
            let updated = CachedDeviceLocation(
                deviceID: loc.deviceID,
                latitude: loc.latitude,
                longitude: loc.longitude,
                accuracy: loc.accuracy,
                timestamp: loc.timestamp,
                country: country,
                locality: locality
            )
            locations[idx] = updated
        }
    }
    
    func removeLocation(for deviceID: String) {
        locations.removeAll { $0.deviceID == deviceID }
    }
} 
