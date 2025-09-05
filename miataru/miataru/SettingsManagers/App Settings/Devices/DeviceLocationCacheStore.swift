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
    private let geocoder = CLGeocoder()
    private var geocodeQueue: [String] = []
    private var isProcessingGeocode: Bool = false
    private var geocodeDistanceThresholdMeters: CLLocationDistance {
        CLLocationDistance(SettingsManager.shared.reverseGeocodingThresholdMeters)
    }
    
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
        // Enqueue reverse geocoding for any cached entries missing placemarks
        for loc in locations where (loc.country == nil && loc.locality == nil) {
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
                // Preserve previous placemark to avoid UI flicker; will be updated by geocoding
                country: existing.country,
                locality: existing.locality
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
        } else {
            locations.append(CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp))
            // New entry: if no placemark present, enqueue
            enqueueGeocodingIfNeeded(for: deviceID)
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

    // MARK: - Reverse Geocoding Queue
    func enqueueGeocodingIfNeeded(for deviceID: String, force: Bool = false) {
        // If not forced and placemark already present, skip
        if !force {
            if let placemark = getPlacemark(for: deviceID), placemark.country != nil || placemark.locality != nil {
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
    
    func forceGeocodingForAllDevices() {
        for location in locations {
            enqueueGeocodingIfNeeded(for: location.deviceID, force: true)
        }
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
                    self.setPlacemark(for: nextDeviceID, country: country, locality: locality)
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
