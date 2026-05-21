/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetDataSyncCoordinator.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Bridges the main app data (devices + cached locations) into the App Group JSON
/// that widgets consume. All calls are lightweight and overwrite the shared file.
enum WidgetDataSyncCoordinator {
    /// Syncs all known devices and cached locations into the shared payload and refreshes widgets.
    static func syncAllDevices() {
        let devices = KnownDeviceStore.shared.devices
        let locations = DeviceLocationCacheStore.shared.locations
        let ownDeviceID = thisDeviceIDManager.shared.deviceID

        let payload = preservingNewerExistingWidgetData(
            in: buildPayload(devices: devices, locations: locations, ownDeviceID: ownDeviceID),
            devices: devices,
            ownDeviceID: ownDeviceID,
            existingPayload: SharedWidgetDataManager.read()
        )
        SharedWidgetDataManager.write(payload)
        syncWidgetConfig(
            serverURL: SettingsManager.shared.miataruServerURL,
            deviceIDs: devices.map { $0.DeviceID },
            ownDeviceID: ownDeviceID,
            ownDeviceKey: SettingsManager.shared.deviceKey,
            shouldReloadTimelines: false
        )

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Imports newer locations written by the widget extension back into the app cache.
    static func importNewerWidgetLocationsIntoAppCache() {
        guard let payload = SharedWidgetDataManager.read(),
              !payload.devices.isEmpty else {
            return
        }

        let cache = DeviceLocationCacheStore.shared
        let snapshots = payload.devices.map { device in
            let existing = cache.getLocation(for: device.id)
            return DeviceLocationSnapshot(
                deviceID: device.id,
                latitude: device.latitude,
                longitude: device.longitude,
                accuracy: device.accuracy ?? existing?.accuracy ?? 0,
                timestamp: device.timestamp,
                batteryLevel: existing?.batteryLevel,
                altitude: existing?.altitude,
                speed: existing?.speed
            )
        }
        cache.applyLocationSnapshots(snapshots)
    }

    /// Sync only the widget configuration (server + device IDs) into the shared container.
    static func syncWidgetConfig(serverURL: String,
                                 deviceIDs: [String],
                                 ownDeviceID: String,
                                 ownDeviceKey: String? = nil,
                                 shouldReloadTimelines: Bool = true) {
        let config = SharedWidgetConfig(
            miataruServerURL: serverURL,
            deviceIDs: deviceIDs,
            ownDeviceID: ownDeviceID,
            ownDeviceKey: ownDeviceKey,
            authorizationToken: nil
        )
        SharedWidgetConfigManager.write(config)

        #if canImport(WidgetKit)
        if shouldReloadTimelines {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    /// Builds the payload from the current stores.
    static func buildPayload(devices: [KnownDevice], locations: [CachedDeviceLocation], ownDeviceID: String) -> WidgetSharedPayload {
        var entries: [WidgetDeviceData] = []
        var ownDevice: WidgetDeviceData?
        let selections = devices.map { WidgetDeviceDataBuilder.makeSelection(device: $0) }

        for device in devices {
            guard let location = locations.first(where: { $0.deviceID == device.DeviceID }) else { continue }
            guard let entry = WidgetDeviceDataBuilder.makeEntry(device: device, location: location) else { continue }
            entries.append(entry)
            if device.DeviceID == ownDeviceID {
                ownDevice = entry
            }
        }

        return WidgetSharedPayload(
            devices: entries,
            ownDeviceID: ownDeviceID,
            ownDevice: ownDevice,
            deviceSelections: selections
        )
    }

    private static func preservingNewerExistingWidgetData(
        in payload: WidgetSharedPayload,
        devices: [KnownDevice],
        ownDeviceID: String,
        existingPayload: WidgetSharedPayload?
    ) -> WidgetSharedPayload {
        guard let existingPayload else { return payload }

        let knownDevicesByID = devices.reduce(into: [String: KnownDevice]()) { result, device in
            let normalizedID = normalizedDeviceID(device.DeviceID)
            guard !normalizedID.isEmpty else { return }
            result[normalizedID] = device
        }
        var entriesByID = payload.devices.reduce(into: [String: WidgetDeviceData]()) { result, entry in
            let normalizedID = normalizedDeviceID(entry.id)
            guard !normalizedID.isEmpty else { return }
            if let currentEntry = result[normalizedID],
               currentEntry.timestamp > entry.timestamp {
                return
            }
            result[normalizedID] = entry
        }

        for existingEntry in existingPayload.devices {
            let normalizedID = normalizedDeviceID(existingEntry.id)
            guard let knownDevice = knownDevicesByID[normalizedID] else { continue }

            if let currentEntry = entriesByID[normalizedID],
               currentEntry.timestamp >= existingEntry.timestamp {
                continue
            }

            entriesByID[normalizedID] = WidgetDeviceDataBuilder.makeEntry(
                device: knownDevice,
                widgetData: existingEntry
            )
        }

        let entries = devices.compactMap { entriesByID[normalizedDeviceID($0.DeviceID)] }
        return WidgetSharedPayload(
            devices: entries,
            ownDeviceID: ownDeviceID,
            ownDevice: entries.first { normalizedDeviceID($0.id) == normalizedDeviceID(ownDeviceID) },
            deviceSelections: devices.map { WidgetDeviceDataBuilder.makeSelection(device: $0) }
        )
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

// MARK: - Helpers

private enum WidgetDeviceDataBuilder {
    static func makeSelection(device: KnownDevice) -> WidgetDeviceSelectionData {
        WidgetDeviceSelectionData(
            id: device.DeviceID,
            name: device.DeviceName,
            color: WidgetColorFactory.color(from: device.DeviceColor)
        )
    }

    static func makeEntry(device: KnownDevice, location: CachedDeviceLocation) -> WidgetDeviceData? {
        WidgetDeviceData(
            id: device.DeviceID,
            name: device.DeviceName,
            latitude: location.latitude,
            longitude: location.longitude,
            locality: location.locality,
            country: location.country,
            timestamp: location.timestamp,
            accuracy: location.accuracy,
            color: WidgetColorFactory.color(from: device.DeviceColor)
        )
    }

    static func makeEntry(device: KnownDevice, widgetData: WidgetDeviceData) -> WidgetDeviceData {
        WidgetDeviceData(
            id: device.DeviceID,
            name: device.DeviceName,
            latitude: widgetData.latitude,
            longitude: widgetData.longitude,
            locality: widgetData.locality,
            country: widgetData.country,
            timestamp: widgetData.timestamp,
            accuracy: widgetData.accuracy,
            color: WidgetColorFactory.color(from: device.DeviceColor) ?? widgetData.color
        )
    }
}

private enum WidgetColorFactory {
    static func color(from uiColor: UIColor?) -> WidgetColor? {
        guard let uiColor else { return nil }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return WidgetColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }
}
