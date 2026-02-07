/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * IgnoredVisitorDeviceStore.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import Combine

class IgnoredVisitorDeviceStore: ObservableObject {
    static let shared = IgnoredVisitorDeviceStore()
    
    @Published private(set) var ignoredDeviceIDs: [String] = []
    
    private let defaults = UserDefaults.standard
    private let key = "ignored_visitor_device_ids"
    
    private init() {
        self.ignoredDeviceIDs = getIgnoredDeviceIDs()
    }
    
    /// Adds a device ID to the ignored list
    func addIgnored(deviceID: String) {
        let normalizedID = deviceID.uppercased()
        if !ignoredDeviceIDs.contains(normalizedID) {
            ignoredDeviceIDs.append(normalizedID)
            defaults.set(ignoredDeviceIDs, forKey: key)
        }
    }
    
    /// Removes a device ID from the ignored list
    func removeIgnored(deviceID: String) {
        let normalizedID = deviceID.uppercased()
        ignoredDeviceIDs.removeAll { $0 == normalizedID }
        defaults.set(ignoredDeviceIDs, forKey: key)
    }
    
    /// Checks if a device ID is in the ignored list
    func isIgnored(deviceID: String) -> Bool {
        let normalizedID = deviceID.uppercased()
        return ignoredDeviceIDs.contains(normalizedID)
    }
    
    /// Returns all ignored device IDs
    func getAllIgnoredDeviceIDs() -> [String] {
        return ignoredDeviceIDs
    }
    
    private func getIgnoredDeviceIDs() -> [String] {
        return defaults.stringArray(forKey: key) ?? []
    }
}
