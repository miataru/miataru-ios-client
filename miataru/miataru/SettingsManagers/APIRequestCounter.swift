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

/// Centralized manager for counting API requests in the last 24 hours.
/// Stores timestamps as seconds since 1970 in UserDefaults so counts reset correctly as time passes.
final class APIRequestCounter: ObservableObject {
    static let shared = APIRequestCounter()

    enum RequestType: String, CaseIterable {
        case updateLocation
        case getVisitorHistory
        case getLocation
        case getLocationHistory
    }

    @Published private(set) var updatedLocationCallsLast24Hours: Int = 0
    @Published private(set) var getVisitorHistoryCallsLast24Hours: Int = 0
    @Published private(set) var getLocationCallsLast24Hours: Int = 0
    @Published private(set) var getLocationHistoryCallsLast24Hours: Int = 0

    private let userDefaults: UserDefaults
    private let timestampsKey = "miataru_apiRequestTimestamps"
    private let maxStoredTimestampsPerType = 2000
    private static let sevenDaysSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let twentyFourHoursSeconds: TimeInterval = 24 * 60 * 60

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        updateCounts()
    }

    func record(_ type: RequestType, now: Date = Date()) {
        var stored = loadTimestamps()
        var timestamps = stored[type.rawValue] ?? []
        timestamps.append(now)
        timestamps = prune(timestamps, now: now)
        stored[type.rawValue] = timestamps
        saveTimestamps(stored)
        updateCounts(now: now, stored: stored, persistPruned: false)
    }

    func updateCounts(now: Date = Date()) {
        let stored = loadTimestamps()
        updateCounts(now: now, stored: stored, persistPruned: true)
    }

    private func updateCounts(now: Date, stored: [String: [Date]], persistPruned: Bool) {
        let twentyFourHoursAgo = now.addingTimeInterval(-Self.twentyFourHoursSeconds)
        let pruned = normalizeStoredTimestamps(stored, now: now)

        let updateLocationCount = pruned[RequestType.updateLocation.rawValue]?.filter { $0 > twentyFourHoursAgo }.count ?? 0
        let getVisitorHistoryCount = pruned[RequestType.getVisitorHistory.rawValue]?.filter { $0 > twentyFourHoursAgo }.count ?? 0
        let getLocationCount = pruned[RequestType.getLocation.rawValue]?.filter { $0 > twentyFourHoursAgo }.count ?? 0
        let getLocationHistoryCount = pruned[RequestType.getLocationHistory.rawValue]?.filter { $0 > twentyFourHoursAgo }.count ?? 0

        updatePublishedCounts(
            updateLocation: updateLocationCount,
            getVisitorHistory: getVisitorHistoryCount,
            getLocation: getLocationCount,
            getLocationHistory: getLocationHistoryCount
        )

        if persistPruned {
            saveTimestamps(pruned)
        }
    }

    private func normalizeStoredTimestamps(_ stored: [String: [Date]], now: Date) -> [String: [Date]] {
        var normalized: [String: [Date]] = [:]
        for type in RequestType.allCases {
            let timestamps = stored[type.rawValue] ?? []
            normalized[type.rawValue] = prune(timestamps, now: now)
        }
        return normalized
    }

    private func prune(_ timestamps: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-Self.sevenDaysSeconds)
        var recent = timestamps.filter { $0 > cutoff }
        if recent.count > maxStoredTimestampsPerType {
            recent = Array(recent.suffix(maxStoredTimestampsPerType))
        }
        return recent
    }

    private func updatePublishedCounts(updateLocation: Int,
                                       getVisitorHistory: Int,
                                       getLocation: Int,
                                       getLocationHistory: Int) {
        let updateBlock = {
            self.updatedLocationCallsLast24Hours = updateLocation
            self.getVisitorHistoryCallsLast24Hours = getVisitorHistory
            self.getLocationCallsLast24Hours = getLocation
            self.getLocationHistoryCallsLast24Hours = getLocationHistory
        }

        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    /// Loads timestamps; supports [String: [Double]] (seconds since 1970) and legacy [String: [Date]].
    private func loadTimestamps() -> [String: [Date]] {
        guard let data = userDefaults.data(forKey: timestampsKey) else { return [:] }
        if let storedSeconds = try? JSONDecoder().decode([String: [Double]].self, from: data) {
            var result: [String: [Date]] = [:]
            for (key, seconds) in storedSeconds {
                result[key] = seconds
                    .map { Date(timeIntervalSince1970: $0) }
                    .filter { $0.timeIntervalSince1970 > 0 }
            }
            return result
        }
        if let stored = try? JSONDecoder().decode([String: [Date]].self, from: data) {
            return stored
        }
        return [:]
    }

    /// Saves timestamps as seconds since 1970 for unambiguous decoding and correct 24h rolloff.
    private func saveTimestamps(_ stored: [String: [Date]]) {
        var secondsStored: [String: [Double]] = [:]
        for (key, dates) in stored {
            secondsStored[key] = dates.map { $0.timeIntervalSince1970 }
        }
        guard let data = try? JSONEncoder().encode(secondsStored) else { return }
        userDefaults.set(data, forKey: timestampsKey)
    }
}
