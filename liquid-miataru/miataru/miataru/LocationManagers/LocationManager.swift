import Foundation
import CoreLocation
import Combine
import MiataruAPIClient
import UIKit

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
    private var foregroundLocationTimer: Timer?
    private var foregroundLocationUpdateTimerTimeframe: Double = 10
    
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
        locationManager.activityType = .automotiveNavigation
        observeSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidBecomeActive() {
        print("App did become active")
        if isTracking {
            startHighAccuracyUpdates()
        }
    }
    
    // MARK: - Settings Observer
    private func observeSettings() {
        settings.$trackAndReportLocation
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
    
    // MARK: - Permissions
    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    // MARK: - Tracking Control
    func startTracking() {
        print("startTracking called")
        guard settings.trackAndReportLocation else { return }
        isTracking = true
        updateTrackingMode()
    }
    
    func stopTracking() {
        print("stopTracking called")
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        stopForegroundLocationTimer()
    }
    
    private func updateTrackingMode() {
        let state = UIApplication.shared.applicationState
        let status = locationManager.authorizationStatus
        print("updateTrackingMode called, state: \(state.rawValue), status: \(status.rawValue), isTracking: \(isTracking)")
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            if isTracking && state == .active {
                startHighAccuracyUpdates()
            } else if isTracking && state != .active {
                startSignificantChangeUpdates()
            } else {
                stopTracking()
            }
        default:
            stopTracking()
        }
    }
    
    private func startHighAccuracyUpdates() {
        print("Calling startHighAccuracyUpdates")
        locationManager.allowsBackgroundLocationUpdates = false
        print("allowsBackgroundLocationUpdates set to false (foreground)")
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.startUpdatingLocation()
        if foregroundLocationTimer == nil {
            print("App is active, will start foreground location timer")
            startForegroundLocationTimer()
        } else {
            print("Foreground location timer already running")
        }
    }
    
    func startSignificantChangeUpdates() {
        print("startSignificantChangeUpdates called")
        locationManager.allowsBackgroundLocationUpdates = true
        print("allowsBackgroundLocationUpdates set to true (background)")
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        stopForegroundLocationTimer()
    }
    
    // MARK: - Server Communication
    private func sendLocationToServer(_ location: CLLocation) {
        guard !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            serverUpdateStatus = .failed("Invalid server configuration")
            return
        }
        serverUpdateStatus = .updating
        let locationData = UpdateLocationPayload(
            Device: thisDeviceIDManager.shared.deviceID,
            Timestamp: String(Int64(location.timestamp.timeIntervalSince1970)),
            Longitude: location.coordinate.longitude,
            Latitude: location.coordinate.latitude,
            HorizontalAccuracy: location.horizontalAccuracy
        )
        Task {
            do {
                let success = try await MiataruAPIClient.updateLocation(
                    serverURL: serverURL,
                    locationData: locationData,
                    enableHistory: settings.saveLocationHistoryOnServer,
                    retentionTime: settings.locationDataRetentionTime
                )
                if success {
                    self.serverUpdateStatus = .success
                    self.lastServerUpdate = Date()
                } else {
                    self.serverUpdateStatus = .failed("Server response was not successful")
                }
            } catch {
                self.serverUpdateStatus = .failed(error.localizedDescription)
            }
        }
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
        print("Starting foreground location timer")
        stopForegroundLocationTimer()
        foregroundLocationTimer = Timer.scheduledTimer(withTimeInterval: foregroundLocationUpdateTimerTimeframe, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if UIApplication.shared.applicationState == .active && self.isTracking {
                print("[Timer] Requesting location...")
                self.locationManager.requestLocation()
            } else {
                print("[Timer] Not active or not tracking, skipping requestLocation")
            }
        }
        RunLoop.main.add(foregroundLocationTimer!, forMode: .common)
        print("ForegroundLocationTimer created at: \(Unmanaged.passUnretained(foregroundLocationTimer!).toOpaque())")
    }
    
    private func stopForegroundLocationTimer() {
        if let timer = foregroundLocationTimer {
            print("Stopping foreground location timer at: \(Unmanaged.passUnretained(timer).toOpaque())")
        } else {
            print("stopForegroundLocationTimer called, but timer was already nil")
        }
        foregroundLocationTimer?.invalidate()
        foregroundLocationTimer = nil
    }
    
    // MARK: - Background Tracking API
    func startBackgroundTracking() {
        guard settings.trackAndReportLocation else { return }
        startSignificantChangeUpdates()
        lastBackgroundUpdate = Date()
        backgroundUpdateCount += 1
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
        print("[LocationManager] App did enter foreground")
        guard isTracking else { return }
        stopSignificantChangeUpdates()
        startHighAccuracyUpdates()
    }

    func appDidEnterBackground() {
        print("[LocationManager] App did enter background")
        guard isTracking else { return }
        stopHighAccuracyUpdates()
        startSignificantChangeUpdates()
    }

    private func stopHighAccuracyUpdates() {
        print("[LocationManager] Stopping high accuracy updates")
        locationManager.stopUpdatingLocation()
        stopForegroundLocationTimer()
    }

    private func stopSignificantChangeUpdates() {
        print("[LocationManager] Stopping significant change updates")
        locationManager.stopMonitoringSignificantLocationChanges()
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let mode = UIApplication.shared.applicationState == .active ? "Foreground" : "Background"
        print("[LocationManager] Location update (", mode, "): (lat: \(location.coordinate.latitude), lon: \(location.coordinate.longitude)) sent to server.")
        DispatchQueue.main.async {
            self.currentLocation = location
            self.lastUpdateTime = Date()
            self.sendLocationToServer(location)
            self.addUpdateLogEntry(mode: mode)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.updateTrackingMode()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.serverUpdateStatus = .failed(error.localizedDescription)
        }
    }
} 
