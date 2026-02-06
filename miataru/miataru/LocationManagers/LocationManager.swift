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
    @Published var userHeading: Double?
    @Published private(set) var isHeadingValid: Bool = false
    @Published var lastServerUpdate: Date?
    @Published var serverUpdateStatus: ServerUpdateStatus = .idle
    @Published var updateLog: [UpdateLogEntry] = []
    @Published var lastBackgroundUpdate: Date?
    @Published var backgroundUpdateCount: Int = 0
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let userDefaults = UserDefaults.standard
    private let backgroundUpdateCountKey = "miataru_backgroundUpdateCount"
    private let lastBackgroundUpdateKey = "miataru_lastBackgroundUpdate"
    private let backgroundMetricsLastResetKey = "miataru_backgroundMetricsLastReset"
    private let lastServerUpdateKey = "miataru_lastServerUpdate"
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared
    private var foregroundLocationTimer: Timer?
    private var foregroundLocationUpdateTimerTimeframe: Double = 30
    private let networkMonitor = NWPathMonitor()
    @Published private(set) var isNetworkAvailable: Bool = true
    private let alwaysAuthorizationRequestedKey = "miataru_always_authorization_requested"
    private var lastSmoothedHeading: Double?
    private let headingSmoothingAlpha: Double = 0.25
    private let headingAccuracyThreshold: Double = 35
    private let headingMinSpeedThreshold: Double = 1.0
    private var hasRequestedAlwaysAuthorization: Bool {
        get { userDefaults.bool(forKey: alwaysAuthorizationRequestedKey) }
        set { userDefaults.set(newValue, forKey: alwaysAuthorizationRequestedKey) }
    }
    
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
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 1
        }
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
        // Ensure permission state is handled on startup
        ensureAuthorizationIfNeeded()
        // Load persisted background update metrics
        if userDefaults.object(forKey: backgroundUpdateCountKey) != nil {
            backgroundUpdateCount = userDefaults.integer(forKey: backgroundUpdateCountKey)
        }
        if let savedDate = userDefaults.object(forKey: lastBackgroundUpdateKey) as? Date {
            lastBackgroundUpdate = savedDate
        }
        // Load persisted lastServerUpdate
        if let savedDate = userDefaults.object(forKey: lastServerUpdateKey) as? Date {
            lastServerUpdate = savedDate
        }
        // Perform initial daily reset check
        maybeResetBackgroundMetricsIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidBecomeActive() {
        debugLog("App did become active")
        // Update authorization status (in case it changed while app was in background)
        let currentStatus = locationManager.authorizationStatus
        self.authorizationStatus = currentStatus
        
        // If permission is denied/restricted but toggle is on, update it
        if (currentStatus == .denied || currentStatus == .restricted) && settings.trackAndReportLocation {
            debugLog("Permission still denied/restricted after returning from Settings, setting trackAndReportLocation to false")
            settings.trackAndReportLocation = false
        }
        
        // Re-check permission escalation / first-time prompt if needed
        ensureAuthorizationIfNeeded()
        if !isTracking,
           settings.trackAndReportLocation,
           !settings.deviceKeyAuthBlocked {
            startTracking()
        }
        if isTracking {
            startHighAccuracyUpdates()
        }
    }
    
    // MARK: - Settings Observer
    private func observeSettings() {
        settings.$trackAndReportLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldTrack in
                guard let self else { return }
                if shouldTrack {
                    self.startTracking()
                } else {
                    self.stopTracking()
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
                    self.updateTrackingMode()
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
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            // Permission already granted, no action needed
            break
        case .denied, .restricted:
            // Permission was denied, open Settings so user can change it
            openAppSettings()
        @unknown default:
            break
        }
    }
    
    func openAppSettings() {
        Task { @MainActor in
            // Use the standard iOS Settings URL
            let settingsUrlString = UIApplication.openSettingsURLString
            debugLog("Attempting to open Settings with URL: \(settingsUrlString)")
            
            guard let settingsUrl = URL(string: settingsUrlString) else {
                debugLog("Failed to create settings URL from: \(settingsUrlString)")
                return
            }
            
            // Check if we can open the URL (this should always be true for app-settings:)
            guard UIApplication.shared.canOpenURL(settingsUrl) else {
                debugLog("Cannot open Settings URL - URL scheme not available")
                return
            }
            
            // Open Settings with completion handler
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(settingsUrl, options: [:]) { success in
                    DispatchQueue.main.async {
                        if success {
                            debugLog("Successfully opened Settings")
                        } else {
                            debugLog("Failed to open Settings - completion handler returned false")
                        }
                    }
                }
            } else {
                // Fallback for iOS 9 and earlier
                let opened = UIApplication.shared.openURL(settingsUrl)
                debugLog("openURL returned: \(opened)")
            }
        }
    }

    private func ensureAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        if settings.trackAndReportLocation {
            switch status {
            case .notDetermined:
                // Trigger first-time prompt
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                // Escalate to Always once if user opted-in to tracking
                if !hasRequestedAlwaysAuthorization {
                    debugLog("Ensuring Always authorization after WhenInUse…")
                    hasRequestedAlwaysAuthorization = true
                    locationManager.requestAlwaysAuthorization()
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Tracking Control
    func startTracking() {
        debugLog("startTracking called")
        if settings.deviceKeyAuthBlocked {
            debugLog("startTracking blocked due to DeviceKey auth failure")
            return
        }
        isTracking = true
        updateTrackingMode()
    }
    
    func stopTracking() {
        debugLog("stopTracking called")
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopHeadingUpdates()
        stopForegroundLocationTimer()
    }
    
    private func updateTrackingMode() {
        let state = UIApplication.shared.applicationState
        let status = locationManager.authorizationStatus
        debugLog("updateTrackingMode called, state: \(state.rawValue), status: \(status.rawValue), isTracking: \(isTracking)")
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if isTracking {
                if state == .active {
                    startHighAccuracyUpdates()
                } else {
                    startSignificantChangeUpdates()
                }
            } else {
                // Ensure updates are stopped but preserve user's tracking preference flag
                stopHighAccuracyUpdates()
                stopSignificantChangeUpdates()
            }
        case .notDetermined:
            // Do not reset isTracking while the user has not decided yet
            break
        case .denied, .restricted:
            // Explicitly stop tracking if permission is denied/restricted
            stopTracking()
            // Update the setting to reflect the actual permission state
            if settings.trackAndReportLocation {
                settings.trackAndReportLocation = false
            }
        @unknown default:
            stopHighAccuracyUpdates()
            stopSignificantChangeUpdates()
        }
    }
    
    private func startHighAccuracyUpdates() {
        debugLog("Calling startHighAccuracyUpdates")
        locationManager.allowsBackgroundLocationUpdates = false
        debugLog("allowsBackgroundLocationUpdates set to false (foreground)")
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        startHeadingUpdatesIfAvailable()
        if foregroundLocationTimer == nil {
            debugLog("App is active, will start foreground location timer")
            startForegroundLocationTimer()
        } else {
            debugLog("Foreground location timer already running")
        }
    }
    
    func startSignificantChangeUpdates() {
        debugLog("startSignificantChangeUpdates called")
        locationManager.allowsBackgroundLocationUpdates = true
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        locationManager.stopUpdatingLocation()
        stopHeadingUpdates()
        locationManager.startMonitoringSignificantLocationChanges()
        stopForegroundLocationTimer()
    }
    
    // MARK: - Server Communication
    @MainActor
    private func sendLocationToServer(_ location: CLLocation) {
        if settings.deviceKeyAuthBlocked {
            self.serverUpdateStatus = .failed(
                NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
            )
            return
        }
        guard isNetworkAvailable else {
            debugLog("No network available, skipping server update.")
            self.serverUpdateStatus = .failed("No network connection")
            return
        }
        guard !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            self.serverUpdateStatus = .failed("Invalid server configuration")
            return
        }
        guard let payload = sanitizedPayload(from: location) else {
            debugLog("[LocationManager] Skipping server update due to invalid location values")
            self.serverUpdateStatus = .failed("Invalid location values")
            return
        }
        self.serverUpdateStatus = .updating
        Task {
            do {
                APIRequestCounter.shared.record(.updateLocation)
                let success = try await MiataruAPIClient.updateLocation(
                    serverURL: serverURL,
                    locationData: payload,
                    enableHistory: settings.saveLocationHistoryOnServer,
                    retentionTime: settings.locationDataRetentionTime
                )
                if success {
                    self.serverUpdateStatus = .success
                    let updateDate = Date()
                    self.lastServerUpdate = updateDate
                    self.userDefaults.set(updateDate, forKey: self.lastServerUpdateKey)
                    NotificationCenter.default.post(name: .didSendOwnLocationUpdate, object: nil)
                } else {
                    self.serverUpdateStatus = .failed("Server response was not successful")
                }
            } catch {
                if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                    settings.deviceKeyAuthBlocked = true
                    settings.deviceKeyAuthBlockedKey = settings.deviceKey
                    self.stopTracking()
                    self.serverUpdateStatus = .failed(authMessage)
                } else {
                    self.serverUpdateStatus = .failed(error.localizedDescription)
                }
            }
        }
    }
    

    /// Creates a sanitized payload to avoid encoding failures from NaN/inf values.
    private func sanitizedPayload(from location: CLLocation) -> UpdateLocationPayload? {
        let longitude = location.coordinate.longitude
        let latitude = location.coordinate.latitude
        let accuracy = location.horizontalAccuracy
        guard longitude.isFinite, latitude.isFinite, accuracy.isFinite, accuracy >= 0 else {
            return nil
        }

        let altitudeValue: Double? = (location.verticalAccuracy >= 0 && location.altitude.isFinite) ? location.altitude : nil
        let speedValue: Double? = (location.speed >= 0 && location.speed.isFinite) ? location.speed : nil
        let batteryLevelRaw = UIDevice.current.batteryLevel
        let batteryPercent: Double? = (batteryLevelRaw >= 0 && batteryLevelRaw.isFinite) ? Double(Int(batteryLevelRaw * 100)) : nil
        let timestamp = location.timestamp.timeIntervalSince1970
        guard timestamp.isFinite else { return nil }

        return UpdateLocationPayload(
            Device: thisDeviceIDManager.shared.deviceID,
            DeviceKey: settings.deviceKey,
            Timestamp: String(Int64(timestamp)),
            Longitude: longitude,
            Latitude: latitude,
            HorizontalAccuracy: accuracy,
            Speed: speedValue,
            BatteryLevel: batteryPercent,
            Altitude: altitudeValue
        )
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
    private func startForegroundLocationTimer() {
        debugLog("Starting foreground location timer")
        stopForegroundLocationTimer()
        foregroundLocationTimer = Timer.scheduledTimer(withTimeInterval: foregroundLocationUpdateTimerTimeframe, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if UIApplication.shared.applicationState == .active && self.isTracking {
                debugLog("[Timer] Requesting location...")
                self.locationManager.requestLocation()
            } else {
                debugLog("[Timer] Not active or not tracking, skipping requestLocation")
            }
        }
        RunLoop.main.add(foregroundLocationTimer!, forMode: .common)
        debugLog("ForegroundLocationTimer created at: \(Unmanaged.passUnretained(foregroundLocationTimer!).toOpaque())")
    }
    
    private func stopForegroundLocationTimer() {
        if let timer = foregroundLocationTimer {
            debugLog("Stopping foreground location timer at: \(Unmanaged.passUnretained(timer).toOpaque())")
        } else {
            debugLog("stopForegroundLocationTimer called, but timer was already nil")
        }
        foregroundLocationTimer?.invalidate()
        foregroundLocationTimer = nil
    }
    
    // MARK: - Background Tracking API
    func startBackgroundTracking() {
        guard settings.trackAndReportLocation else { return }
        startSignificantChangeUpdates()
    }
    
    func stopBackgroundTracking() {
        stopTracking()
    }
    
    // MARK: - App Delegate Extension
    func applicationDidEnterBackground(_ application: UIApplication) {
        startBackgroundTracking()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        stopBackgroundTracking()
    }
    
    // MARK: - App Lifecycle Hooks
    func appDidEnterForeground() {
        debugLog("[LocationManager] App did enter foreground")
        guard isTracking else { return }
        // Check daily reset on foreground entry so UI reflects a new day immediately
        maybeResetBackgroundMetricsIfNeeded()
        stopSignificantChangeUpdates()
        startHighAccuracyUpdates()
    }

    func appDidEnterBackground() {
        debugLog("[LocationManager] App did enter background")
        guard isTracking else { return }
        stopHighAccuracyUpdates()
        startSignificantChangeUpdates()
    }

    private func stopHighAccuracyUpdates() {
        debugLog("[LocationManager] Stopping high accuracy updates")
        locationManager.stopUpdatingLocation()
        stopHeadingUpdates()
        stopForegroundLocationTimer()
    }

    private func stopSignificantChangeUpdates() {
        debugLog("[LocationManager] Stopping significant change updates")
        locationManager.stopMonitoringSignificantLocationChanges()
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else {
            isHeadingValid = false
            userHeading = nil
            return
        }
        locationManager.startUpdatingHeading()
    }

    private func stopHeadingUpdates() {
        locationManager.stopUpdatingHeading()
        isHeadingValid = false
        userHeading = nil
        lastSmoothedHeading = nil
    }

    private func normalizedHeading(_ heading: Double) -> Double {
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private func smoothHeading(_ newHeading: Double) -> Double {
        let normalized = normalizedHeading(newHeading)
        guard let last = lastSmoothedHeading else {
            lastSmoothedHeading = normalized
            return normalized
        }
        let delta = normalized - last
        let wrappedDelta: Double = {
            if delta > 180 { return delta - 360 }
            if delta < -180 { return delta + 360 }
            return delta
        }()
        let smoothed = normalizedHeading(last + wrappedDelta * headingSmoothingAlpha)
        lastSmoothedHeading = smoothed
        return smoothed
    }

    private func blendedHeading(compass: Double, course: Double?, speed: Double?) -> Double {
        let normalizedCompass = normalizedHeading(compass)
        guard let course, course >= 0, let speed, speed >= headingMinSpeedThreshold else {
            return normalizedCompass
        }
        let normalizedCourse = normalizedHeading(course)
        let weight = min(max(speed / 4.0, 0.0), 1.0)
        let delta = normalizedCourse - normalizedCompass
        let wrappedDelta: Double = {
            if delta > 180 { return delta - 360 }
            if delta < -180 { return delta + 360 }
            return delta
        }()
        return normalizedHeading(normalizedCompass + wrappedDelta * weight)
    }
    
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

    // MARK: - Daily reset at midnight boundary
    private func maybeResetBackgroundMetricsIfNeeded() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let lastReset = (userDefaults.object(forKey: backgroundMetricsLastResetKey) as? Date) ?? todayStart
        if lastReset < todayStart {
            backgroundUpdateCount = 0
            userDefaults.set(0, forKey: backgroundUpdateCountKey)
            userDefaults.set(todayStart, forKey: backgroundMetricsLastResetKey)
        } else if userDefaults.object(forKey: backgroundMetricsLastResetKey) == nil {
            // Initialize baseline on first run
            userDefaults.set(todayStart, forKey: backgroundMetricsLastResetKey)
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let mode = UIApplication.shared.applicationState == .active ? NSLocalizedString("lm_foreground_status", comment: "shown in the Location Status overview for foreground updates") : NSLocalizedString("lm_background_status", comment: "shown in the Location Status overview for background updates")
            // Record update arrival whenever app is not active (background or inactive)
            if UIApplication.shared.applicationState != .active {
                // Reset counter if a new day window started
                self.maybeResetBackgroundMetricsIfNeeded()
                self.lastBackgroundUpdate = Date()
                self.backgroundUpdateCount += 1
                self.userDefaults.set(self.backgroundUpdateCount, forKey: self.backgroundUpdateCountKey)
                if let lastDate = self.lastBackgroundUpdate {
                    self.userDefaults.set(lastDate, forKey: self.lastBackgroundUpdateKey)
                }
            }
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
            if (userHeading == nil || !isHeadingValid),
               location.course >= 0,
               location.speed >= headingMinSpeedThreshold {
                userHeading = smoothHeading(normalizedHeading(location.course))
                isHeadingValid = true
            }
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
            self.sendLocationToServer(location)
            self.addUpdateLogEntry(mode: mode)
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            let accuracy = newHeading.headingAccuracy
            guard accuracy >= 0 else {
                isHeadingValid = false
                return
            }
            isHeadingValid = accuracy <= headingAccuracyThreshold
            let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
            let blended = blendedHeading(
                compass: rawHeading,
                course: currentLocation?.course,
                speed: currentLocation?.speed
            )
            userHeading = smoothHeading(blended)
        }
    }
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            // If permission is denied or restricted, update the setting to reflect the actual state
            if status == .denied || status == .restricted {
                if settings.trackAndReportLocation {
                    debugLog("Location permission denied/restricted, setting trackAndReportLocation to false")
                    settings.trackAndReportLocation = false
                }
            }
            if status == .authorizedWhenInUse,
               settings.trackAndReportLocation,
               !hasRequestedAlwaysAuthorization {
                // Escalate to Always once, if user opted-in to tracking
                debugLog("Authorized WhenInUse. Requesting Always authorization…")
                hasRequestedAlwaysAuthorization = true
                self.locationManager.requestAlwaysAuthorization()
            }
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
