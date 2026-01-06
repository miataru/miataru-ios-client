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
    private static let snapshotPrefix = "MapSnapshot-"
    private static let snapshotExtension = "png"

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
}

