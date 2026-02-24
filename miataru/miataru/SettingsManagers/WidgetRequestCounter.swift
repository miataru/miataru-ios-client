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

/// Centralized manager for counting widget-initiated location requests since local midnight.
/// Stores a daily counter in App Group UserDefaults and exposes a shared observable instance for UI.
final class WidgetRequestCounter: ObservableObject {
    static let shared = WidgetRequestCounter()

    @Published private(set) var countToday: Int = 0

    private let userDefaults: UserDefaults
    private let countKey = "miataru_widgetRequestCount"
    private let lastResetKey = "miataru_widgetRequestLastReset"
    private let legacyTimestampsKey = "miataru_widgetRequestTimestamps"
    private static let appGroupIdentifier = "group.com.miataru.ios"

    private init(userDefaults: UserDefaults? = nil) {
        // Use App Group UserDefaults if available, otherwise fall back to standard UserDefaults
        if let appGroupDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            self.userDefaults = appGroupDefaults
        } else {
            self.userDefaults = userDefaults ?? .standard
        }
        migrateLegacyTimestampsIfNeeded()
        updateCount()
    }

    /// Records a widget-initiated location request for today.
    /// Note: Widget extensions call SharedWidgetDataManager.recordWidgetRequest() directly,
    /// but this method can also be used from the main app if needed.
    func recordRequest() {
        let now = Date()
        let currentCount = normalizedCount(now: now)
        let updatedCount = currentCount + 1
        saveCount(updatedCount, now: now)
        publishCount(updatedCount)
    }

    /// Updates the count of widget requests since local midnight.
    /// Call this when the view appears or periodically while the details screen is visible.
    func updateCount(now: Date = Date()) {
        let count = normalizedCount(now: now)
        saveCount(count, now: now)
        publishCount(count)
    }

    private func publishCount(_ count: Int) {
        let updateBlock = {
            self.countToday = count
        }
        if Thread.isMainThread {
            updateBlock()
        } else {
            DispatchQueue.main.async(execute: updateBlock)
        }
    }

    private func normalizedCount(now: Date) -> Int {
        let todayStart = Calendar.current.startOfDay(for: now)
        let lastReset = userDefaults.object(forKey: lastResetKey) as? Date
        guard let lastReset, lastReset >= todayStart else {
            return 0
        }
        return max(0, userDefaults.integer(forKey: countKey))
    }

    private func saveCount(_ count: Int, now: Date) {
        userDefaults.set(count, forKey: countKey)
        userDefaults.set(Calendar.current.startOfDay(for: now), forKey: lastResetKey)
    }

    private func migrateLegacyTimestampsIfNeeded(now: Date = Date()) {
        if userDefaults.object(forKey: countKey) != nil {
            return
        }
        guard let timestamps = loadLegacyTimestamps() else { return }
        let todayStart = Calendar.current.startOfDay(for: now)
        let count = timestamps.filter { $0 >= todayStart }.count
        saveCount(count, now: now)
        userDefaults.removeObject(forKey: legacyTimestampsKey)
    }

    /// Loads legacy timestamps from UserDefaults. Supports both [Double] (seconds since 1970) and [Date].
    private func loadLegacyTimestamps() -> [Date]? {
        guard let data = userDefaults.data(forKey: legacyTimestampsKey) else { return nil }
        if let seconds = try? JSONDecoder().decode([Double].self, from: data) {
            let timestamps = seconds.map { Date(timeIntervalSince1970: $0) }.filter { $0.timeIntervalSince1970 > 0 }
            return timestamps.isEmpty ? nil : timestamps
        }
        if let dates = try? JSONDecoder().decode([Date].self, from: data) {
            return dates.isEmpty ? nil : dates
        }
        return nil
    }
}
