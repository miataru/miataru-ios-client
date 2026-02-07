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
    private static let widgetRequestTimestampsKey = "miataru_widgetRequestTimestamps"
    private static let maxStoredTimestamps = 1000

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
    
    /// Records a widget-initiated location request timestamp.
    /// Uses seconds since 1970 so the main app's WidgetRequestCounter can compute "last 24 hours" reliably.
    /// This can be called from the widget extension to track requests.
    static func recordWidgetRequest() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        let now = Date()
        var timestamps: [Date] = loadWidgetRequestTimestamps(userDefaults: userDefaults)
        timestamps.append(now)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        timestamps = timestamps.filter { $0 > sevenDaysAgo }
        if timestamps.count > maxStoredTimestamps {
            timestamps = Array(timestamps.suffix(maxStoredTimestamps))
        }
        let seconds = timestamps.map { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(seconds) {
            userDefaults.set(data, forKey: widgetRequestTimestampsKey)
        }
    }

    /// Loads widget request timestamps; supports both [Double] (seconds since 1970) and legacy [Date].
    private static func loadWidgetRequestTimestamps(userDefaults: UserDefaults) -> [Date] {
        guard let data = userDefaults.data(forKey: widgetRequestTimestampsKey) else { return [] }
        if let seconds = try? JSONDecoder().decode([Double].self, from: data) {
            return seconds.map { Date(timeIntervalSince1970: $0) }.filter { $0.timeIntervalSince1970 > 0 }
        }
        if let dates = try? JSONDecoder().decode([Date].self, from: data) {
            return dates
        }
        return []
    }
}

