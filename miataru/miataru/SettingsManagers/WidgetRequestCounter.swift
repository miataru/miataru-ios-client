/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetRequestCounter.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 23.01.26.
 */

import Foundation
import Combine

/// Centralized manager for counting widget-initiated location requests in the last 24 hours.
/// Stores request timestamps in App Group UserDefaults and exposes a shared observable instance for UI.
/// Uses seconds since 1970 for storage so counts reset correctly as time passes.
final class WidgetRequestCounter: ObservableObject {
    static let shared = WidgetRequestCounter()

    @Published private(set) var countLast24Hours: Int = 0

    private let userDefaults: UserDefaults
    private let timestampsKey = "miataru_widgetRequestTimestamps"
    private let maxStoredTimestamps = 1000 // Limit stored timestamps to prevent excessive storage
    private static let appGroupIdentifier = "group.com.miataru.ios"
    private static let sevenDaysSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let twentyFourHoursSeconds: TimeInterval = 24 * 60 * 60

    private init(userDefaults: UserDefaults? = nil) {
        // Use App Group UserDefaults if available, otherwise fall back to standard UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            self.userDefaults = appGroupDefaults
        } else {
            self.userDefaults = userDefaults ?? .standard
        }
        updateCount()
    }

    /// Records a widget-initiated location request with the current timestamp.
    /// Note: Widget extensions call SharedWidgetDataManager.recordWidgetRequest() directly,
    /// but this method can also be used from the main app if needed.
    func recordRequest() {
        let now = Date()
        var timestamps = loadTimestamps()
        timestamps.append(now)
        let pruned = pruneToRetention(timestamps, now: now)
        saveTimestamps(pruned)
        updateCount()
    }

    /// Updates the count of widget requests in the last 24 hours.
    /// Prunes old timestamps from storage and persists so the count can decrease over time.
    /// Call this when the view appears or periodically while the details screen is visible.
    func updateCount() {
        let now = Date()
        let timestamps = loadTimestamps()
        let twentyFourHoursAgo = now.addingTimeInterval(-Self.twentyFourHoursSeconds)
        countLast24Hours = timestamps.filter { $0 > twentyFourHoursAgo }.count
        // Prune and persist so storage does not keep thousands of old entries; ensures count can drop
        let pruned = pruneToRetention(timestamps, now: now)
        if pruned.count != timestamps.count {
            saveTimestamps(pruned)
        }
    }

    /// Keeps only timestamps within the last 7 days and caps total count.
    private func pruneToRetention(_ timestamps: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-Self.sevenDaysSeconds)
        var recent = timestamps.filter { $0 > cutoff }
        if recent.count > maxStoredTimestamps {
            recent = Array(recent.suffix(maxStoredTimestamps))
        }
        return recent
    }

    /// Loads stored timestamps from UserDefaults. Supports both legacy [Date] and [Double] (seconds since 1970).
    private func loadTimestamps() -> [Date] {
        guard let data = userDefaults.data(forKey: timestampsKey) else { return [] }
        // Prefer explicit seconds-since-1970 for reliable 24h rolloff
        if let seconds = try? JSONDecoder().decode([Double].self, from: data) {
            return seconds.map { Date(timeIntervalSince1970: $0) }.filter { $0.timeIntervalSince1970 > 0 }
        }
        if let dates = try? JSONDecoder().decode([Date].self, from: data) {
            return dates
        }
        return []
    }

    /// Saves timestamps as seconds since 1970 for unambiguous decoding and correct 24h filtering.
    private func saveTimestamps(_ timestamps: [Date]) {
        let seconds = timestamps.map { $0.timeIntervalSince1970 }
        guard let data = try? JSONEncoder().encode(seconds) else { return }
        userDefaults.set(data, forKey: timestampsKey)
    }
}
