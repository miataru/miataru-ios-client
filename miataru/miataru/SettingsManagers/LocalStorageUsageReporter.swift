/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocalStorageUsageReporter.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import Foundation

struct LocalStorageUsageSnapshot: Equatable {
    let generatedAt: Date
    let entries: [LocalStorageUsageEntry]

    static let empty = LocalStorageUsageSnapshot(generatedAt: .distantPast, entries: [])

    var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.byteCount }
    }
}

struct LocalStorageUsageEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let byteCount: Int64
    let itemCount: Int?

    var byteText: String {
        LocalStorageUsageReporter.byteCountText(byteCount)
    }

    var itemCountText: String? {
        guard let itemCount else { return nil }
        let format = NSLocalizedString("local_storage_item_count_format", comment: "Storage statistic item count. Argument: number of items.")
        return String.localizedStringWithFormat(format, itemCount)
    }
}

enum LocalStorageUsageReporter {
    @MainActor
    static func snapshot(
        generatedAt: Date = Date(),
        fileManager: FileManager = .default
    ) async -> LocalStorageUsageSnapshot {
        var entries: [LocalStorageUsageEntry] = []

        let automationInfo = await MiataruAutomationEventStore.shared.storageInfo()
        entries.append(LocalStorageUsageEntry(
            id: "automationEvents",
            title: NSLocalizedString("local_storage_automation_events_title", comment: "Local storage row title for automation events"),
            byteCount: automationInfo.fileSizeBytes,
            itemCount: automationInfo.recordCount
        ))

        entries.append(fileEntry(
            id: "locationDiagnostics",
            title: NSLocalizedString("local_storage_location_diagnostics_title", comment: "Local storage row title for location diagnostics log"),
            url: LocationDiagnosticsLogStore.storageFileURL(fileManager: fileManager),
            itemCount: LocationDiagnosticsLogStore.shared.entries.count + LocationDiagnosticsLogStore.shared.coalescedCounts.count,
            fileManager: fileManager
        ))

        entries.append(fileEntry(
            id: "locationUpdateOutbox",
            title: NSLocalizedString("local_storage_location_update_outbox_title", comment: "Local storage row title for queued location updates"),
            url: LocationUpdateOutboxStore.storageFileURL(),
            itemCount: LocationManager.shared.pendingLocationUpdateCount,
            fileManager: fileManager
        ))

        entries.append(fileEntry(
            id: "knownDevices",
            title: NSLocalizedString("local_storage_known_devices_title", comment: "Local storage row title for known devices"),
            url: AppDirectories.applicationSupportFile(named: "knownDevices.plist"),
            itemCount: KnownDeviceStore.shared.devices.count,
            fileManager: fileManager
        ))

        entries.append(fileEntry(
            id: "deviceGroups",
            title: NSLocalizedString("local_storage_device_groups_title", comment: "Local storage row title for device groups"),
            url: AppDirectories.applicationSupportFile(named: "deviceGroups.plist"),
            itemCount: DeviceGroupStore.shared.groups.count,
            fileManager: fileManager
        ))

        entries.append(fileEntry(
            id: "deviceLocationCache",
            title: NSLocalizedString("local_storage_device_location_cache_title", comment: "Local storage row title for cached device locations"),
            url: AppDirectories.applicationSupportFile(named: "deviceLocations.plist"),
            itemCount: DeviceLocationCacheStore.shared.locations.count,
            fileManager: fileManager
        ))

        entries.append(fileEntry(
            id: "thisDeviceID",
            title: NSLocalizedString("local_storage_device_identity_title", comment: "Local storage row title for this device identity"),
            url: AppDirectories.applicationSupportFile(named: "deviceIDmodern.txt"),
            itemCount: 1,
            fileManager: fileManager
        ))

        if let widgetDataURL = SharedWidgetDataManager.sharedDataURL {
            entries.append(fileEntry(
                id: "widgetSharedData",
                title: NSLocalizedString("local_storage_widget_data_title", comment: "Local storage row title for shared widget data"),
                url: widgetDataURL,
                itemCount: nil,
                fileManager: fileManager
            ))
        }

        if let widgetConfigURL = SharedWidgetConfigManager.configURL {
            entries.append(fileEntry(
                id: "widgetConfig",
                title: NSLocalizedString("local_storage_widget_config_title", comment: "Local storage row title for shared widget configuration"),
                url: widgetConfigURL,
                itemCount: nil,
                fileManager: fileManager
            ))
        }

        if let widgetSnapshotEntry = widgetSnapshotEntry(fileManager: fileManager) {
            entries.append(widgetSnapshotEntry)
        }

        let sloganStore = DeviceSloganCacheStore.shared
        entries.append(LocalStorageUsageEntry(
            id: "deviceSlogans",
            title: NSLocalizedString("local_storage_device_slogans_title", comment: "Local storage row title for cached device slogans"),
            byteCount: sloganStore.estimatedStorageBytes,
            itemCount: sloganStore.storageItemCount
        ))

        let ignoredVisitorCount = IgnoredVisitorDeviceStore.shared.getAllIgnoredDeviceIDs().count
        entries.append(LocalStorageUsageEntry(
            id: "ignoredVisitors",
            title: NSLocalizedString("local_storage_ignored_visitors_title", comment: "Local storage row title for ignored visitor devices"),
            byteCount: estimatedStringArrayBytes(IgnoredVisitorDeviceStore.shared.getAllIgnoredDeviceIDs()),
            itemCount: ignoredVisitorCount
        ))

        return LocalStorageUsageSnapshot(
            generatedAt: generatedAt,
            entries: entries.filter { $0.byteCount > 0 || ($0.itemCount ?? 0) > 0 }
        )
    }

    static func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesActualByteCount = bytes < 1_024
        return formatter.string(fromByteCount: max(0, bytes))
    }

    static func fileSize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    static func directorySize(
        at directory: URL,
        matching shouldInclude: (URL) -> Bool,
        fileManager: FileManager = .default
    ) -> (bytes: Int64, count: Int) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }

        var bytes: Int64 = 0
        var count = 0
        for url in urls where shouldInclude(url) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else {
                continue
            }
            bytes += Int64(values.fileSize ?? 0)
            count += 1
        }
        return (bytes, count)
    }

    private static func fileEntry(
        id: String,
        title: String,
        url: URL,
        itemCount: Int?,
        fileManager: FileManager
    ) -> LocalStorageUsageEntry {
        LocalStorageUsageEntry(
            id: id,
            title: title,
            byteCount: fileSize(at: url, fileManager: fileManager),
            itemCount: itemCount
        )
    }

    private static func widgetSnapshotEntry(fileManager: FileManager) -> LocalStorageUsageEntry? {
        var bytes: Int64 = 0
        var count = 0

        if let directory = SharedWidgetDataManager.mapSnapshotDirectoryURL() {
            let result = directorySize(at: directory, matching: isWidgetSnapshotFile, fileManager: fileManager)
            bytes += result.bytes
            count += result.count
        }

        if let sharedContainerURL = SharedWidgetDataManager.sharedContainerURL {
            let result = directorySize(at: sharedContainerURL, matching: isWidgetSnapshotFile, fileManager: fileManager)
            bytes += result.bytes
            count += result.count
        }

        guard bytes > 0 || count > 0 else { return nil }
        return LocalStorageUsageEntry(
            id: "widgetSnapshots",
            title: NSLocalizedString("local_storage_widget_snapshots_title", comment: "Local storage row title for widget map snapshots"),
            byteCount: bytes,
            itemCount: count
        )
    }

    private static func isWidgetSnapshotFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.hasSuffix(".png") else { return false }
        return name.hasPrefix("MapSnapshot-") || name.hasPrefix("WidgetMapSnapshot-")
    }

    private static func estimatedStringArrayBytes(_ values: [String]) -> Int64 {
        Int64(values.reduce(0) { $0 + $1.utf8.count })
    }
}

extension Notification.Name {
    static let miataruLocalStorageUsageDidChange = Notification.Name("miataruLocalStorageUsageDidChange")
}
