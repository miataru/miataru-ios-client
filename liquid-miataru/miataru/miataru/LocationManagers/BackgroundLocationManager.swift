import Foundation
import BackgroundTasks
import CoreLocation
import UIKit
import Combine

/// BackgroundLocationManager schedules and handles background location updates using BGTaskScheduler.
final class BackgroundLocationManager: NSObject, ObservableObject {
    static let shared = BackgroundLocationManager()

    // MARK: - Background Task Identifier
    private let backgroundTaskIdentifier = "com.miataru.ios.background-location"

    // MARK: - Published Properties
    @Published var lastBackgroundUpdate: Date?
    @Published var backgroundUpdateCount: Int = 0
    @Published var backgroundTaskStatus: String = "Not registered"

    // MARK: - Private Properties
    private let locationManager = LocationManager.shared
    private let settings = SettingsManager.shared
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    override private init() {
        super.init()
        registerBackgroundTask()
    }

    // MARK: - Register Background Task
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { [weak self] task in
            self?.handleBackgroundLocationTask(task as! BGAppRefreshTask)
        }
        backgroundTaskStatus = "Registered"
    }

    // MARK: - Schedule Background Task
    func scheduleBackgroundLocationTask() {
        guard settings.trackAndReportLocation else { return }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 minute
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background location task scheduled")
        } catch {
            print("Failed to schedule background location task: \(error)")
        }
    }

    // MARK: - Handle Background Task
    private func handleBackgroundLocationTask(_ task: BGAppRefreshTask) {
        let queue = DispatchQueue.global(qos: .background)
        task.expirationHandler = { [weak self] in
            self?.endBackgroundTask()
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.beginBackgroundTask()
            self.locationManager.startSignificantChangeUpdates()
            self.lastBackgroundUpdate = Date()
            self.backgroundUpdateCount += 1
            self.scheduleBackgroundLocationTask()
            task.setTaskCompleted(success: true)
            self.endBackgroundTask()
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

    // MARK: - Public API
    func startBackgroundTracking() {
        locationManager.startSignificantChangeUpdates()
        scheduleBackgroundLocationTask()
    }
    func stopBackgroundTracking() {
        locationManager.stopTracking()
        BGTaskScheduler.shared.cancelAllTaskRequests()
        endBackgroundTask()
    }
}

// MARK: - App Delegate Extension
extension BackgroundLocationManager {
    func applicationDidEnterBackground(_ application: UIApplication) {
        startBackgroundTracking()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        stopBackgroundTracking()
    }
} 
