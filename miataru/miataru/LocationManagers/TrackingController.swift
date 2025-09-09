import Foundation
import CoreLocation
import UIKit

/// Handles switching between foreground and background location tracking modes.
///
/// `TrackingController` owns the logic for starting/stopping tracking and choosing
/// the appropriate Core Location APIs based on app state, authorization status and
/// user settings. It offloads this responsibility from `LocationManager` to keep it
/// focused on orchestration.
final class TrackingController {
    private unowned let manager: LocationManager
    private let locationManager: CLLocationManager
    private let settings: SettingsManager
    private var foregroundLocationTimer: Timer?
    private var foregroundLocationUpdateTimerTimeframe: Double = 30

    /// Creates a new tracking controller.
    /// - Parameters:
    ///   - manager: Reference back to the owning `LocationManager` instance.
    ///   - locationManager: The Core Location manager used to obtain updates.
    ///   - settings: User settings that influence tracking behaviour.
    init(manager: LocationManager, locationManager: CLLocationManager, settings: SettingsManager) {
        self.manager = manager
        self.locationManager = locationManager
        self.settings = settings
    }

    /// Starts location tracking and selects the appropriate mode.
    /// This is typically called when the user enables tracking.
    func startTracking() {
        debugLog("startTracking called")
        manager.isTracking = true
        updateTrackingMode()
    }

    /// Stops all active tracking and timers.
    func stopTracking() {
        debugLog("stopTracking called")
        manager.isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopForegroundLocationTimer()
    }

    /// Re-evaluates which tracking mode should be active.
    ///
    /// Depending on the authorization status and whether the app is in the
    /// foreground, this method switches between high accuracy updates and
    /// significant change monitoring. It also stops tracking if permissions are
    /// missing.
    func updateTrackingMode() {
        let state = UIApplication.shared.applicationState
        let status = locationManager.authorizationStatus
        debugLog("updateTrackingMode called, state: \(state.rawValue), status: \(status.rawValue), isTracking: \(manager.isTracking)")
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if manager.isTracking {
                if state == .active {
                    startHighAccuracyUpdates()
                } else {
                    startSignificantChangeUpdates()
                }
            } else {
                // Tracking stopped while permission still granted.
                stopHighAccuracyUpdates()
                stopSignificantChangeUpdates()
            }
        case .notDetermined:
            break
        case .denied, .restricted:
            // User revoked permission; stop any tracking.
            stopTracking()
        @unknown default:
            stopHighAccuracyUpdates()
            stopSignificantChangeUpdates()
        }
    }

    /// Starts continuous high accuracy updates suitable for foreground usage.
    private func startHighAccuracyUpdates() {
        debugLog("Calling startHighAccuracyUpdates")
        // Ensure the app does not attempt background updates while active.
        locationManager.allowsBackgroundLocationUpdates = false
        debugLog("allowsBackgroundLocationUpdates set to false (foreground)")
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        if foregroundLocationTimer == nil {
            debugLog("App is active, will start foreground location timer")
            startForegroundLocationTimer()
        } else {
            debugLog("Foreground location timer already running")
        }
    }

    /// Begins monitoring for large location changes, used in the background.
    func startSignificantChangeUpdates() {
        debugLog("startSignificantChangeUpdates called")
        // Allow updates while the app is backgrounded.
        locationManager.allowsBackgroundLocationUpdates = true
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        stopForegroundLocationTimer()
    }

    /// Starts a timer to periodically request location updates while in the foreground.
    private func startForegroundLocationTimer() {
        debugLog("Starting foreground location timer")
        // Reset any existing timer to avoid duplicates.
        stopForegroundLocationTimer()
        foregroundLocationTimer = Timer.scheduledTimer(withTimeInterval: foregroundLocationUpdateTimerTimeframe, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if UIApplication.shared.applicationState == .active && self.manager.isTracking {
                debugLog("[Timer] Requesting location...")
                self.locationManager.requestLocation()
            } else {
                debugLog("[Timer] Not active or not tracking, skipping requestLocation")
            }
        }
        RunLoop.main.add(foregroundLocationTimer!, forMode: .common)
        debugLog("ForegroundLocationTimer created at: \(Unmanaged.passUnretained(foregroundLocationTimer!).toOpaque())")
    }

    /// Invalidates and clears the foreground location timer.
    private func stopForegroundLocationTimer() {
        if let timer = foregroundLocationTimer {
            debugLog("Stopping foreground location timer at: \(Unmanaged.passUnretained(timer).toOpaque())")
        } else {
            debugLog("stopForegroundLocationTimer called, but timer was already nil")
        }
        foregroundLocationTimer?.invalidate()
        foregroundLocationTimer = nil
    }

    /// Configures tracking for background execution using significant change updates.
    func startBackgroundTracking() {
        guard settings.trackAndReportLocation else { return }
        startSignificantChangeUpdates()
        // Update bookkeeping on the manager for analytics/debugging purposes.
        manager.lastBackgroundUpdate = Date()
        manager.backgroundUpdateCount += 1
    }

    /// Stops background tracking and any active updates.
    func stopBackgroundTracking() {
        stopTracking()
    }

    /// Responds to the app transitioning to the foreground.
    func appDidEnterForeground() {
        debugLog("[LocationManager] App did enter foreground")
        guard manager.isTracking else { return }
        // Switch to high accuracy updates while the app is visible.
        stopSignificantChangeUpdates()
        startHighAccuracyUpdates()
    }

    /// Responds to the app transitioning to the background.
    func appDidEnterBackground() {
        debugLog("[LocationManager] App did enter background")
        guard manager.isTracking else { return }
        // Reduce power usage by switching to significant change monitoring.
        stopHighAccuracyUpdates()
        startSignificantChangeUpdates()
    }

    /// Stops foreground tracking mode and its timer.
    private func stopHighAccuracyUpdates() {
        debugLog("[LocationManager] Stopping high accuracy updates")
        locationManager.stopUpdatingLocation()
        stopForegroundLocationTimer()
    }

    /// Stops background significant change monitoring.
    private func stopSignificantChangeUpdates() {
        debugLog("[LocationManager] Stopping significant change updates")
        locationManager.stopMonitoringSignificantLocationChanges()
    }
}
