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

/// Common data structures and utilities used to exchange data between the main app
/// and the WidgetKit extension via the shared App Group container.
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
    private static let snapshotPrefix = "MapSnapshot-"
    private static let snapshotExtension = "png"

    /// Location of the shared App Group container.
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Location of the JSON payload used by widgets to read the latest data.
    static var sharedDataURL: URL? {
        sharedContainerURL?.appendingPathComponent(sharedDataFileName)
    }

    /// Location of the map snapshot image for a specific device and appearance.
    static func mapSnapshotURL(for deviceID: String, style: Any? = nil) -> URL? {
        let suffix: String
        #if canImport(UIKit)
        if let style = style as? UIUserInterfaceStyle {
            switch style {
            case .dark: suffix = "-dark"
            case .light: suffix = "-light"
            default: suffix = ""
            }
        } else {
            suffix = ""
        }
        #else
        suffix = ""
        #endif
        return sharedContainerURL?.appendingPathComponent("\(snapshotPrefix)\(deviceID)\(suffix).\(snapshotExtension)")
    }

    /// Persist a payload into the shared container.
    static func write(_ payload: WidgetSharedPayload) {
        guard let url = sharedDataURL else { return }
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
        } catch {
            debugLog("Failed to write shared widget data: \(error)")
        }
    }

    /// Load the last written payload from the shared container.
    static func read() -> WidgetSharedPayload? {
        guard let url = sharedDataURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetSharedPayload.self, from: data)
        } catch {
            debugLog("Failed to decode shared widget data: \(error)")
            return nil
        }
    }
}

