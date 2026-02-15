/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * SharedWidgetConfig.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation

/// Lightweight configuration that mirrors the settings widgets need to reach the server.
struct SharedWidgetConfig: Codable {
    let miataruServerURL: String
    let deviceIDs: [String]
    let ownDeviceID: String?
    let ownDeviceKey: String?
    let authorizationToken: String?
}

enum SharedWidgetConfigManager {
    private static let configFileName = "SharedWidgetConfig.json"

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedWidgetDataManager.appGroupIdentifier)
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
            debugLog("Failed to write shared widget config: \(error)")
        }
    }

    static func read() -> SharedWidgetConfig? {
        guard let url = configURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(SharedWidgetConfig.self, from: data)
        } catch {
            debugLog("Failed to decode shared widget config: \(error)")
            return nil
        }
    }
}
