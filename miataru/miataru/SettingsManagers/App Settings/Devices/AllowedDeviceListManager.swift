/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * AllowedDeviceListManager.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import UIKit
import MiataruAPIClient

enum SyncTrigger: String {
    case activation
    case add
    case edit
    case remove
    case unknownAllow
}

enum AllowedDeviceListError: LocalizedError {
    case deviceKeyMissing
    case serverURLInvalid
    case syncFailed(underlying: Error, trigger: SyncTrigger, retryCount: Int)
    case preconditionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .deviceKeyMissing:
            return NSLocalizedString("device_key_auth_required_message", comment: "Error shown when trying to enable access control without a DeviceKey")
        case .serverURLInvalid:
            return NSLocalizedString("server_url_invalid", comment: "The server URL is invalid.")
        case .syncFailed:
            return NSLocalizedString("allowed_device_list_sync_failed", comment: "Generic error when syncing the allowed device list fails")
        case .preconditionFailed(let message):
            return message
        }
    }
}

@MainActor
class AllowedDeviceListManager {
    static let shared = AllowedDeviceListManager()
    
    private let settings = SettingsManager.shared
    private let deviceStore = KnownDeviceStore.shared
    private let thisDeviceID = thisDeviceIDManager.shared.deviceID
    
    // Serialized sync queue using an actor
    private actor SyncQueue {
        private var isSyncing = false
        private var pendingSync: (() async throws -> Void)?
        
        func enqueue(_ operation: @escaping () async throws -> Void) async throws {
            // If already syncing, wait for it to complete
            while isSyncing {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            isSyncing = true
            defer { isSyncing = false }
            
            try await operation()
        }
    }
    
    private let syncQueue = SyncQueue()
    
    private init() {}
    
    /// Activates the allowed device list feature and seeds initial ACL list to server
    func activateAllowedDeviceList() async throws {
        // Precondition checks
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            throw AllowedDeviceListError.deviceKeyMissing
        }
        
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            throw AllowedDeviceListError.serverURLInvalid
        }
        
        // Build payload from all known devices with defaults (true/true for existing devices)
        let payload = buildPayloadFromDevices()
        
        // Sync to server
        try await syncQueue.enqueue {
            try await self.performSync(
                serverURL: serverURL,
                deviceKey: deviceKey,
                payload: payload,
                trigger: .activation,
                maxRetries: 3
            )
        }
        
        // On success, persist enabled flag
        settings.allowedDeviceListEnabled = true
        
        // Ensure all devices have ACL values persisted
        deviceStore.devices.forEach { device in
            // Values are already set via buildPayloadFromDevices defaults
            // Force save to persist new keys
        }
        deviceStore.devices = deviceStore.devices // Trigger save
    }
    
    /// Syncs the full device list if feature is enabled
    func syncAllowedDeviceListIfEnabled(trigger: SyncTrigger) async throws {
        guard settings.allowedDeviceListEnabled else {
            return // Feature not enabled, skip sync
        }
        
        // Precondition checks
        guard let deviceKey = settings.deviceKey, !deviceKey.isEmpty else {
            throw AllowedDeviceListError.deviceKeyMissing
        }
        
        guard let serverURL = URL(string: settings.miataruServerURL) else {
            throw AllowedDeviceListError.serverURLInvalid
        }
        
        let payload = buildPayloadFromDevices()
        
        try await syncQueue.enqueue {
            try await self.performSync(
                serverURL: serverURL,
                deviceKey: deviceKey,
                payload: payload,
                trigger: trigger,
                maxRetries: 3
            )
        }
    }
    
    /// Updates device ACL and syncs full list
    func upsertDeviceACL(deviceID: String, hasCurrentLocationAccess: Bool, hasHistoryAccess: Bool) async throws {
        guard let device = deviceStore.devices.first(where: { $0.DeviceID.uppercased() == deviceID.uppercased() }) else {
            throw AllowedDeviceListError.preconditionFailed("Device not found: \(deviceID)")
        }
        
        device.hasCurrentLocationAccess = hasCurrentLocationAccess
        device.hasHistoryAccess = hasHistoryAccess
        
        try await syncAllowedDeviceListIfEnabled(trigger: .edit)
    }
    
    /// Removes device and syncs full list
    func removeDeviceAndSync(deviceID: String) async throws {
        // Capture snapshot for rollback
        let snapshot = captureSnapshot()
        
        // Remove device locally
        deviceStore.removeDevice(byID: deviceID)
        
        // Sync full list
        do {
            try await syncAllowedDeviceListIfEnabled(trigger: .remove)
        } catch {
            // Rollback on failure
            restoreSnapshot(snapshot)
            throw error
        }
    }
    
    /// Captures a snapshot of current device state for rollback
    func captureSnapshot() -> [KnownDeviceSnapshot] {
        return deviceStore.devices.map { device in
            KnownDeviceSnapshot(
                deviceID: device.DeviceID,
                deviceName: device.DeviceName,
                deviceColor: device.DeviceColor,
                deviceIsInGroup: device.DeviceIsInGroup,
                knownDevicesTablePosition: device.KnownDevicesTablePosition,
                hasCurrentLocationAccess: device.hasCurrentLocationAccess,
                hasHistoryAccess: device.hasHistoryAccess
            )
        }
    }
    
    /// Restores device state from snapshot
    func restoreSnapshot(_ snapshot: [KnownDeviceSnapshot]) {
        // Remove all current devices
        let currentDeviceIDs = deviceStore.devices.map { $0.DeviceID }
        currentDeviceIDs.forEach { deviceStore.removeDevice(byID: $0) }
        
        // Restore from snapshot
        for snap in snapshot {
            let device = KnownDevice(
                name: snap.deviceName,
                deviceID: snap.deviceID,
                color: snap.deviceColor,
                hasCurrentLocationAccess: snap.hasCurrentLocationAccess,
                hasHistoryAccess: snap.hasHistoryAccess
            )
            device.DeviceIsInGroup = snap.deviceIsInGroup
            device.KnownDevicesTablePosition = snap.knownDevicesTablePosition
            deviceStore.add(device: device)
        }
        
        // Restore ordering
        let sortedDevices = deviceStore.devices.sorted { $0.KnownDevicesTablePosition < $1.KnownDevicesTablePosition }
        deviceStore.devices = sortedDevices
    }
    
    // MARK: - Private Helpers
    
    private func buildPayloadFromDevices() -> [MiataruAllowedDevice] {
        let payload = deviceStore.devices.map { device in
            MiataruAllowedDevice(
                DeviceID: device.DeviceID,
                hasCurrentLocationAccess: device.hasCurrentLocationAccess,
                hasHistoryAccess: device.hasHistoryAccess
            )
        }
        debugLog("[AllowedDeviceListManager] Building payload with \(payload.count) devices")
        for item in payload {
            debugLog("[AllowedDeviceListManager] Device \(item.DeviceID): current=\(item.hasCurrentLocationAccess), history=\(item.hasHistoryAccess)")
        }
        return payload
    }
    
    private func performSync(
        serverURL: URL,
        deviceKey: String,
        payload: [MiataruAllowedDevice],
        trigger: SyncTrigger,
        maxRetries: Int
    ) async throws {
        var lastError: Error?
        var retryCount = 0
        
        while retryCount <= maxRetries {
            do {
                _ = try await MiataruAPIClient.setAllowedDeviceList(
                    serverURL: serverURL,
                    deviceID: thisDeviceID,
                    deviceKey: deviceKey,
                    allowedDevices: payload
                )
                
                debugLog("[AllowedDeviceListManager] Sync successful (trigger: \(trigger.rawValue), retries: \(retryCount))")
                return // Success
                
            } catch {
                lastError = error
                retryCount += 1
                
                if retryCount <= maxRetries {
                    // Exponential backoff: 1s, 2s, 4s
                    let delay = pow(2.0, Double(retryCount - 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    debugLog("[AllowedDeviceListManager] Retry \(retryCount)/\(maxRetries) after \(delay)s (trigger: \(trigger.rawValue))")
                } else {
                    debugLog("[AllowedDeviceListManager] Sync failed after \(maxRetries) retries (trigger: \(trigger.rawValue)): \(error)")
                }
            }
        }
        
        // All retries exhausted
        throw AllowedDeviceListError.syncFailed(
            underlying: lastError ?? NSError(domain: "AllowedDeviceListManager", code: -1),
            trigger: trigger,
            retryCount: retryCount - 1
        )
    }
}

// Snapshot structure for rollback
struct KnownDeviceSnapshot {
    let deviceID: String
    let deviceName: String
    let deviceColor: UIColor?
    let deviceIsInGroup: Bool
    let knownDevicesTablePosition: Int
    let hasCurrentLocationAccess: Bool
    let hasHistoryAccess: Bool
}
