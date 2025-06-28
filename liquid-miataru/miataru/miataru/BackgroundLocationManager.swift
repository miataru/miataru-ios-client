import Foundation
import MiataruAPIClient
import CoreLocation
import UIKit
import BackgroundTasks
import UserNotifications

class BackgroundLocationManager: NSObject, ObservableObject {
    static let shared = BackgroundLocationManager()
    
    // MARK: - Background Task Identifiers
    private let backgroundLocationTaskIdentifier = "com.miataru.ios.background-location"
    private let backgroundServerUpdateTaskIdentifier = "com.miataru.ios.background-server-update"
    
    // MARK: - Published Properties
    @Published var backgroundTaskStatus: String = "Nicht registriert"
    @Published var lastBackgroundUpdate: Date?
    @Published var backgroundUpdateCount: Int = 0
    
    // MARK: - Private Properties
    private let locationManager = LocationManager.shared
    private let settings = SettingsManager.shared
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimer: Timer?
    
    override init() {
        super.init()
        registerBackgroundTasks()
        setupNotificationCenter()
    }
    
    // MARK: - Background Task Registration
    private func registerBackgroundTasks() {
        // Registriere Background Location Task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundLocationTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundLocationTask(task as! BGAppRefreshTask)
        }
        
        // Registriere Background Server Update Task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundServerUpdateTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundServerUpdateTask(task as! BGAppRefreshTask)
        }
        
        backgroundTaskStatus = "Registriert"
        print("Background Tasks registriert")
    }
    
    // MARK: - Background Task Handlers
    private func handleBackgroundLocationTask(_ task: BGAppRefreshTask) {
        // Erstelle einen Timer für die Background-Ausführung
        let queue = DispatchQueue.global(qos: .background)
        
        task.expirationHandler = {
            queue.async {
                self.endBackgroundTask()
            }
        }
        
        queue.async {
            self.beginBackgroundTask()
            
            // Führe Location-Update durch
            if self.settings.trackAndReportLocation {
                self.locationManager.startTracking()
                
                // Warte auf Location-Update
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.sendLocationToServer()
                    self.scheduleNextBackgroundTask()
                    task.setTaskCompleted(success: true)
                }
            } else {
                task.setTaskCompleted(success: true)
            }
        }
    }
    
    private func handleBackgroundServerUpdateTask(_ task: BGAppRefreshTask) {
        let queue = DispatchQueue.global(qos: .background)
        
        task.expirationHandler = {
            queue.async {
                self.endBackgroundTask()
            }
        }
        
        queue.async {
            self.beginBackgroundTask()
            
            // Sende Location an Server
            self.sendLocationToServer()
            
            // Warte kurz und beende dann
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.scheduleNextBackgroundTask()
                task.setTaskCompleted(success: true)
            }
        }
    }
    
    // MARK: - Background Task Scheduling
    func scheduleBackgroundTasks() {
        guard settings.trackAndReportLocation else { return }
        
        // Schedule Location Task
        let locationRequest = BGAppRefreshTaskRequest(identifier: backgroundLocationTaskIdentifier)
        locationRequest.earliestBeginDate = Date(timeIntervalSinceNow: 30) // 30 Sekunden
        
        do {
            try BGTaskScheduler.shared.submit(locationRequest)
            print("Background Location Task geplant")
        } catch {
            print("Fehler beim Planen des Background Location Tasks: \(error)")
        }
        
        // Schedule Server Update Task
        let serverRequest = BGAppRefreshTaskRequest(identifier: backgroundServerUpdateTaskIdentifier)
        serverRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 Minute
        
        do {
            try BGTaskScheduler.shared.submit(serverRequest)
            print("Background Server Update Task geplant")
        } catch {
            print("Fehler beim Planen des Background Server Update Tasks: \(error)")
        }
    }
    
    private func scheduleNextBackgroundTask() {
        // Plane nächste Background-Tasks
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.scheduleBackgroundTasks()
        }
    }
    
    // MARK: - Background Task Management
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
    
    // MARK: - Server Communication
    private func sendLocationToServer() {
        guard let location = locationManager.currentLocation,
              !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            print("Background: Ungültige Konfiguration für Server-Update")
            return
        }
        
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
                    self.lastBackgroundUpdate = Date()
                    self.backgroundUpdateCount += 1
                    
                    if success {
                        print("Background: Location erfolgreich an Server gesendet")
                        self.sendLocalNotification(title: "Miataru", body: "Standort im Hintergrund aktualisiert")
                    } else {
                        print("Background: Server-Antwort war nicht erfolgreich")
                    }
                }
            } catch {
                await MainActor.run {
                    print("Background: Fehler beim Senden der Location: \(error)")
                    self.sendLocalNotification(title: "Miataru Fehler", body: "Standort konnte nicht gesendet werden: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Notification Center
    private func setupNotificationCenter() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Benachrichtigungen erlaubt")
            } else {
                print("Benachrichtigungen verweigert: \(error?.localizedDescription ?? "")")
            }
        }
    }
    
    private func sendLocalNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Fehler beim Senden der Benachrichtigung: \(error)")
            }
        }
    }
    
    // MARK: - Public Methods
    func startBackgroundTracking() {
        scheduleBackgroundTasks()
        print("Background-Tracking gestartet")
    }
    
    func stopBackgroundTracking() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        endBackgroundTask()
        print("Background-Tracking gestoppt")
    }
    
    // MARK: - App State Handling
    func handleAppDidEnterBackground() {
        if settings.trackAndReportLocation {
            startBackgroundTracking()
        }
    }
    
    func handleAppWillEnterForeground() {
        // Aktualisiere UI und stoppe Background-Tasks
        stopBackgroundTracking()
    }
}

// MARK: - App Delegate Extension
extension BackgroundLocationManager {
    func applicationDidEnterBackground(_ application: UIApplication) {
        handleAppDidEnterBackground()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        handleAppWillEnterForeground()
    }
} 
