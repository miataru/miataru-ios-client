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
import MiataruAPIClient

struct DeviceLocationSnapshot {
    let deviceID: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let batteryLevel: Double?
    let altitude: Double?
    let speed: Double?
}

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

    @discardableResult
    func setLocation(for deviceID: String, latitude: Double, longitude: Double, accuracy: Double, timestamp: Date, batteryLevel: Double? = nil, altitude: Double? = nil, speed: Double? = nil) -> Bool {
        if let idx = locations.firstIndex(where: { $0.deviceID == deviceID }) {
            let existing = locations[idx]
            guard timestamp >= existing.timestamp else {
                return false
            }
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
                batteryLevel: batteryLevel ?? existing.batteryLevel,
                altitude: altitude ?? existing.altitude,
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
            return true
        } else {
            let newLocation = CachedDeviceLocation(deviceID: deviceID, latitude: latitude, longitude: longitude, accuracy: accuracy, timestamp: timestamp, batteryLevel: batteryLevel, altitude: altitude, speed: speed)
            locations.append(newLocation)
            // New entry: if no placemark present, enqueue
            enqueueGeocodingIfNeeded(for: deviceID)
            WidgetDataSyncCoordinator.syncAllDevices()
            return true
        }
    }

    func applyLocationSnapshots(
        _ snapshots: [DeviceLocationSnapshot],
        removingMissingDeviceIDs missingDeviceIDs: Set<String> = [],
        forceGeocoding: Bool = false
    ) {
        var snapshotsByID: [String: DeviceLocationSnapshot] = [:]
        for snapshot in snapshots {
            guard !snapshot.deviceID.isEmpty else { continue }
            if let existing = snapshotsByID[snapshot.deviceID],
               existing.timestamp > snapshot.timestamp {
                continue
            }
            snapshotsByID[snapshot.deviceID] = snapshot
        }

        var remainingSnapshotIDs = Set(snapshotsByID.keys)
        var nextLocations: [CachedDeviceLocation] = []
        nextLocations.reserveCapacity(max(locations.count, snapshots.count))
        var deviceIDsNeedingGeocoding: [String] = []
        var didChange = false

        for existing in locations {
            if let snapshot = snapshotsByID[existing.deviceID] {
                remainingSnapshotIDs.remove(existing.deviceID)
                guard snapshot.timestamp >= existing.timestamp else {
                    nextLocations.append(existing)
                    continue
                }

                let updated = CachedDeviceLocation(
                    deviceID: snapshot.deviceID,
                    latitude: snapshot.latitude,
                    longitude: snapshot.longitude,
                    accuracy: snapshot.accuracy,
                    timestamp: snapshot.timestamp,
                    country: existing.country,
                    locality: existing.locality,
                    timeZone: existing.timeZone,
                    batteryLevel: snapshot.batteryLevel ?? existing.batteryLevel,
                    altitude: snapshot.altitude ?? existing.altitude,
                    speed: snapshot.speed ?? existing.speed
                )
                nextLocations.append(updated)
                didChange = true

                let moved = existing.latitude != snapshot.latitude || existing.longitude != snapshot.longitude
                if moved {
                    let hasPlacemark = (existing.country != nil) || (existing.locality != nil)
                    let oldLocation = CLLocation(latitude: existing.latitude, longitude: existing.longitude)
                    let newLocation = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
                    let distance = oldLocation.distance(from: newLocation)
                    if !hasPlacemark || distance >= geocodeDistanceThresholdMeters {
                        deviceIDsNeedingGeocoding.append(existing.deviceID)
                    }
                }
            } else if !missingDeviceIDs.contains(existing.deviceID) {
                nextLocations.append(existing)
            } else {
                didChange = true
            }
        }

        for snapshot in snapshotsByID.values where remainingSnapshotIDs.contains(snapshot.deviceID) {
            let newLocation = CachedDeviceLocation(
                deviceID: snapshot.deviceID,
                latitude: snapshot.latitude,
                longitude: snapshot.longitude,
                accuracy: snapshot.accuracy,
                timestamp: snapshot.timestamp,
                batteryLevel: snapshot.batteryLevel,
                altitude: snapshot.altitude,
                speed: snapshot.speed
            )
            nextLocations.append(newLocation)
            deviceIDsNeedingGeocoding.append(snapshot.deviceID)
            didChange = true
        }

        if didChange {
            locations = nextLocations
        }

        if forceGeocoding {
            for location in (didChange ? nextLocations : locations) {
                enqueueGeocodingIfNeeded(for: location.deviceID, force: true)
            }
        } else {
            for deviceID in deviceIDsNeedingGeocoding {
                enqueueGeocodingIfNeeded(for: deviceID, force: true)
            }
        }

        if didChange {
            WidgetDataSyncCoordinator.syncAllDevices()
        }
    }

    func ingestServerLocations(
        _ locations: [MiataruLocationData],
        removingMissingDeviceIDs missingDeviceIDs: Set<String> = [],
        forceGeocoding: Bool = false
    ) {
        let snapshots = locations.map { location in
            DeviceLocationSnapshot(
                deviceID: location.Device,
                latitude: location.Latitude,
                longitude: location.Longitude,
                accuracy: location.HorizontalAccuracy,
                timestamp: location.TimestampDate,
                batteryLevel: location.BatteryLevel,
                altitude: location.Altitude,
                speed: location.Speed
            )
        }

        applyLocationSnapshots(
            snapshots,
            removingMissingDeviceIDs: missingDeviceIDs,
            forceGeocoding: forceGeocoding
        )
    }

    func ingestLatestHistoryEntry(_ entries: [MiataruLocationData], for deviceID: String) {
        let normalizedTargetID = normalizedDeviceID(deviceID)
        guard !normalizedTargetID.isEmpty else { return }
        let matchingEntries = entries.filter { normalizedDeviceID($0.Device) == normalizedTargetID }
        guard let latestEntry = matchingEntries.max(by: { $0.TimestampDate < $1.TimestampDate }) else { return }
        ingestServerLocations([latestEntry])
    }

    func updateRecentVisitors(
        from visitors: [MiataruVisitor],
        ownDeviceID: String,
        window: TimeInterval = 90,
        now: Date = Date()
    ) {
        let normalizedOwnDeviceID = normalizedDeviceID(ownDeviceID)
        let cutoff = now.addingTimeInterval(-window)
        let recentVisitorDeviceIDs = Set(
            visitors
                .filter { $0.TimeStampDate >= cutoff }
                .map { normalizedDeviceID($0.DeviceID) }
                .filter { !$0.isEmpty && $0 != normalizedOwnDeviceID }
        )
        setRecentVisitorDeviceIDs(recentVisitorDeviceIDs)
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
                altitude: loc.altitude,
                speed: loc.speed
            )
            locations[idx] = updated
            WidgetDataSyncCoordinator.syncAllDevices()
        }
    }
    
    func removeLocation(for deviceID: String) {
        locations.removeAll { $0.deviceID == deviceID }
        WidgetDataSyncCoordinator.syncAllDevices()
    }

    @discardableResult
    func prune(
        retainingDeviceIDs retainedDeviceIDs: Set<String>,
        unknownDeviceTTL: TimeInterval = 7 * 24 * 60 * 60,
        now: Date = Date()
    ) -> Int {
        let retainedIDs = Set(retainedDeviceIDs.map(normalizedDeviceID).filter { !$0.isEmpty })
        let ttl = max(0, unknownDeviceTTL)
        var removedDeviceIDs = Set<String>()

        let nextLocations = locations.filter { location in
            let normalizedID = normalizedDeviceID(location.deviceID)
            guard !normalizedID.isEmpty else {
                return false
            }
            if retainedIDs.contains(normalizedID) {
                return true
            }
            let shouldKeep = now.timeIntervalSince(location.timestamp) <= ttl
            if !shouldKeep {
                removedDeviceIDs.insert(normalizedID)
            }
            return shouldKeep
        }

        let removedCount = locations.count - nextLocations.count
        guard removedCount > 0 else { return 0 }

        locations = nextLocations
        geocodeQueue.removeAll { removedDeviceIDs.contains(normalizedDeviceID($0)) }
        WidgetDataSyncCoordinator.syncAllDevices()
        return removedCount
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
        recentVisitorDeviceIDs = Set(
            deviceIDs
                .map { normalizedDeviceID($0) }
                .filter { !$0.isEmpty }
        )
    }
    
    /// Checks if a device has looked for the current user's device in the past 90 seconds
    func hasRecentVisitor(deviceID: String) -> Bool {
        return recentVisitorDeviceIDs.contains(normalizedDeviceID(deviceID))
    }

    private func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
