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
final class DeviceLocationRefresher {
    static let shared = DeviceLocationRefresher()
    
    // MARK: - Private Properties
    private var lastRefresh: Date?
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
        
        let interval = Double(settings.mapUpdateInterval)
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
        guard let url = URL(string: settings.miataruServerURL), !store.devices.isEmpty else {
            return false
        }
        
        let deviceIDs = store.devices.map { $0.DeviceID }
        
        do {
            debugLog("[DeviceLocationRefresher] refreshAllDeviceLocations")
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: deviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            
            // Update cache on main thread to ensure @Published properties are updated safely
            await MainActor.run {
                for location in locations {
                    cache.setLocation(
                        for: location.Device,
                        latitude: location.Latitude,
                        longitude: location.Longitude,
                        accuracy: location.HorizontalAccuracy,
                        timestamp: location.TimestampDate,
                        batteryLevel: location.BatteryLevel,
                        altitude: location.Altitude
                    )
                }
                
                // Remove cache entry for devices without location
                let foundIDs = Set(locations.map { $0.Device })
                let missingIDs = Set(deviceIDs).subtracting(foundIDs)
                for missingID in missingIDs {
                    cache.removeLocation(for: missingID)
                }
                
                // Force geocoding only if explicitly requested (e.g., manual refresh)
                if forceGeocoding {
                    cache.forceGeocodingForAllDevices()
                }
            }
            
            return true
        } catch {
            debugLog("Error refreshing device locations: \(error)")
            // Remove all device locations from cache if download fails (on main thread)
            await MainActor.run {
                for deviceID in deviceIDs {
                    cache.removeLocation(for: deviceID)
                }
            }
            return false
        }
    }
}
