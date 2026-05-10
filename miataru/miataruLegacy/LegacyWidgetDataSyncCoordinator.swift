/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LegacyWidgetDataSyncCoordinator.swift
 * miataru-iOS15
 *
 * iOS 15 compatibility target shim.
 */

import Foundation

enum WidgetDataSyncCoordinator {
    static func syncAllDevices() {}

    static func importNewerWidgetLocationsIntoAppCache() {}

    static func syncWidgetConfig(
        serverURL: String,
        deviceIDs: [String],
        ownDeviceID: String,
        ownDeviceKey: String? = nil,
        shouldReloadTimelines: Bool = true
    ) {}
}
