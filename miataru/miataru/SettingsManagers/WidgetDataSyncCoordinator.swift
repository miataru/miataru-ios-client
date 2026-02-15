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

        let payload = buildPayload(devices: devices, locations: locations, ownDeviceID: ownDeviceID)
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
            ownDevice: ownDevice
        )
    }
}

// MARK: - Helpers

private enum WidgetDeviceDataBuilder {
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
