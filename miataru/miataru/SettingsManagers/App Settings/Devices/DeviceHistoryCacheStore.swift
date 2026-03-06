/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceHistoryCacheStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import Combine
import MiataruAPIClient

class DeviceHistoryCacheStore: ObservableObject {
    static let shared = DeviceHistoryCacheStore()
    static let activeHistoryCacheMaxAge: TimeInterval = 120
    private static let knownLocationLeadTolerance: TimeInterval = 60

    private struct CachedHistoryEntry {
        let history: [MiataruLocationData]
        let fetchedAt: Date
        let newestTimestamp: Date?
    }

    @Published private var histories: [String: CachedHistoryEntry] = [:]
    private init() {}

    func setHistory(_ history: [MiataruLocationData], for deviceID: String, fetchedAt: Date = Date()) {
        let newestTimestamp = history.map(\.TimestampDate).max()
        histories[deviceID] = CachedHistoryEntry(
            history: history,
            fetchedAt: fetchedAt,
            newestTimestamp: newestTimestamp
        )
    }

    func getHistory(for deviceID: String) -> [MiataruLocationData]? {
        histories[deviceID]?.history
    }

    func removeHistory(for deviceID: String) {
        histories.removeValue(forKey: deviceID)
    }

    func shouldRefreshHistory(for deviceID: String,
                              latestKnownLocationTimestamp: Date?,
                              maxAge: TimeInterval = DeviceHistoryCacheStore.activeHistoryCacheMaxAge) -> Bool {
        guard let entry = histories[deviceID] else { return true }

        if maxAge > 0, Date().timeIntervalSince(entry.fetchedAt) > maxAge {
            return true
        }

        guard let latestKnownLocationTimestamp else {
            return false
        }

        if let newestTimestamp = entry.newestTimestamp {
            return latestKnownLocationTimestamp.timeIntervalSince(newestTimestamp) > Self.knownLocationLeadTolerance
        }

        return latestKnownLocationTimestamp.timeIntervalSince(entry.fetchedAt) > Self.knownLocationLeadTolerance
    }

}
