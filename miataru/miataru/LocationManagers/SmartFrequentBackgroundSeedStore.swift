/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * SmartFrequentBackgroundSeedStore.swift
 * miataru
 */

import Foundation
import CoreLocation

/// Keeps the latest usable Smart frequent seed in one preferences value.
/// The eight values written by earlier builds remain readable during migration.
struct SmartFrequentBackgroundSeedStore {
    static let snapshotKey = "miataru_smartFrequentBackgroundSeedSnapshot"

    private enum LegacyKey {
        static let latitude = "miataru_smartFrequentBackgroundSeedLatitude"
        static let longitude = "miataru_smartFrequentBackgroundSeedLongitude"
        static let altitude = "miataru_smartFrequentBackgroundSeedAltitude"
        static let horizontalAccuracy = "miataru_smartFrequentBackgroundSeedHorizontalAccuracy"
        static let verticalAccuracy = "miataru_smartFrequentBackgroundSeedVerticalAccuracy"
        static let course = "miataru_smartFrequentBackgroundSeedCourse"
        static let speed = "miataru_smartFrequentBackgroundSeedSpeed"
        static let timestamp = "miataru_smartFrequentBackgroundSeedTimestamp"

        static let all = [
            latitude, longitude, altitude, horizontalAccuracy,
            verticalAccuracy, course, speed, timestamp
        ]
    }

    private struct Snapshot {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let course: Double
        let speed: Double
        let timestamp: Date

        init(location: CLLocation) {
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            altitude = location.altitude.isFinite ? location.altitude : 0
            horizontalAccuracy = location.horizontalAccuracy
            verticalAccuracy = location.verticalAccuracy.isFinite ? location.verticalAccuracy : -1
            course = location.course.isFinite ? location.course : -1
            speed = location.speed.isFinite ? location.speed : -1
            timestamp = location.timestamp
        }

        init?(dictionary: [String: Any]) {
            guard dictionary["version"] as? Int == 1,
                  let latitude = dictionary["latitude"] as? Double,
                  let longitude = dictionary["longitude"] as? Double,
                  let altitude = dictionary["altitude"] as? Double,
                  let horizontalAccuracy = dictionary["horizontalAccuracy"] as? Double,
                  let verticalAccuracy = dictionary["verticalAccuracy"] as? Double,
                  let course = dictionary["course"] as? Double,
                  let speed = dictionary["speed"] as? Double,
                  let timestamp = dictionary["timestamp"] as? Date else {
                return nil
            }
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
            self.course = course
            self.speed = speed
            self.timestamp = timestamp
        }

        init?(legacy userDefaults: UserDefaults) {
            guard let latitude = userDefaults.object(forKey: LegacyKey.latitude) as? Double,
                  let longitude = userDefaults.object(forKey: LegacyKey.longitude) as? Double,
                  let horizontalAccuracy = userDefaults.object(forKey: LegacyKey.horizontalAccuracy) as? Double,
                  let timestamp = userDefaults.object(forKey: LegacyKey.timestamp) as? Date else {
                return nil
            }
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = userDefaults.object(forKey: LegacyKey.altitude) as? Double ?? 0
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = userDefaults.object(forKey: LegacyKey.verticalAccuracy) as? Double ?? -1
            self.course = userDefaults.object(forKey: LegacyKey.course) as? Double ?? -1
            self.speed = userDefaults.object(forKey: LegacyKey.speed) as? Double ?? -1
            self.timestamp = timestamp
        }

        var dictionary: [String: Any] {
            [
                "version": 1,
                "latitude": latitude,
                "longitude": longitude,
                "altitude": altitude,
                "horizontalAccuracy": horizontalAccuracy,
                "verticalAccuracy": verticalAccuracy,
                "course": course,
                "speed": speed,
                "timestamp": timestamp
            ]
        }

        func location(now: Date, inactivityWindow: TimeInterval) -> CLLocation? {
            SmartFrequentBackgroundPolicy.seedLocation(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                verticalAccuracy: verticalAccuracy,
                course: course,
                speed: speed,
                timestamp: timestamp,
                now: now,
                inactivityWindow: inactivityWindow
            )
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func save(_ location: CLLocation, maximumAccuracy: CLLocationAccuracy) {
        guard location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.timestamp.timeIntervalSince1970.isFinite,
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumAccuracy else {
            return
        }

        // One complete value avoids eight preference mutations and partial seeds.
        userDefaults.set(Snapshot(location: location).dictionary, forKey: Self.snapshotKey)
    }

    func load(now: Date, inactivityWindow: TimeInterval) -> CLLocation? {
        let rawSnapshot = userDefaults.object(forKey: Self.snapshotKey)
        let snapshot = userDefaults.dictionary(forKey: Self.snapshotKey).flatMap(Snapshot.init(dictionary:))
        let legacy = Snapshot(legacy: userDefaults)
        let candidates = [snapshot, legacy].compactMap { $0 }.sorted { $0.timestamp > $1.timestamp }
        for candidate in candidates {
            if let location = candidate.location(now: now, inactivityWindow: inactivityWindow) {
                return location
            }
        }
        // Remove seeds that were decoded but are no longer usable. Preserve an
        // unreadable snapshot so a transient preferences read cannot erase it.
        if !candidates.isEmpty, rawSnapshot == nil || snapshot != nil {
            clear()
        }
        return nil
    }

    func clear() {
        userDefaults.removeObject(forKey: Self.snapshotKey)
        LegacyKey.all.forEach { userDefaults.removeObject(forKey: $0) }
    }
}
