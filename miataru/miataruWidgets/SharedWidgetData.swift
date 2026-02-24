/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * SharedWidgetData.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct WidgetColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

struct WidgetDeviceData: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let locality: String?
    let country: String?
    let timestamp: Date
    let accuracy: Double?
    let color: WidgetColor?
}

struct WidgetSharedPayload: Codable {
    var devices: [WidgetDeviceData]
    var ownDeviceID: String?
    var ownDevice: WidgetDeviceData?
}

enum SharedWidgetDataManager {
    static let appGroupIdentifier = "group.com.miataru.ios"
    private static let sharedDataFileName = "SharedDeviceData.json"
    // IMPORTANT: Widget snapshots must not share filenames with app-side snapshots.
    // Otherwise the app can overwrite the widget image while the widget text comes from fresh widget data.
    private static let snapshotPrefix = "WidgetMapSnapshot-"
    private static let snapshotExtension = "png"
    private static let widgetRequestCountKey = "miataru_widgetRequestCount"
    private static let widgetRequestLastResetKey = "miataru_widgetRequestLastReset"
    private static let legacyWidgetRequestTimestampsKey = "miataru_widgetRequestTimestamps"

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var sharedDataURL: URL? {
        sharedContainerURL?.appendingPathComponent(sharedDataFileName)
    }

    static func mapSnapshotURL(for deviceID: String, style: UIUserInterfaceStyle? = nil) -> URL? {
        #if canImport(UIKit)
        let suffix: String
        if let style {
            switch style {
            case .dark: suffix = "-dark"
            case .light: suffix = "-light"
            default: suffix = ""
            }
        } else {
            suffix = ""
        }
        #else
        let suffix = ""
        #endif
        return sharedContainerURL?.appendingPathComponent("\(snapshotPrefix)\(deviceID)\(suffix).\(snapshotExtension)")
    }

    static func write(_ payload: WidgetSharedPayload) {
        guard let url = sharedDataURL else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Failed to write shared widget data: \(error)")
        }
    }

    static func read() -> WidgetSharedPayload? {
        guard let url = sharedDataURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetSharedPayload.self, from: data)
        } catch {
            print("Failed to decode shared widget data: \(error)")
            return nil
        }
    }
    
    /// Records a widget-initiated location request for the current local calendar day.
    /// This can be called from the widget extension to track requests.
    static func recordWidgetRequest() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let now = Date()
        migrateLegacyWidgetRequestTimestampsIfNeeded(userDefaults: userDefaults, now: now)

        let todayStart = Calendar.current.startOfDay(for: now)
        let lastReset = userDefaults.object(forKey: widgetRequestLastResetKey) as? Date
        let currentCount: Int
        if let lastReset, lastReset >= todayStart {
            currentCount = userDefaults.integer(forKey: widgetRequestCountKey)
        } else {
            currentCount = 0
        }
        userDefaults.set(currentCount + 1, forKey: widgetRequestCountKey)
        userDefaults.set(todayStart, forKey: widgetRequestLastResetKey)
    }

    private static func migrateLegacyWidgetRequestTimestampsIfNeeded(userDefaults: UserDefaults, now: Date) {
        if userDefaults.object(forKey: widgetRequestCountKey) != nil {
            return
        }
        guard let timestamps = loadLegacyWidgetRequestTimestamps(userDefaults: userDefaults) else { return }
        let todayStart = Calendar.current.startOfDay(for: now)
        let count = timestamps.filter { $0 >= todayStart }.count
        userDefaults.set(count, forKey: widgetRequestCountKey)
        userDefaults.set(todayStart, forKey: widgetRequestLastResetKey)
        userDefaults.removeObject(forKey: legacyWidgetRequestTimestampsKey)
    }

    /// Loads legacy widget request timestamps; supports both [Double] (seconds since 1970) and [Date].
    private static func loadLegacyWidgetRequestTimestamps(userDefaults: UserDefaults) -> [Date]? {
        guard let data = userDefaults.data(forKey: legacyWidgetRequestTimestampsKey) else { return nil }
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
