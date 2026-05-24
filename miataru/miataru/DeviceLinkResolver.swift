/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLinkResolver.swift
 * miataru
 *
 * Created by Codex on 24.05.26.
 */

import Foundation

enum DeviceLinkResolver {
    static let miataruScheme = "miataru"
    static let canonicalPrefix = "miataru://"

    static func urlString(for deviceID: String) -> String {
        "\(canonicalPrefix)\(deviceID)"
    }

    static func deviceID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == miataruScheme else { return nil }

        let rawDeviceID: String
        if let host = url.host, !host.isEmpty {
            rawDeviceID = host
        } else {
            rawDeviceID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        return normalizedDeviceID(rawDeviceID)
    }

    static func deviceID(fromCanonicalCode rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.lowercased().hasPrefix(canonicalPrefix) else { return nil }

        let rawDeviceID = String(trimmedValue.dropFirst(canonicalPrefix.count))
        return normalizedDeviceID(rawDeviceID)
    }

    static func normalizedDeviceID(_ rawValue: String) -> String? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    @MainActor
    static func canonicalKnownDeviceID(for rawValue: String, store: KnownDeviceStore = .shared) -> String? {
        guard let normalizedDeviceID = normalizedDeviceID(rawValue) else { return nil }
        return store.devices.first {
            self.normalizedDeviceID($0.DeviceID) == normalizedDeviceID
        }?.DeviceID
    }
}
