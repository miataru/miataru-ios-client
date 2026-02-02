/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MutualNavigationDetector.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-19.
 */

import Foundation
import Combine
import MiataruAPIClient

/// Detects mutual navigation state between two devices by polling visitor history.
/// Implements hysteresis to avoid flickering (T_enter=60s, T_exit=90s).
final class MutualNavigationDetector: ObservableObject {
    @Published var isMutualNavigation: Bool = false
    
    private var targetDeviceId: String?
    private let ourDeviceId: String
    private var serverURL: String
    private let settings = SettingsManager.shared
    private var pollingTimer: AnyCancellable?
    private var cachedVisitorHistory: [MiataruVisitor] = []
    private var lastPollTime: Date?
    
    // Hysteresis thresholds
    private let tEnter: TimeInterval = 60.0  // Enter mutual state if last seen <= 60s ago
    private let tExit: TimeInterval = 90.0   // Exit mutual state if last seen >= 90s ago
    
    // Polling interval (15-30s as specified)
    private let pollingInterval: TimeInterval = 20.0
    
    init(ourDeviceId: String, serverURL: String) {
        self.ourDeviceId = ourDeviceId
        self.serverURL = serverURL
    }
    
    /// Start monitoring for mutual navigation with the given target device.
    /// Stops any existing monitoring.
    func startMonitoring(targetDeviceId: String, serverURL: String? = nil) {
        stopMonitoring()
        self.targetDeviceId = targetDeviceId
        if let serverURL = serverURL {
            self.serverURL = serverURL
        }
        isMutualNavigation = false
        cachedVisitorHistory = []
        lastPollTime = nil
        
        // Initial poll
        Task { @MainActor in
            await pollVisitorHistory()
        }
        
        // Start periodic polling
        pollingTimer = Timer.publish(every: pollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.pollVisitorHistory()
                }
            }
    }
    
    /// Stop monitoring for mutual navigation.
    func stopMonitoring() {
        pollingTimer?.cancel()
        pollingTimer = nil
        targetDeviceId = nil
        isMutualNavigation = false
        cachedVisitorHistory = []
        lastPollTime = nil
    }
    
    /// Poll visitor history and update mutual navigation state.
    private func pollVisitorHistory() async {
        guard let targetId = targetDeviceId,
              let url = URL(string: serverURL) else {
            return
        }
        
        do {
            APIRequestCounter.shared.record(.getVisitorHistory)
            let visitors = try await MiataruAPIClient.getVisitorHistory(
                serverURL: url,
                forDeviceID: ourDeviceId,
                deviceKey: settings.deviceKey,
                amount: 100  // Get enough entries to find recent visits
            )
            
            await MainActor.run {
                // Update cached history if it changed (compare by count and device IDs)
                let hasChanged = visitors.count != cachedVisitorHistory.count ||
                    !visitors.allSatisfy { visitor in
                        cachedVisitorHistory.contains { $0.DeviceID == visitor.DeviceID && $0.TimeStamp == visitor.TimeStamp }
                    }
                if hasChanged {
                    cachedVisitorHistory = visitors
                }
                // Always re-evaluate mutual state based on current time, even if history hasn't changed.
                // This ensures the state updates when the age of the last visit exceeds the exit threshold.
                updateMutualState(targetDeviceId: targetId)
                lastPollTime = Date()
            }
        } catch {
            debugLog("[MutualNavigationDetector] Failed to fetch visitor history: \(error)")
            // On error, still re-evaluate state based on cached data since time is passing
            await MainActor.run {
                if let targetId = targetDeviceId {
                    updateMutualState(targetDeviceId: targetId)
                }
            }
        }
    }
    
    /// Update mutual navigation state based on visitor history and hysteresis logic.
    private func updateMutualState(targetDeviceId: String) {
        // Find the newest visitor entry for the target device
        let targetVisits = cachedVisitorHistory.filter { $0.DeviceID.uppercased() == targetDeviceId.uppercased() }
        guard let newestVisit = targetVisits.max(by: { $0.TimeStampDate < $1.TimeStampDate }) else {
            // No visits from target device, not mutual
            isMutualNavigation = false
            return
        }
        
        let age = Date().timeIntervalSince(newestVisit.TimeStampDate)
        
        // Hysteresis: different thresholds for enter/exit
        if isMutualNavigation {
            // Currently mutual: exit if age >= T_exit
            isMutualNavigation = age <= tExit
        } else {
            // Not currently mutual: enter if age <= T_enter
            isMutualNavigation = age <= tEnter
        }
    }
}
