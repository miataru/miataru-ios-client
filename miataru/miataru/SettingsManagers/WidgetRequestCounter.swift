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
final class WidgetRequestCounter: ObservableObject {
    static let shared = WidgetRequestCounter()

    @Published private(set) var countLast24Hours: Int = 0

    private let userDefaults: UserDefaults
    private let timestampsKey = "miataru_widgetRequestTimestamps"
    private let maxStoredTimestamps = 1000 // Limit stored timestamps to prevent excessive storage
    private static let appGroupIdentifier = "group.com.miataru.ios"

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
        
        // Keep only recent timestamps (last 7 days) to prevent unbounded growth
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        timestamps = timestamps.filter { $0 > sevenDaysAgo }
        
        // Limit total stored timestamps
        if timestamps.count > maxStoredTimestamps {
            timestamps = Array(timestamps.suffix(maxStoredTimestamps))
        }
        
        saveTimestamps(timestamps)
        updateCount()
    }

    /// Updates the count of widget requests in the last 24 hours.
    /// Call this method to refresh the count, e.g., when the view appears.
    func updateCount() {
        let now = Date()
        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
        let timestamps = loadTimestamps()
        countLast24Hours = timestamps.filter { $0 > twentyFourHoursAgo }.count
    }

    /// Loads stored timestamps from UserDefaults.
    private func loadTimestamps() -> [Date] {
        guard let data = userDefaults.data(forKey: timestampsKey),
              let timestamps = try? JSONDecoder().decode([Date].self, from: data) else {
            return []
        }
        return timestamps
    }

    /// Saves timestamps to UserDefaults.
    private func saveTimestamps(_ timestamps: [Date]) {
        guard let data = try? JSONEncoder().encode(timestamps) else {
            return
        }
        userDefaults.set(data, forKey: timestampsKey)
    }
}
