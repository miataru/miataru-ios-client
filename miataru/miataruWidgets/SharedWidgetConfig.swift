/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * SharedWidgetConfig.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation

struct SharedWidgetConfig: Codable {
    let miataruServerURL: String
    let deviceIDs: [String]
    let ownDeviceID: String?
    let ownDeviceKey: String?
    let authorizationToken: String?
}

enum SharedWidgetConfigManager {
    private static let configFileName = "SharedWidgetConfig.json"
    private static let appGroupIdentifier = "group.com.miataru.ios"

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var configURL: URL? {
        sharedContainerURL?.appendingPathComponent(configFileName)
    }

    static func write(_ config: SharedWidgetConfig) {
        guard let url = configURL else { return }
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Failed to write shared widget config: \(error)")
        }
    }

    static func read() -> SharedWidgetConfig? {
        guard let url = configURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SharedWidgetConfig.self, from: data)
        } catch {
            print("Failed to decode shared widget config: \(error)")
            return nil
        }
    }
}
