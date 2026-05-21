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

struct WidgetDeviceSelectionData: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: WidgetColor?
}

struct WidgetSharedPayload: Codable {
    var devices: [WidgetDeviceData]
    var ownDeviceID: String?
    var ownDevice: WidgetDeviceData?
    var deviceSelections: [WidgetDeviceSelectionData]? = nil
}

enum SharedWidgetDataManager {
    static let appGroupIdentifier = "group.com.miataru.ios"
    private static let sharedDataFileName = "SharedDeviceData.json"
    private static let snapshotPrefix = "MapSnapshot-"
    private static let snapshotExtension = "png"
    private static let widgetSnapshotCacheDirectoryName = "WidgetSnapshots"
    private static let snapshotFilePrefixes = ["MapSnapshot-", "WidgetMapSnapshot-"]

    /// Location of the shared App Group container.
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Location of the JSON payload used by widgets to read the latest data.
    static var sharedDataURL: URL? {
        sharedContainerURL?.appendingPathComponent(sharedDataFileName)
    }

    /// Location of the map snapshot image for a specific device and appearance.
    static func mapSnapshotURL(for deviceID: String, style: Any? = nil, containerURL: URL? = nil) -> URL? {
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
        guard let directory = mapSnapshotDirectoryURL(containerURL: containerURL, createIfNeeded: true) else {
            return nil
        }
        return directory.appendingPathComponent("\(snapshotPrefix)\(deviceID)\(suffix).\(snapshotExtension)")
    }

    static func mapSnapshotDirectoryURL(containerURL: URL? = nil, createIfNeeded: Bool = false) -> URL? {
        guard let containerURL = containerURL ?? sharedContainerURL else { return nil }
        let directory = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(widgetSnapshotCacheDirectoryName, isDirectory: true)

        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }

        return directory
    }

    @discardableResult
    static func pruneMapSnapshots(
        retainingDeviceIDs retainedDeviceIDs: Set<String>,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> Int {
        guard let containerURL = containerURL ?? sharedContainerURL else { return 0 }
        let retainedIDs = Set(retainedDeviceIDs.map(normalizedDeviceID).filter { !$0.isEmpty })
        var removedCount = 0

        if let snapshotDirectory = mapSnapshotDirectoryURL(containerURL: containerURL) {
            removedCount += pruneSnapshotFiles(
                in: snapshotDirectory,
                retainingDeviceIDs: retainedIDs,
                removeAllSnapshots: false,
                fileManager: fileManager
            )
        }

        // Root-level snapshot files are legacy; current code writes into Library/Caches.
        removedCount += pruneSnapshotFiles(
            in: containerURL,
            retainingDeviceIDs: retainedIDs,
            removeAllSnapshots: true,
            fileManager: fileManager
        )

        return removedCount
    }

    private static func pruneSnapshotFiles(
        in directory: URL,
        retainingDeviceIDs retainedDeviceIDs: Set<String>,
        removeAllSnapshots: Bool,
        fileManager: FileManager
    ) -> Int {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removedCount = 0
        for file in files {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let snapshot = snapshotMetadata(for: file.lastPathComponent) else {
                continue
            }

            let shouldRemove = snapshot.isAtomicWriteTemp
                || removeAllSnapshots
                || !retainedDeviceIDs.contains(snapshot.deviceID)

            guard shouldRemove else { continue }
            do {
                try fileManager.removeItem(at: file)
                removedCount += 1
            } catch {
                debugLog("Failed to remove widget snapshot \(file.lastPathComponent): \(error)")
            }
        }

        return removedCount
    }

    private static func snapshotMetadata(for fileName: String) -> (deviceID: String, isAtomicWriteTemp: Bool)? {
        guard let pngRange = fileName.range(of: ".\(snapshotExtension)") else { return nil }
        let isAtomicWriteTemp = fileName[pngRange.upperBound...].hasPrefix(".sb-")
        let baseName = String(fileName[..<pngRange.lowerBound])

        for prefix in snapshotFilePrefixes where baseName.hasPrefix(prefix) {
            var deviceID = String(baseName.dropFirst(prefix.count))
            if deviceID.hasSuffix("-light") {
                deviceID.removeLast("-light".count)
            } else if deviceID.hasSuffix("-dark") {
                deviceID.removeLast("-dark".count)
            }

            let normalizedID = normalizedDeviceID(deviceID)
            guard !normalizedID.isEmpty else { return nil }
            return (normalizedID, isAtomicWriteTemp)
        }

        return nil
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
