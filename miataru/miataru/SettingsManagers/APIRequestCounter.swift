/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * APIRequestCounter.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 31.01.26.
 */

import Foundation
import Combine

/// Centralized manager for counting API requests since local midnight.
/// Persists per-request-type daily counts in UserDefaults.
final class APIRequestCounter: ObservableObject {
    static let shared = APIRequestCounter()

    enum RequestType: String, CaseIterable {
        case updateLocation
        case getVisitorHistory
        case getLocation
        case getLocationHistory
    }

    @Published private(set) var updatedLocationCallsToday: Int = 0
    @Published private(set) var getVisitorHistoryCallsToday: Int = 0
    @Published private(set) var getLocationCallsToday: Int = 0
    @Published private(set) var getLocationHistoryCallsToday: Int = 0

    private let userDefaults: UserDefaults
    private let countsKey = "miataru_apiRequestCounts"
    private let lastResetKey = "miataru_apiRequestCountsLastReset"
    private let legacyTimestampsKey = "miataru_apiRequestTimestamps"

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        migrateLegacyTimestampsIfNeeded()
        updateCounts()
    }

    func record(_ type: RequestType, now: Date = Date()) {
        var counts = normalizedCounts(now: now)
        counts[type.rawValue, default: 0] += 1
        saveCounts(counts, now: now)
        publishCounts(from: counts)
    }

    func updateCounts(now: Date = Date()) {
        let counts = normalizedCounts(now: now)
        saveCounts(counts, now: now)
        publishCounts(from: counts)
    }

    private func publishCounts(from counts: [String: Int]) {
        let updateLocationCount = counts[RequestType.updateLocation.rawValue] ?? 0
        let getVisitorHistoryCount = counts[RequestType.getVisitorHistory.rawValue] ?? 0
        let getLocationCount = counts[RequestType.getLocation.rawValue] ?? 0
        let getLocationHistoryCount = counts[RequestType.getLocationHistory.rawValue] ?? 0

        let updateBlock = {
            self.updatedLocationCallsToday = updateLocationCount
            self.getVisitorHistoryCallsToday = getVisitorHistoryCount
            self.getLocationCallsToday = getLocationCount
            self.getLocationHistoryCallsToday = getLocationHistoryCount
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    private func normalizedCounts(now: Date) -> [String: Int] {
        var counts = emptyCounts()
        let todayStart = Calendar.current.startOfDay(for: now)
        let lastReset = userDefaults.object(forKey: lastResetKey) as? Date
        if let lastReset, lastReset >= todayStart {
            let persisted = loadCounts()
            for type in RequestType.allCases {
                counts[type.rawValue] = max(0, persisted[type.rawValue] ?? 0)
            }
        }
        return counts
    }

    private func emptyCounts() -> [String: Int] {
        var result: [String: Int] = [:]
        for type in RequestType.allCases {
            result[type.rawValue] = 0
        }
        return result
    }

    private func loadCounts() -> [String: Int] {
        guard let data = userDefaults.data(forKey: countsKey),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return counts
    }

    private func saveCounts(_ counts: [String: Int], now: Date) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        userDefaults.set(data, forKey: countsKey)
        userDefaults.set(Calendar.current.startOfDay(for: now), forKey: lastResetKey)
    }

    private func migrateLegacyTimestampsIfNeeded(now: Date = Date()) {
        if userDefaults.data(forKey: countsKey) != nil {
            return
        }
        guard let legacy = loadLegacyTimestamps() else { return }
        let todayStart = Calendar.current.startOfDay(for: now)
        var counts = emptyCounts()
        for type in RequestType.allCases {
            let perType = legacy[type.rawValue] ?? []
            counts[type.rawValue] = perType.filter { $0 >= todayStart }.count
        }
        saveCounts(counts, now: now)
        userDefaults.removeObject(forKey: legacyTimestampsKey)
    }

    /// Loads legacy timestamps; supports [String: [Double]] (seconds since 1970) and [String: [Date]].
    private func loadLegacyTimestamps() -> [String: [Date]]? {
        guard let data = userDefaults.data(forKey: legacyTimestampsKey) else { return nil }
        if let storedSeconds = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            var result: [String: [Date]] = [:]
            for (key, seconds) in storedSeconds {
                result[key] = seconds
                    .map { Date(timeIntervalSince1970: $0) }
                    .filter { $0.timeIntervalSince1970 > 0 }
            }
            return result.isEmpty ? nil : result
        }
        if let stored = try? JSONDecoder().decode([String: [Date]].self, from: data) {
            return stored.isEmpty ? nil : stored
        }
        return nil
    }
}
