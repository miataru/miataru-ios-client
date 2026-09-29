/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * PersistentDataCleanup.swift
 * miataru
 *
 * Created by Codex on 21.05.26.
 */

import Foundation
import UIKit

struct PersistentDataCleanupResult: Equatable {
    let removedLocationCount: Int
    let removedSloganCount: Int
    let removedSnapshotCount: Int

    var removedTotalCount: Int {
        removedLocationCount + removedSloganCount + removedSnapshotCount
    }
}

@MainActor
enum PersistentDataCleanup {
    static let unknownDeviceTTL: TimeInterval = 7 * 24 * 60 * 60

    @discardableResult
    static func run(now: Date = Date()) -> PersistentDataCleanupResult {
        // A background launch while protected files are unavailable must not
        // mistake unreadable stores for empty stores and prune valid user data.
        guard UIApplication.shared.isProtectedDataAvailable,
              let ownDeviceID = thisDeviceIDManager.shared.deviceIDIfAvailable,
              !KnownDeviceStore.shared.hasUnresolvedReadFailure else {
            return PersistentDataCleanupResult(removedLocationCount: 0, removedSloganCount: 0, removedSnapshotCount: 0)
        }
        return run(retainedDeviceIDs: currentRetainedDeviceIDs(ownDeviceID: ownDeviceID), now: now)
    }

    @discardableResult
    static func run(retainedDeviceIDs: Set<String>, now: Date = Date()) -> PersistentDataCleanupResult {
        let retainedIDs = normalizedDeviceIDs(retainedDeviceIDs)
        let removedLocationCount = DeviceLocationCacheStore.shared.prune(
            retainingDeviceIDs: retainedIDs,
            unknownDeviceTTL: unknownDeviceTTL,
            now: now
        )
        let removedSloganCount = DeviceSloganCacheStore.shared.prune(
            retainingDeviceIDs: retainedIDs,
            unknownDeviceTTL: unknownDeviceTTL,
            now: now
        )
        let removedSnapshotCount = SharedWidgetDataManager.pruneMapSnapshots(
            retainingDeviceIDs: retainedIDs
        )

        let result = PersistentDataCleanupResult(
            removedLocationCount: removedLocationCount,
            removedSloganCount: removedSloganCount,
            removedSnapshotCount: removedSnapshotCount
        )

        if result.removedTotalCount > 0 {
            debugLog("[PersistentDataCleanup] Removed locations=\(removedLocationCount), slogans=\(removedSloganCount), snapshots=\(removedSnapshotCount)")
        }

        return result
    }

    private static func currentRetainedDeviceIDs(ownDeviceID: String) -> Set<String> {
        var deviceIDs = Set(KnownDeviceStore.shared.devices.map(\.DeviceID))
        deviceIDs.insert(ownDeviceID)

        if let payload = SharedWidgetDataManager.read() {
            deviceIDs.formUnion(payload.devices.map(\.id))
            if let ownDeviceID = payload.ownDeviceID {
                deviceIDs.insert(ownDeviceID)
            }
            if let ownDevice = payload.ownDevice {
                deviceIDs.insert(ownDevice.id)
            }
            if let selections = payload.deviceSelections {
                deviceIDs.formUnion(selections.map(\.id))
            }
        }

        return normalizedDeviceIDs(deviceIDs)
    }

    private static func normalizedDeviceIDs(_ deviceIDs: Set<String>) -> Set<String> {
        Set(
            deviceIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }
}
