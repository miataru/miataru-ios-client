/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceSloganCacheStore.swift
 * miataru
 *
 * Created by Codex on 15.02.26.
 */

import Foundation
import MiataruAPIClient

@MainActor
final class DeviceSloganCacheStore: ObservableObject {
    static let shared = DeviceSloganCacheStore()

    @Published private(set) var slogansByDeviceID: [String: String]
    @Published private(set) var knownDeviceIDs: Set<String>

    private var lastFetchByDeviceID: [String: Date]
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let slogansByDeviceID = "device_slogans_by_device_id"
        static let knownDeviceIDs = "device_slogans_known_device_ids"
        static let lastFetchByDeviceID = "device_slogans_last_fetch_by_device_id"
    }

    private init() {
        self.slogansByDeviceID = defaults.dictionary(forKey: Keys.slogansByDeviceID) as? [String: String] ?? [:]
        self.knownDeviceIDs = Set(defaults.stringArray(forKey: Keys.knownDeviceIDs) ?? [])
        if let raw = defaults.dictionary(forKey: Keys.lastFetchByDeviceID) as? [String: TimeInterval] {
            self.lastFetchByDeviceID = raw.reduce(into: [:]) { partialResult, entry in
                partialResult[entry.key] = Date(timeIntervalSince1970: entry.value)
            }
        } else {
            self.lastFetchByDeviceID = [:]
        }
    }

    func slogan(for deviceID: String) -> String? {
        slogansByDeviceID[normalizedDeviceID(deviceID)]
    }

    func isKnown(for deviceID: String) -> Bool {
        knownDeviceIDs.contains(normalizedDeviceID(deviceID))
    }

    func cacheSlogan(_ slogan: String?, for deviceID: String) {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return }
        let normalizedSlogan = normalizedSloganValue(slogan)

        knownDeviceIDs.insert(normalizedID)

        if let normalizedSlogan {
            slogansByDeviceID[normalizedID] = normalizedSlogan
        } else {
            slogansByDeviceID.removeValue(forKey: normalizedID)
        }

        persist()
    }

    func shouldRefresh(for deviceID: String,
                       minimumRefreshInterval: TimeInterval = 300,
                       force: Bool = false) -> Bool {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return false }
        if force {
            return true
        }
        guard let lastFetch = lastFetchByDeviceID[normalizedID] else {
            return true
        }
        return Date().timeIntervalSince(lastFetch) >= minimumRefreshInterval
    }

    func ingestGetLocationResults(_ locations: [MiataruLocationData], requestedDeviceIDs: [String]) {
        let normalizedRequestedIDs = Set(requestedDeviceIDs.map(normalizedDeviceID).filter { !$0.isEmpty })
        let locationsByDeviceID = locations.reduce(into: [String: MiataruLocationData]()) { partialResult, location in
            let normalizedID = normalizedDeviceID(location.Device)
            guard !normalizedID.isEmpty else { return }
            partialResult[normalizedID] = location
        }
        let now = Date()

        for requestedID in normalizedRequestedIDs {
            lastFetchByDeviceID[requestedID] = now

            guard let location = locationsByDeviceID[requestedID] else {
                continue
            }

            knownDeviceIDs.insert(requestedID)
            let normalizedSlogan = normalizedSloganValue(location.DeviceSlogan)
            if let normalizedSlogan {
                slogansByDeviceID[requestedID] = normalizedSlogan
            } else {
                slogansByDeviceID.removeValue(forKey: requestedID)
            }
        }

        persist()
    }

    func markFreshNow(for deviceID: String) {
        let normalizedID = normalizedDeviceID(deviceID)
        guard !normalizedID.isEmpty else { return }
        markFetchAttempt(for: normalizedID, at: Date())
    }

    func migrateCachedEntry(from oldDeviceID: String, to newDeviceID: String) {
        let normalizedOldID = normalizedDeviceID(oldDeviceID)
        let normalizedNewID = normalizedDeviceID(newDeviceID)

        guard !normalizedOldID.isEmpty, !normalizedNewID.isEmpty, normalizedOldID != normalizedNewID else {
            return
        }

        if let cachedSlogan = slogansByDeviceID[normalizedOldID] {
            slogansByDeviceID[normalizedNewID] = cachedSlogan
        }
        if let lastFetch = lastFetchByDeviceID[normalizedOldID] {
            lastFetchByDeviceID[normalizedNewID] = lastFetch
        }
        if knownDeviceIDs.contains(normalizedOldID) {
            knownDeviceIDs.insert(normalizedNewID)
        }

        persist()
    }

    private func persist() {
        defaults.set(slogansByDeviceID, forKey: Keys.slogansByDeviceID)
        defaults.set(Array(knownDeviceIDs).sorted(), forKey: Keys.knownDeviceIDs)
        let serializedLastFetch = lastFetchByDeviceID.reduce(into: [String: TimeInterval]()) { partialResult, entry in
            partialResult[entry.key] = entry.value.timeIntervalSince1970
        }
        defaults.set(serializedLastFetch, forKey: Keys.lastFetchByDeviceID)
    }

    private func markFetchAttempt(for deviceID: String, at date: Date) {
        lastFetchByDeviceID[deviceID] = date
        persist()
    }

    private func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func normalizedSloganValue(_ slogan: String?) -> String? {
        guard let slogan else { return nil }
        let cleansed = MiataruAppAPI.cleanseDeviceSlogan(slogan)
        guard !cleansed.isEmpty else { return nil }
        return cleansed
    }
}
