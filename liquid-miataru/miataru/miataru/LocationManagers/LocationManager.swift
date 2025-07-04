import Foundation
import CoreLocation
import Combine
import MiataruAPIClient
import UIKit

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var locationStatus: LocationStatus = .notDetermined
    @Published var lastUpdateTime: Date?
    @Published var isTracking: Bool = false
    @Published var lastServerUpdate: Date?
    @Published var serverUpdateStatus: ServerUpdateStatus = .idle
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let settings = SettingsManager.shared
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var locationUpdateTimer: Timer?
    private var serverUpdateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Location Status
    enum LocationStatus {
        case notDetermined
        case denied
        case restricted
        case authorizedWhenInUse
        case authorizedAlways
        case unavailable
    }
    
    // MARK: - Server Update Status
    enum ServerUpdateStatus {
        case idle
        case updating
        case success
        case failed(String)
    }
    
    // MARK: - Configuration
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 10 // 10 Meter
    private let updateInterval: TimeInterval = 30 // 30 Sekunden
    
    override init() {
        super.init()
        setupLocationManager()
        setupObservers()
        loadSettings()
    }
    
    // MARK: - Setup
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }
    
    private func setupObservers() {
        // Beobachte Settings-Änderungen
        settings.$trackAndReportLocation
            .sink { [weak self] shouldTrack in
                if shouldTrack {
                    self?.startTracking()
                } else {
                    self?.stopTracking()
                }
            }
            .store(in: &cancellables)
        
        settings.$miataruServerURL
            .sink { [weak self] _ in
                // Bei Server-URL-Änderung sofort aktualisieren
                if self?.isTracking == true {
                    self?.sendLocationToServer()
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadSettings() {
        // Initiale Einstellung basierend auf gespeicherten Settings
        if settings.trackAndReportLocation {
            startTracking()
        }
    }
    
    // MARK: - Public Methods
    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            locationStatus = .denied
        case .authorizedWhenInUse:
            // Upgrade auf "Always" anfordern
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            locationStatus = .authorizedAlways
        @unknown default:
            locationStatus = .unavailable
        }
    }
    
    func startTracking() {
        guard settings.trackAndReportLocation else { return }
        
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            locationStatus = .authorizedAlways
            startLocationUpdates()
        case .authorizedWhenInUse:
            locationStatus = .authorizedWhenInUse
            // Versuche Upgrade auf "Always"
            locationManager.requestAlwaysAuthorization()
            startLocationUpdates()
        case .denied, .restricted:
            locationStatus = .denied
            return
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
            return
        @unknown default:
            locationStatus = .unavailable
            return
        }
    }
    
    func stopTracking() {
        stopLocationUpdates()
        isTracking = false
    }
    
    // MARK: - Private Methods
    private func startLocationUpdates() {
        guard !isTracking else { return }
        
        isTracking = true
        locationManager.startUpdatingLocation()
        
        // Timer für regelmäßige Server-Updates
        startServerUpdateTimer()
        
        print("Location-Tracking gestartet")
    }
    
    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        stopServerUpdateTimer()
        endBackgroundTask()
        
        print("Location-Tracking gestoppt")
    }
    
    private func startServerUpdateTimer() {
        serverUpdateTimer?.invalidate()
        serverUpdateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.sendLocationToServer()
        }
    }
    
    private func stopServerUpdateTimer() {
        serverUpdateTimer?.invalidate()
        serverUpdateTimer = nil
    }
    
    private func sendLocationToServer() {
        guard let location = currentLocation,
              !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            serverUpdateStatus = .failed("Ungültige Konfiguration")
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
                
                await MainActor.run {
                    if success {
                        self.serverUpdateStatus = .success
                        self.lastServerUpdate = Date()
                        //print("Location erfolgreich an Server gesendet: \(location.coordinate)")
                    } else {
                        self.serverUpdateStatus = .failed("Server-Antwort war nicht erfolgreich")
                    }
                }
            } catch {
                await MainActor.run {
                    self.serverUpdateStatus = .failed(error.localizedDescription)
                    print("Fehler beim Senden der Location: \(error)")
                }
            }
        }
    }
    
    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        lastUpdateTime = Date()
        
        // Sofort an Server senden bei neuer Location
        sendLocationToServer()
        
        //print("Neue Location erhalten: \(location.coordinate)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location-Fehler: \(error.localizedDescription)")
        locationStatus = .unavailable
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationStatus = .notDetermined
        case .denied:
            locationStatus = .denied
            stopTracking()
        case .restricted:
            locationStatus = .restricted
            stopTracking()
        case .authorizedWhenInUse:
            locationStatus = .authorizedWhenInUse
            if settings.trackAndReportLocation {
                startTracking()
            }
        case .authorizedAlways:
            locationStatus = .authorizedAlways
            if settings.trackAndReportLocation {
                startTracking()
            }
        @unknown default:
            locationStatus = .unavailable
        }
    }
    
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        print("Location-Updates pausiert")
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        print("Location-Updates fortgesetzt")
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("Region betreten: \(region.identifier)")
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        print("Region verlassen: \(region.identifier)")
    }
} 
