/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationManager.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import Foundation
import CoreLocation
import Combine
import MiataruAPIClient
import UIKit
import Network

/// LocationManager handles high-accuracy foreground tracking and significant-change background tracking.
final class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastUpdateTime: Date?
    @Published var isTracking: Bool = false
    @Published var lastServerUpdate: Date?
    @Published var serverUpdateStatus: ServerUpdateStatus = .idle
    @Published var updateLog: [UpdateLogEntry] = []
    @Published var lastBackgroundUpdate: Date?
    @Published var backgroundUpdateCount: Int = 0

    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared
    private let networkMonitor = NWPathMonitor()
    var isNetworkAvailable: Bool = true

    // MARK: - Controllers
    var permissionController: PermissionController!
    var trackingController: TrackingController!
    var locationUploader: LocationUploader!
    
    // MARK: - Server Update Status
    enum ServerUpdateStatus {
        case idle
        case updating
        case success
        case failed(String)
    }
    
    struct UpdateLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let mode: String
    }
    
    // MARK: - Init
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.activityType = Self.activityTypeFrom(settings.locationActivityType)
        // Enable battery monitoring to report battery percentage with location updates
        UIDevice.current.isBatteryMonitoringEnabled = true
        observeSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        observeActivityType()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = (path.status == .satisfied)
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
        permissionController = PermissionController(locationManager: locationManager, settings: settings)
        trackingController = TrackingController(manager: self, locationManager: locationManager, settings: settings)
        locationUploader = LocationUploader(manager: self, settings: settings)
        // Ensure permission state is handled on startup
        permissionController.ensureAuthorizationIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidBecomeActive() {
        debugLog("App did become active")
        // Re-check permission escalation / first-time prompt if needed
        permissionController.ensureAuthorizationIfNeeded()
        if isTracking {
            trackingController.updateTrackingMode()
        }
    }
    
    // MARK: - Settings Observer
    private func observeSettings() {
        settings.$trackAndReportLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldTrack in
                guard let self else { return }
                if shouldTrack {
                    self.trackingController.startTracking()
                } else {
                    self.trackingController.stopTracking()
                }
            }
            .store(in: &cancellables)
    }
    
    private func observeActivityType() {
        settings.$locationActivityType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.locationManager.activityType = Self.activityTypeFrom(newValue)
                if self.isTracking {
                    // Restart location updates to apply new activityType immediately
                    self.trackingController.updateTrackingMode()
                }
            }
            .store(in: &cancellables)
    }
    
    private static func activityTypeFrom(_ value: Int) -> CLActivityType {
        switch value {
        case 1: return .automotiveNavigation
        case 2: return .fitness
        case 3: return .otherNavigation
        case 4:
#if swift(>=5.0)
            if #available(iOS 12.0, *) {
                return .airborne
            } else {
                return .other
            }
#else
            return .other
#endif
        default: return .other
        }
    }
    
    // MARK: - Permissions
    func requestLocationPermission() {
        permissionController.requestLocationPermission()
    }

    // MARK: - Tracking Control
    func startTracking() {
        trackingController.startTracking()
    }

    func stopTracking() {
        trackingController.stopTracking()
    }

    private func updateTrackingMode() {
        trackingController.updateTrackingMode()
    }

    func startSignificantChangeUpdates() {
        trackingController.startSignificantChangeUpdates()
    }

    func startBackgroundTracking() {
        trackingController.startBackgroundTracking()
    }

    func stopBackgroundTracking() {
        trackingController.stopBackgroundTracking()
    }

    func appDidEnterForeground() {
        trackingController.appDidEnterForeground()
    }

    func appDidEnterBackground() {
        trackingController.appDidEnterBackground()
    }

    // MARK: - Logging
    private func addUpdateLogEntry(mode: String) {
        let entry = UpdateLogEntry(timestamp: Date(), mode: mode)
        updateLog.insert(entry, at: 0)
        if updateLog.count > 10 {
            updateLog = Array(updateLog.prefix(10))
        }
    }
    
    // MARK: - Foreground Location Timer
    // Moved to TrackingController

    // MARK: - Background Tracking API
    // Implemented in TrackingController

    // MARK: - App Delegate Extension
    func applicationDidEnterBackground(_ application: UIApplication) {
        trackingController.startBackgroundTracking()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        trackingController.stopBackgroundTracking()
    }

    // MARK: - App Lifecycle Hooks
    func appDidEnterForeground() {
        trackingController.appDidEnterForeground()
    }

    func appDidEnterBackground() {
        trackingController.appDidEnterBackground()
    }

    // Additional tracking helpers moved to TrackingController
    
    private func mappedSensitivityValues(for level: Int) -> (distance: CLLocationDistance, accuracy: CLLocationAccuracy) {
        switch level {
        case 1: return (3, 2)
        case 2: return (5, 5)
        case 3: return (10, 10)
        case 4: return (25, 20)
        case 5: return (50, 40)
        default: return (5, 5)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let mode = UIApplication.shared.applicationState == .active ? NSLocalizedString("lm_foreground_status", comment: "shown in the Location Status overview for foreground updates") : NSLocalizedString("lm_background_status", comment: "shown in the Location Status overview for background updates")
            // Only accept updates if distance or accuracy criteria are met
            let (minimumDistance, significantAccuracyImprovement) = mappedSensitivityValues(for: settings.locationSensitivityLevel)
            var shouldAcceptUpdate = false
            if let previousLocation = self.currentLocation {
                let distance = location.distance(from: previousLocation)
                let accuracyImprovement = previousLocation.horizontalAccuracy - location.horizontalAccuracy
                if distance >= minimumDistance {
                    shouldAcceptUpdate = true
                    debugLog("[LocationManager] Location update accepted: distance (\(distance)m) >= minimum (\(minimumDistance)m)")
                } else if accuracyImprovement >= significantAccuracyImprovement {
                    shouldAcceptUpdate = true
                    debugLog("[LocationManager] Location update accepted: accuracy improved by (\(accuracyImprovement)m) >= minimum (\(significantAccuracyImprovement)m)")
                } else {
                    debugLog("[LocationManager] Location update ignored: distance (\(distance)m), accuracy improvement (\(accuracyImprovement)m)")
                }
            } else {
                // Always accept the very first location
                shouldAcceptUpdate = true
                debugLog("[LocationManager] First location update accepted.")
            }
            guard shouldAcceptUpdate else { return }
            self.currentLocation = location
            self.lastUpdateTime = Date()
            // Immediately update local cache for own device to enable timely reverse geocoding and UI updates
            let altitudeValue: Double? = (location.verticalAccuracy >= 0) ? location.altitude : nil
            let speedValue: Double? = (location.speed >= 0) ? location.speed : nil
            let batteryLevelRaw = UIDevice.current.batteryLevel
            let batteryPercent: Double? = batteryLevelRaw >= 0 ? Double(Int(batteryLevelRaw * 100)) : nil

            DeviceLocationCacheStore.shared.setLocation(
                for: thisDeviceIDManager.shared.deviceID,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                batteryLevel: batteryPercent,
                altitude: altitudeValue,
                speed: speedValue
            )
            self.locationUploader.sendLocationToServer(location)
            self.addUpdateLogEntry(mode: mode)
        }
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
        self.authorizationStatus = status
        permissionController.handleAuthorizationChange(status)
        self.updateTrackingMode()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.serverUpdateStatus = .failed(error.localizedDescription)
        }
    }
} 

extension Notification.Name {
    static let didSendOwnLocationUpdate = Notification.Name("didSendOwnLocationUpdate")
} 
