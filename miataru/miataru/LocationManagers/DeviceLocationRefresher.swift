/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLocationRefresher.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import UIKit
import MiataruAPIClient

/// DeviceLocationRefresher handles refreshing device locations from the server with throttling support.
@MainActor
final class DeviceLocationRefresher {
    static let shared = DeviceLocationRefresher()
    
    // MARK: - Private Properties
    private var lastRefresh: Date?
    private var inFlightRefreshTask: Task<Bool, Never>?
    private let settings = SettingsManager.shared
    private let store = KnownDeviceStore.shared
    private let cache = DeviceLocationCacheStore.shared
    
    // MARK: - Init
    private init() {}
    
    // MARK: - Public Methods
    
    /// Checks if a refresh should be performed based on throttling, visibility, app state, and settings.
    /// - Parameter isVisible: Whether the view requesting the refresh is currently visible
    /// - Returns: `true` if refresh should proceed, `false` otherwise
    func shouldRefresh(isVisible: Bool) async -> Bool {
        guard settings.autoRefreshDeviceList,
              isVisible else {
            return false
        }
        
        // Check application state on main thread
        let isActive = await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        
        guard isActive else {
            return false
        }
        
        let interval = Double(settings.outsideMapUpdateInterval)
        let now = Date()
        
        if let last = lastRefresh, now.timeIntervalSince(last) < interval {
            // Throttle: do not refresh yet
            return false
        }
        return true
    }
    
    /// Refreshes all device locations if conditions are met (throttling, visibility, app state).
    /// - Parameters:
    ///   - isVisible: Whether the view requesting the refresh is currently visible
    ///   - forceGeocoding: Whether to force geocoding for all devices
    /// - Returns: `true` if refresh was performed and succeeded, `false` otherwise
    func refreshIfNeeded(isVisible: Bool, forceGeocoding: Bool = false) async -> Bool {
        guard await shouldRefresh(isVisible: isVisible) else {
            return false
        }
        
        lastRefresh = Date()
        return await refreshAllDeviceLocations(forceGeocoding: forceGeocoding)
    }
    
    /// Refreshes all device locations from the server, updating the cache.
    /// - Parameter forceGeocoding: Whether to force geocoding for all devices (typically used for manual refresh)
    /// - Returns: `true` if refresh succeeded, `false` otherwise
    func refreshAllDeviceLocations(forceGeocoding: Bool = false) async -> Bool {
        if let inFlightRefreshTask {
            return await inFlightRefreshTask.value
        }

        guard let url = URL(string: settings.miataruServerURL), !store.devices.isEmpty else {
            return false
        }
        
        let deviceIDs = store.devices.map { $0.DeviceID }

        let refreshTask = Task<Bool, Never> {
            do {
                debugLog("[DeviceLocationRefresher] refreshAllDeviceLocations")
                APIRequestCounter.shared.record(.getLocation)
                let locations = try await MiataruAppAPI.getLocation(
                    serverURL: url,
                    forDeviceIDs: deviceIDs,
                    requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                    requestingDeviceKey: settings.deviceKey
                )

                let snapshots = locations.map {
                    DeviceLocationSnapshot(
                        deviceID: $0.Device,
                        latitude: $0.Latitude,
                        longitude: $0.Longitude,
                        accuracy: $0.HorizontalAccuracy,
                        timestamp: $0.TimestampDate,
                        batteryLevel: $0.BatteryLevel,
                        altitude: $0.Altitude,
                        speed: nil
                    )
                }
                let foundIDs = Set(locations.map { $0.Device })
                let missingIDs = Set(deviceIDs).subtracting(foundIDs)

                cache.applyLocationSnapshots(
                    snapshots,
                    removingMissingDeviceIDs: missingIDs,
                    forceGeocoding: forceGeocoding
                )

                // Fetch visitor history for current user's device after locations are retrieved
                await refreshVisitorHistory(serverURL: url)
                return true
            } catch {
                debugLog("Error refreshing device locations: \(error)")
                // Keep the last successful snapshot on transient refresh errors to avoid list flicker.
                return false
            }
        }

        inFlightRefreshTask = refreshTask
        let result = await refreshTask.value
        inFlightRefreshTask = nil
        return result
    }
    
    /// Fetches visitor history for the current user's device and updates cache with devices that have looked for the user in the past 90 seconds.
    /// - Parameter serverURL: The server URL to fetch visitor history from
    private func refreshVisitorHistory(serverURL: URL) async {
        let currentDeviceID = thisDeviceIDManager.shared.deviceID
        
        do {
            debugLog("[DeviceLocationRefresher] refreshVisitorHistory for device \(currentDeviceID)")
            // Request a reasonable amount of visitor history entries (enough to cover 90 seconds)
            // Assuming updates happen every few seconds, requesting 50 entries should be sufficient
            APIRequestCounter.shared.record(.getVisitorHistory)
            let visitors = try await MiataruAppAPI.getVisitorHistory(
                serverURL: serverURL,
                forDeviceID: currentDeviceID,
                deviceKey: settings.deviceKey,
                amount: 50
            )
            
            // Calculate cutoff time: 90 seconds ago
            let cutoffTime = Date().addingTimeInterval(-90)
            
            // Filter visitors from the past 90 seconds and get unique device IDs
            let recentVisitorDeviceIDs = Set(visitors
                .filter { $0.TimeStampDate >= cutoffTime }
                .map { $0.DeviceID })
            
            // Update cache on main thread
            await MainActor.run {
                cache.setRecentVisitorDeviceIDs(recentVisitorDeviceIDs)
            }
            
            debugLog("[DeviceLocationRefresher] Found \(recentVisitorDeviceIDs.count) devices that looked for current user in past 90 seconds")
        } catch {
            _ = DeviceKeyAuthHandler.handle(error: error)
            debugLog("[DeviceLocationRefresher] Error refreshing visitor history: \(error)")
            // On error, clear recent visitors
            await MainActor.run {
                cache.setRecentVisitorDeviceIDs(Set<String>())
            }
        }
    }
}
