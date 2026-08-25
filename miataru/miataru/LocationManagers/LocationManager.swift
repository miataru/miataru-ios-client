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
    static let startupHeartbeatMinimumServerUpdateAge: TimeInterval = 3 * 60 * 60

    private static var shouldPreserveEnabledTrackingPreferenceForUITests: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-ui-testing") && args.contains("-ui-enable-location-tracking")
    }
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    /// Most recent CLLocation update without sensitivity filtering.
    /// Use for UI that needs immediate local-device movement feedback.
    @Published private(set) var latestRawLocation: CLLocation?
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
    @Published private(set) var locationUpdateModeCounts = LocationUpdateModeCounts()
    @Published private(set) var smartFrequentBackgroundRuntimeActive = false
    @Published private(set) var smartFrequentBackgroundRuntimePhase: SmartFrequentRuntimePhase = .waiting
    @Published private(set) var smartFrequentBackgroundLastActivationReason: String?
    @Published private(set) var smartFrequentBackgroundLastRelevantMovementAt: Date?
    @Published private(set) var smartFrequentBackgroundNextInactivityTimeoutAt: Date?
    @Published private(set) var lastSignificantChangeRearmStatus: LocationSignificantChangeRearmStatus?
    @Published private(set) var backgroundTrackingForensicState = BackgroundTrackingForensicState()
    
    // MARK: - Private Properties
    private let coreLocationServices = CoreLocationServiceController()
    private var locationManager: CLLocationManager { coreLocationServices.primaryManager }
    private var frequentBackgroundLocationManager: CLLocationManager { coreLocationServices.frequentBackgroundManager }
    private var isSignificantChangeRecoveryAnchorActive: Bool { coreLocationServices.isSignificantChangeRecoveryAnchorActive }
    private var isFrequentBackgroundStandardUpdatesActive: Bool { coreLocationServices.isFrequentBackgroundStandardUpdatesActive }
    private let userDefaults = UserDefaults.standard
    private let lastServerUpdateKey = "miataru_lastServerUpdate"
    private let smartFrequentBackgroundSeedLatitudeKey = "miataru_smartFrequentBackgroundSeedLatitude"
    private let smartFrequentBackgroundSeedLongitudeKey = "miataru_smartFrequentBackgroundSeedLongitude"
    private let smartFrequentBackgroundSeedAltitudeKey = "miataru_smartFrequentBackgroundSeedAltitude"
    private let smartFrequentBackgroundSeedHorizontalAccuracyKey = "miataru_smartFrequentBackgroundSeedHorizontalAccuracy"
    private let smartFrequentBackgroundSeedVerticalAccuracyKey = "miataru_smartFrequentBackgroundSeedVerticalAccuracy"
    private let smartFrequentBackgroundSeedCourseKey = "miataru_smartFrequentBackgroundSeedCourse"
    private let smartFrequentBackgroundSeedSpeedKey = "miataru_smartFrequentBackgroundSeedSpeed"
    private let smartFrequentBackgroundSeedTimestampKey = "miataru_smartFrequentBackgroundSeedTimestamp"
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared
    private let diagnosticsLog = LocationDiagnosticsLogStore.shared
    private let backgroundForensicsRecorder = LocationBackgroundForensicsRecorder()
    private let smartFrequentBackgroundRuntimeMarkerStore = SmartFrequentBackgroundRuntimeMarkerStore()
    private let locationUpdateMetricsStore = LocationUpdateMetricsStore()
    private let locationUpdateUploadService = LocationUpdateUploadService()
    private var foregroundLocationTimer: Timer?
    private var frequentBackgroundLocationExpirationTimer: Timer?
    private var trackingPauseExpirationTimer: Timer?
    private var smartFrequentBackgroundInactivityTimer: Timer?
    private var foregroundLocationUpdateTimerTimeframe: Double = 30
    private let networkMonitor = NWPathMonitor()
    private let locationUpdateDeliveryCoordinator = LocationUpdateDeliveryCoordinator.shared
    @Published private(set) var isNetworkAvailable: Bool = true
    @Published private(set) var pendingLocationUpdateCount: Int = 0
    private var pendingAlwaysAuthorizationRequestTask: Task<Void, Never>?
    private var didAttemptAlwaysAuthorizationInCurrentSession = false
    private var didScheduleStartupHeartbeat = false
    private var lastSubmittedLocationDeduplicationKey: LocationSubmissionDeduplicationKey?
    private var smartFrequentBackgroundSpeedReferenceLocation: CLLocation?
    private var smartFrequentBackgroundMovementAnchor: CLLocation?
    private var lastSmartFrequentBackgroundLocationUpdateAt: Date?
    private var smartFrequentBackgroundProbeStartedAt: Date?
    private var smartFrequentBackgroundConfirmedAt: Date?
    private var smartFrequentBackgroundLastFrequentCallbackAt: Date?
    private var smartFrequentBackgroundRecoveryAttemptCount = 0
    private var smartFrequentBackgroundWatchdogTimer: Timer?
    private var frequentBackgroundAccuracyRecoveryTimer: Timer?
    private var frequentBackgroundAccuracyRecoveryActive = false
    private var frequentBackgroundPoorAccuracyStreak = 0
    private var frequentBackgroundAccuracyRecoveryStartedAt: Date?
    private var frequentBackgroundAccuracyRecoveryEndedAt: Date?
    private var smartFrequentBackgroundActivationNotificationDelivered = false
    private var smartFrequentBackgroundLastMovementLocationKey: LocationSubmissionDeduplicationKey?
    private var smartFrequentBackgroundLastMovementDistanceMeters: CLLocationDistance?
    private var smartFrequentBackgroundLastMovementThresholdMeters: CLLocationDistance?
    private var smartFrequentBackgroundStartupGuardPending = true
    private var isSmartFrequentExitFenceActive = false
    private var smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false
    private var pendingLargeJumpLocation: PendingLargeJumpLocation?
    private var headingSmoother = HeadingSmoother()
    private enum LocationUpdateSource: String {
        case primary
        case frequentBackground
        case unknown
    }

    private struct StaleFrequentBackgroundCallbackCleanupResult {
        let didCleanUp: Bool
        let shouldSuppressCallback: Bool

        static let noCleanup = StaleFrequentBackgroundCallbackCleanupResult(
            didCleanUp: false,
            shouldSuppressCallback: false
        )
    }

    private struct PendingLargeJumpLocation {
        let candidate: CLLocation
        let previousAcceptedLocation: CLLocation
        let metrics: LocationSamplePolicy.AcceptanceMetrics
    }

    private var navigationLocationSessionIDs = Set<UUID>()
    private var backgroundNavigationLocationSessionIDs = Set<UUID>()
    
    // MARK: - Init
    override private init() {
        super.init()
        coreLocationServices.configure(delegate: self, activityType: Self.activityTypeFrom(settings.locationActivityType))
        // Enable battery monitoring to report battery percentage with location updates
        UIDevice.current.isBatteryMonitoringEnabled = true
        observeSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(locationUpdateOutboxDidChange), name: .locationUpdateOutboxDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ownLocationUpdateDidSend), name: .didSendOwnLocationUpdate, object: nil)
        observeActivityType()
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let networkIsAvailable = (path.status == .satisfied)
                let didRecover = !self.isNetworkAvailable && networkIsAvailable
                self.isNetworkAvailable = networkIsAvailable
                if didRecover {
                    Task {
                        await self.locationUpdateDeliveryCoordinator.networkBecameAvailable()
                    }
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
        Task {
            await locationUpdateDeliveryCoordinator.start()
        }
        refreshPendingLocationUpdateCount()
        applyLocationUpdateOutboxPolicy()
        settings.ensureFrequentBackgroundLocationUpdatesExpiration()
        handleTrackingPauseExpirationIfNeeded()
        scheduleFrequentBackgroundLocationExpirationTimer()
        scheduleTrackingPauseExpirationTimer()
        refreshFrequentBackgroundTrackingReminder()
        refreshLocationTrackingHealthReminder()
        // Ensure permission state is handled on startup
        ensureAuthorizationIfNeeded()
        applyLocationUpdateMetricsSnapshot(locationUpdateMetricsStore.load())
        // Load persisted lastServerUpdate
        if let savedDate = userDefaults.object(forKey: lastServerUpdateKey) as? Date {
            lastServerUpdate = savedDate
        }
        syncBackgroundForensicsSnapshot()
        restorePersistedSmartFrequentBackgroundSeedIfNeeded()
        // Perform initial daily reset check
        maybeResetBackgroundMetricsIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        frequentBackgroundLocationExpirationTimer?.invalidate()
        trackingPauseExpirationTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer?.invalidate()
        frequentBackgroundAccuracyRecoveryTimer?.invalidate()
        pendingAlwaysAuthorizationRequestTask?.cancel()
        coreLocationServices.stopLocationServiceSession(reason: "deinit")
        coreLocationServices.stopFrequentBackgroundActivitySession(reason: "deinit")
    }
    
    @objc private func appDidBecomeActive() {
        debugLog("App did become active")
        scheduleStartupHeartbeatIfNeeded()
        smartFrequentBackgroundStartupGuardPending = false
        recordForensicForegroundOpen(trigger: "app did become active")
        reconcileTrackingState(
            reason: "app did become active",
            applicationStateContext: .forceForeground,
            refreshExternalSettings: true
        )
        recordLocationTrackingHealthReminderActivity(reason: "app did become active")
        Task {
            await locationUpdateDeliveryCoordinator.appDidBecomeActive()
        }
        refreshPendingLocationUpdateCount()
    }

    @objc private func locationUpdateOutboxDidChange() {
        refreshPendingLocationUpdateCount()
    }

    @objc private func ownLocationUpdateDidSend() {
        Task { @MainActor in
            self.markServerUpdateSucceeded()
            self.recordLocationTrackingHealthReminderActivity(reason: "own location update sent")
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
                    self.recordLocationTrackingHealthReminderActivity(reason: "tracking enabled")
                } else {
                    self.stopTracking()
                    self.refreshLocationTrackingHealthReminder()
                }
                self.refreshFrequentBackgroundTrackingReminder()
            }
            .store(in: &cancellables)

        settings.$locationTrackingHealthReminderIntervalDays
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshLocationTrackingHealthReminder()
            }
            .store(in: &cancellables)

        settings.$trackingPauseExpiresAt
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expiresAt in
                guard let self else { return }
                self.scheduleTrackingPauseExpirationTimer()
                self.refreshFrequentBackgroundTrackingReminder()
                self.refreshLocationTrackingHealthReminder()
                Task {
                    await TrackingPauseNotificationService.shared.refresh(pauseExpiresAt: expiresAt)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            settings.$locationUpdateOutboxRetentionMode.removeDuplicates(),
            settings.$locationUpdateOutboxMaxItems.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _ in
            self?.applyLocationUpdateOutboxPolicy()
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$frequentBackgroundLocationUpdatesEnabled.removeDuplicates(),
            settings.$frequentBackgroundLocationDistanceFilter.removeDuplicates(),
            settings.$frequentBackgroundLocationUpdateDuration.removeDuplicates(),
            settings.$frequentBackgroundBatteryAutoDisableLevel.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _, _, _, _ in
            guard let self else { return }
            self.settings.ensureFrequentBackgroundLocationUpdatesExpiration()
            self.scheduleFrequentBackgroundLocationExpirationTimer()
            self.refreshFrequentBackgroundTrackingReminder()
            if self.isTracking {
                self.applyTrackingMode(reason: "frequent background settings changed")
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest4(
            settings.$smartFrequentBackgroundLocationUpdatesEnabled.removeDuplicates(),
            settings.$smartFrequentBackgroundSpeedThresholdKmh.removeDuplicates(),
            settings.$smartFrequentBackgroundSpeedDetectionMode.removeDuplicates(),
            settings.$smartFrequentBackgroundInactivityWindow.removeDuplicates()
        )
        .combineLatest(settings.$smartFrequentBackgroundExitFenceRadiusMeters.removeDuplicates())
        .receive(on: DispatchQueue.main)
        .sink { [weak self] smartSettings, _ in
            guard let self else { return }
            let smartEnabled = smartSettings.0
            if !smartEnabled {
                self.deactivateSmartFrequentBackgroundRuntime(reason: "smart frequent disabled")
            } else {
                self.scheduleSmartFrequentBackgroundInactivityTimer()
            }
            if self.isTracking {
                self.applyTrackingMode(reason: "smart frequent background settings changed")
            }
        }
        .store(in: &cancellables)
    }

    private func applyLocationUpdateOutboxPolicy() {
        let maxItems = settings.locationUpdateOutboxMaxItems
        let ttl = settings.locationUpdateOutboxRetentionTimeToLive
        Task {
            await locationUpdateDeliveryCoordinator.updateOutboxPolicy(maxItems: maxItems, ttl: ttl)
        }
    }

    func pendingLocationUpdateOutboxCount() async -> Int {
        await locationUpdateDeliveryCoordinator.pendingOutboxCount()
    }

    func sendPendingLocationUpdates(to serverURL: URL) async {
        guard !settings.isTrackingPaused else {
            refreshPendingLocationUpdateCount()
            return
        }
        await locationUpdateDeliveryCoordinator.sendPendingOutbox(to: serverURL)
        refreshPendingLocationUpdateCount()
    }

    func flushPendingLocationUpdatesNow() async {
        guard !settings.isTrackingPaused else {
            refreshPendingLocationUpdateCount()
            return
        }
        await locationUpdateDeliveryCoordinator.flushOutboxCompletelyNow()
        refreshPendingLocationUpdateCount()
    }

    func discardPendingLocationUpdates() async {
        await locationUpdateDeliveryCoordinator.discardPendingOutbox()
        refreshPendingLocationUpdateCount()
    }
    
    private func observeActivityType() {
        settings.$locationActivityType
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }
                let activityType = Self.activityTypeFrom(newValue)
                self.coreLocationServices.updateActivityType(activityType)
                if self.isTracking {
                    // Restart location updates to apply new activityType immediately
                    self.applyTrackingMode(reason: "activity type changed")
                }
            }
            .store(in: &cancellables)
    }
    
    var currentBackgroundTrackingDisplayMode: BackgroundTrackingDisplayMode {
        Self.backgroundTrackingDisplayMode(
            applicationState: UIApplication.shared.applicationState,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
            trackingPaused: settings.isTrackingPaused
        )
    }

    private var effectiveFrequentBackgroundUpdatesEnabled: Bool {
        Self.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
            trackingPaused: settings.isTrackingPaused
        )
    }

    // MARK: - Permissions
    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysAuthorizationIfPossible(reason: "explicit permission request", delay: 0)
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

    func authorizationStatusForIntent() -> CLAuthorizationStatus {
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        return status
    }

    func requestFullLocationAuthorizationAgain() {
        pendingAlwaysAuthorizationRequestTask?.cancel()
        pendingAlwaysAuthorizationRequestTask = nil
        didAttemptAlwaysAuthorizationInCurrentSession = false

        if !settings.trackAndReportLocation {
            settings.trackAndReportLocation = true
        }

        requestLocationPermission()

        if settings.trackAndReportLocation,
           !settings.deviceKeyAuthBlocked {
            startTracking()
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
        guard !Self.shouldPreserveEnabledTrackingPreferenceForUITests else { return }

        let status = locationManager.authorizationStatus
        if settings.trackAndReportLocation {
            switch status {
            case .notDetermined:
                // Trigger first-time prompt
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                requestAlwaysAuthorizationIfPossible(reason: "ensure authorization")
            default:
                break
            }
        }
    }

    private func requestAlwaysAuthorizationIfPossible(reason: String, delay: TimeInterval = 0.6) {
        guard settings.trackAndReportLocation,
              locationManager.authorizationStatus == .authorizedWhenInUse,
              !didAttemptAlwaysAuthorizationInCurrentSession,
              pendingAlwaysAuthorizationRequestTask == nil else {
            return
        }

        let delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        pendingAlwaysAuthorizationRequestTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.pendingAlwaysAuthorizationRequestTask = nil
            guard self.settings.trackAndReportLocation,
                  self.locationManager.authorizationStatus == .authorizedWhenInUse,
                  !self.didAttemptAlwaysAuthorizationInCurrentSession else {
                return
            }

            self.didAttemptAlwaysAuthorizationInCurrentSession = true
            debugLog("Requesting Always authorization (\(reason))")
            self.locationManager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Tracking Control
    func startTracking(applicationStateContext: TrackingApplicationStateContext = .current) {
        debugLog("startTracking called")
        if Self.shouldPreserveEnabledTrackingPreferenceForUITests {
            authorizationStatus = locationManager.authorizationStatus
            isTracking = settings.trackAndReportLocation
            return
        }

        if settings.deviceKeyAuthBlocked {
            debugLog("startTracking blocked due to DeviceKey auth failure")
            isTracking = false
            stopAllLocationServices()
            return
        }
        handleTrackingPauseExpirationIfNeeded()
        ensureAuthorizationIfNeeded()
        let status = locationManager.authorizationStatus
        authorizationStatus = status
        if Self.shouldDisableTrackingPreference(authorizationStatus: status) {
            debugLog("startTracking disabled because location authorization is denied/restricted")
            isTracking = false
            if settings.trackAndReportLocation {
                settings.trackAndReportLocation = false
            }
            stopAllLocationServices()
            diagnosticsLog.append(
                level: .warning,
                event: "trackingReconcile",
                summary: "Tracking was disabled because location authorization is unavailable.",
                result: TrackingReconcileAction.stopAuthorizationUnavailable.rawValue,
                reason: "start tracking",
                checks: trackingEligibilityChecks(status: status),
                context: [
                    "authorizationStatus": .integer(Int(status.rawValue)),
                    "trackAndReportLocation": .bool(settings.trackAndReportLocation)
                ]
            )
            return
        }
        isTracking = true
        handleFrequentBackgroundLocationExpirationIfNeeded()
        restorePersistedSmartFrequentBackgroundSeedIfNeeded()
        applyTrackingMode(reason: "start tracking", applicationStateContext: applicationStateContext)
    }

    func restoreTrackingAfterLaunch(reason: String, applicationStateContext: TrackingApplicationStateContext = .current) {
        debugLog("[LocationManager] Restoring tracking after launch: \(reason)")
        authorizationStatus = locationManager.authorizationStatus
        if applicationStateContext == .forceBackground || UIApplication.shared.applicationState != .active {
            smartFrequentBackgroundStartupGuardPending = true
        }
        handleFrequentBackgroundLocationExpirationIfNeeded()
        handleTrackingPauseExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()
        refreshLocationTrackingHealthReminder()
        recordForensicRestoreAfterLaunch(trigger: "restore tracking after launch: \(reason)")

        guard Self.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: settings.trackAndReportLocation,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            trackingPaused: settings.isTrackingPaused
        ) else {
            isTracking = false
            stopAllLocationServices()
            return
        }

        ensureAuthorizationIfNeeded()
        isTracking = true
        restorePersistedSmartFrequentBackgroundSeedIfNeeded()
        let didResumeSmartFrequentRuntime = consumePersistedSmartFrequentBackgroundRuntimeMarkerAfterLaunchIfNeeded(reason: reason)
        debugLog("[LocationManager] restoreTrackingAfterLaunch reason=\(reason), status=\(authorizationStatus.rawValue), frequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), context=\(applicationStateContext)")
        recordLocationTrackingHealthReminderActivity(reason: "restore tracking after launch: \(reason)")
        diagnosticsLog.append(
            level: .info,
            event: "restoreTrackingAfterLaunch",
            summary: "Restored tracking after launch.",
            result: "tracking restored",
            reason: reason,
            checks: trackingEligibilityChecks(status: authorizationStatus),
            context: [
                "applicationStateContext": .string(String(describing: applicationStateContext)),
                "authorizationStatus": .integer(Int(authorizationStatus.rawValue)),
                "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled)
            ],
            persistence: .immediate
        )
        applyTrackingMode(reason: "restore tracking after launch: \(reason)", applicationStateContext: applicationStateContext)
        requestSmartFrequentRestartRecoveryLocationIfNeeded(
            didResume: didResumeSmartFrequentRuntime,
            applicationStateContext: applicationStateContext
        )
        refreshPendingLocationUpdateCount()
    }

    func rearmSignificantChangeMonitorAfterFreshLaunchIfNeeded(buildIdentifier: String, reason: String) {
        let status = locationManager.authorizationStatus
        handleTrackingPauseExpirationIfNeeded()
        let decision = backgroundForensicsRecorder.significantChangeRearmDecision(
            buildIdentifier: buildIdentifier,
            reason: reason,
            trackAndReportLocation: settings.trackAndReportLocation,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )

        backgroundForensicsRecorder.recordSignificantChangeRearmStatus(decision.status)
        syncBackgroundForensicsSnapshot()

        guard decision.shouldAttempt else {
            diagnosticsLog.append(
                level: .info,
                event: "significantChangeRearm",
                summary: "Skipped significant-change re-arm.",
                result: decision.status.result.rawValue,
                reason: decision.status.reason,
                checks: decision.status.checks,
                context: ["buildIdentifier": .string(buildIdentifier)],
                persistence: .immediate
            )
            return
        }

        debugLog("[LocationManager] Re-arming significant-change monitor after fresh launch (\(reason))")
        coreLocationServices.rearmSignificantChangeMonitorAfterFreshLaunch()
        backgroundForensicsRecorder.markSignificantChangeRearmed(buildIdentifier: buildIdentifier)

        diagnosticsLog.append(
            level: .warning,
            event: "significantChangeRearm",
            summary: "Re-armed significant-change monitor with stop/start.",
            result: decision.status.result.rawValue,
            reason: decision.status.reason,
            checks: decision.status.checks,
            context: [
                "buildIdentifier": .string(buildIdentifier),
                "allowsBackgroundLocationUpdates": .bool(locationManager.allowsBackgroundLocationUpdates)
            ],
            persistence: .immediate
        )
    }
    
    func stopTracking() {
        debugLog("stopTracking called")
        isTracking = false
        applyTrackingMode(reason: "stop tracking")
    }

    @discardableResult
    func pauseTracking(for duration: TrackingPauseDuration, now: Date = Date()) -> Date {
        let expiresAt = settings.pauseTracking(duration: duration, now: now)
        return activateServerUpdatePause(
            expiresAt: expiresAt,
            durationSeconds: duration.rawValue,
            now: now,
            reason: "user selected server update pause"
        )
    }

    @discardableResult
    func pauseTracking(forCustomDuration duration: TimeInterval, now: Date = Date()) -> Date {
        let expiresAt = settings.pauseTracking(duration: duration, now: now)
        return activateServerUpdatePause(
            expiresAt: expiresAt,
            durationSeconds: Int(TrackingPauseCustomDuration.normalized(duration)),
            now: now,
            reason: "user selected custom server update pause"
        )
    }

    @discardableResult
    private func activateServerUpdatePause(expiresAt: Date,
                                           durationSeconds: Int,
                                           now: Date,
                                           reason: String) -> Date {
        debugLog("[LocationManager] Server updates paused until \(expiresAt)")
        scheduleTrackingPauseExpirationTimer()

        Task {
            await self.discardPendingLocationUpdates()
            await Self.recordTrackingPausedEvent(until: expiresAt, at: now)
            await TrackingPauseNotificationService.shared.notifyTrackingPaused(until: expiresAt)
        }

        diagnosticsLog.append(
            level: .info,
            event: "trackingPause",
            summary: "Paused server update delivery temporarily.",
            result: "paused",
            reason: reason,
            checks: trackingEligibilityChecks(status: locationManager.authorizationStatus),
            context: [
                "expiresAt": .string(ISO8601DateFormatter().string(from: expiresAt)),
                "durationSeconds": .integer(durationSeconds)
            ],
            persistence: .immediate
        )
        if isTracking {
            applyTrackingMode(reason: "server update pause started")
        }
        return expiresAt
    }

    func resumeTrackingFromPause(now: Date = Date(), reason: String = "manual resume server updates") {
        guard settings.trackingPauseExpiresAt != nil else { return }
        settings.clearTrackingPause()
        trackingPauseExpirationTimer?.invalidate()
        trackingPauseExpirationTimer = nil
        debugLog("[LocationManager] Server update pause cleared (\(reason))")

        Task {
            await Self.recordTrackingResumedEvent(at: now, reason: reason)
            await TrackingPauseNotificationService.shared.cancelScheduledResumeNotification()
        }

        if isTracking {
            applyTrackingMode(reason: reason)
        }
    }

    @discardableResult
    func beginNavigationLocationSession(allowsHighAccuracyBackground: Bool = false) -> UUID {
        let id = UUID()
        navigationLocationSessionIDs.insert(id)
        if allowsHighAccuracyBackground {
            backgroundNavigationLocationSessionIDs.insert(id)
        }
        debugLog("[LocationManager] beginNavigationLocationSession id=\(id), activeSessions=\(navigationLocationSessionIDs.count), backgroundSessions=\(backgroundNavigationLocationSessionIDs.count)")
        applyTrackingMode(reason: "begin navigation location session")
        return id
    }

    func endNavigationLocationSession(_ id: UUID) {
        guard navigationLocationSessionIDs.remove(id) != nil else { return }
        backgroundNavigationLocationSessionIDs.remove(id)
        debugLog("[LocationManager] endNavigationLocationSession id=\(id), activeSessions=\(navigationLocationSessionIDs.count), backgroundSessions=\(backgroundNavigationLocationSessionIDs.count)")
        applyTrackingMode(reason: "end navigation location session")
    }

    private func trackingEligibilityChecks(status: CLAuthorizationStatus) -> [LocationDiagnosticsCheck] {
        [
            LocationDiagnosticsLogStore.check(
                "trackingEnabled",
                settings.trackAndReportLocation && isTracking,
                detail: "trackAndReportLocation=\(settings.trackAndReportLocation), isTracking=\(isTracking)."
            ),
            LocationDiagnosticsLogStore.check(
                "authorizedAlways",
                status == .authorizedAlways,
                detail: "Authorization status: \(status.rawValue)."
            ),
            LocationDiagnosticsLogStore.check(
                "deviceKeyNotBlocked",
                !settings.deviceKeyAuthBlocked,
                detail: settings.deviceKeyAuthBlocked ? "DeviceKey auth is blocked." : "DeviceKey auth is not blocked."
            )
        ]
    }

    private func diagnosticsLocationContext(_ location: CLLocation,
                                            extra: [(String, LocationDiagnosticsValue)] = []) -> [String: LocationDiagnosticsValue] {
        var context = LocationDiagnosticsLogStore.roundedLocationContext(location)
        for (key, value) in extra {
            context[key] = value
        }
        return context
    }

    private func diagnosticsLocationContext(_ location: CLLocation,
                                            acceptanceMetrics metrics: LocationSamplePolicy.AcceptanceMetrics,
                                            extra: [(String, LocationDiagnosticsValue)] = []) -> [String: LocationDiagnosticsValue] {
        var fields: [(String, LocationDiagnosticsValue)] = [
            ("horizontalAccuracyMeters", .double(metrics.horizontalAccuracy)),
            ("maximumHorizontalAccuracyMeters", .double(metrics.maximumHorizontalAccuracy)),
            ("maximumImplausibleSpeedKmh", .double(metrics.maximumImplausibleSpeedKmh)),
            ("maximumTrustedGpsSpeedKmh", .double(metrics.maximumTrustedGPSSpeedKmh)),
            ("maximumTrustedSpeedAccuracyMetersPerSecond", .double(metrics.maximumTrustedSpeedAccuracyMetersPerSecond)),
            ("largeJumpDistanceMeters", .double(metrics.largeJumpDistanceMeters)),
            ("largeJumpMinimumElapsedSeconds", .double(metrics.largeJumpMinimumElapsedSeconds)),
            ("largeJumpConfirmationRadiusMeters", .double(metrics.largeJumpConfirmationRadiusMeters))
        ]
        if let distanceMeters = metrics.distanceMeters {
            fields.append(("distanceMeters", .double(distanceMeters)))
        }
        if let elapsedSeconds = metrics.elapsedSeconds {
            fields.append(("elapsedSeconds", .double(elapsedSeconds)))
        }
        if let derivedSpeedKmh = metrics.derivedSpeedKmh {
            fields.append(("derivedSpeedKmh", .double(derivedSpeedKmh)))
        }
        if let gpsSpeedKmh = metrics.gpsSpeedKmh {
            fields.append(("gpsSpeedKmh", .double(gpsSpeedKmh)))
        }
        if let gpsSpeedAccuracy = metrics.gpsSpeedAccuracyMetersPerSecond {
            fields.append(("gpsSpeedAccuracyMetersPerSecond", .double(gpsSpeedAccuracy)))
        }
        if let previousAccuracy = metrics.previousHorizontalAccuracy {
            fields.append(("previousHorizontalAccuracyMeters", .double(previousAccuracy)))
        }
        fields.append(contentsOf: extra)
        return diagnosticsLocationContext(location, extra: fields)
    }

    private func shouldProcessLocationSample(_ location: CLLocation,
                                             now: Date,
                                             applicationState: UIApplication.State,
                                             updateSource: LocationUpdateSource) -> Bool {
        let decision = Self.locationSampleProcessingDecision(
            for: location,
            now: now,
            latestRawLocation: latestRawLocation,
            currentLocation: currentLocation,
            smartReferenceLocation: smartFrequentBackgroundSpeedReferenceLocation
        )
        guard decision == .process else {
            diagnosticsLog.append(
                level: .warning,
                event: "locationSample",
                summary: "Skipped CoreLocation sample before state processing.",
                result: decision.rawValue,
                reason: locationSampleRejectionReason(decision),
                checks: [
                    LocationDiagnosticsLogStore.check(
                        "sampleProcessable",
                        false,
                        detail: "Decision: \(decision.rawValue)."
                    )
                ],
                context: diagnosticsLocationContext(location, extra: [
                    ("source", .string(updateSource.rawValue)),
                    ("applicationState", .integer(applicationState.rawValue)),
                    ("maximumAgeSeconds", .integer(Int(Self.maximumLocationSampleAge))),
                    ("futureToleranceSeconds", .integer(Int(Self.maximumLocationSampleFutureSkew))),
                    ("latestReferenceTimestamp", latestLocationSampleReferenceTimestamp().map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("unknown"))
                ])
            )
            return false
        }
        return true
    }

    private func locationSampleRejectionReason(_ decision: LocationSampleProcessingDecision) -> String {
        switch decision {
        case .process:
            return "sample accepted"
        case .invalid:
            return "invalid coordinate or timestamp"
        case .futureDated:
            return "future-dated location sample"
        case .stale:
            return "stale location sample"
        case .outOfOrder:
            return "out-of-order location sample"
        }
    }

    private func latestLocationSampleReferenceTimestamp() -> Date? {
        LocationSamplePolicy.newestValidLocationTimestamp([
            latestRawLocation,
            currentLocation,
            smartFrequentBackgroundSpeedReferenceLocation
        ])
    }

    private func syncBackgroundForensicsSnapshot() {
        lastSignificantChangeRearmStatus = backgroundForensicsRecorder.lastSignificantChangeRearmStatus
        backgroundTrackingForensicState = backgroundForensicsRecorder.state
    }

    private func recordForensicRestoreAfterLaunch(trigger: String, now: Date = Date()) {
        backgroundForensicsRecorder.recordRestoreAfterLaunch(trigger: trigger, now: now)
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicModeResolution(mode: TrackingMode,
                                              applicationState: UIApplication.State,
                                              reason: String,
                                              now: Date = Date()) {
        backgroundForensicsRecorder.recordModeResolution(
            mode: mode,
            applicationState: applicationState,
            reason: reason,
            now: now
        )
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicServiceAssertion(mode: TrackingMode, now: Date = Date()) {
        backgroundForensicsRecorder.recordServiceAssertion(mode: mode, now: now)
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicForegroundOpen(trigger: String, now: Date = Date()) {
        backgroundForensicsRecorder.recordForegroundOpen(trigger: trigger, now: now)
        syncBackgroundForensicsSnapshot()
    }

    private func evaluateBackgroundTrackingGap(trigger: String,
                                               now: Date = Date(),
                                               prepareForegroundRecovery: Bool = false) {
        backgroundForensicsRecorder.evaluateGap(
            trigger: trigger,
            now: now,
            prepareForegroundRecovery: prepareForegroundRecovery
        )
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicLocationCallback(applicationState: UIApplication.State,
                                                source: LocationUpdateSource,
                                                timestamp: Date = Date()) {
        backgroundForensicsRecorder.recordLocationCallback(
            applicationState: applicationState,
            sourceRawValue: source.rawValue,
            isPrimarySource: source == .primary,
            timestamp: timestamp
        )
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicAcceptedLocation(applicationState: UIApplication.State,
                                                source: LocationUpdateSource,
                                                timestamp: Date = Date()) {
        backgroundForensicsRecorder.recordAcceptedLocation(
            applicationState: applicationState,
            isPrimarySource: source == .primary,
            timestamp: timestamp
        )
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicUpload(applicationState: UIApplication.State, timestamp: Date = Date()) {
        backgroundForensicsRecorder.recordUpload(applicationState: applicationState, timestamp: timestamp)
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicSmartActivation(at timestamp: Date) {
        backgroundForensicsRecorder.recordSmartActivation(at: timestamp)
        syncBackgroundForensicsSnapshot()
    }

    private func recordForensicSmartDeactivation(at timestamp: Date = Date()) {
        backgroundForensicsRecorder.recordSmartDeactivation(at: timestamp)
        syncBackgroundForensicsSnapshot()
    }

    @discardableResult
    private func reconcileTrackingState(reason: String,
                                        applicationStateContext: TrackingApplicationStateContext = .current,
                                        refreshExternalSettings: Bool = false) -> TrackingReconcileAction {
        let didRefreshExternalSettings: Bool
        if refreshExternalSettings {
            didRefreshExternalSettings = settings.refreshFromUserDefaultsForAppActivation(clearExpiredTrackingPause: false)
        } else {
            didRefreshExternalSettings = false
        }
        if didRefreshExternalSettings {
            diagnosticsLog.append(
                level: .info,
                event: "externalSettingsRefresh",
                summary: "Refreshed app settings from UserDefaults during activation.",
                result: "changed",
                reason: reason,
                checks: [],
                context: [
                    "trackAndReportLocation": .bool(settings.trackAndReportLocation),
                    "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                    "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                    "locationDiagnosticsLoggingEnabled": .bool(settings.locationDiagnosticsLoggingEnabled)
                ]
            )
        }

        let status = locationManager.authorizationStatus
        authorizationStatus = status
        handleFrequentBackgroundLocationExpirationIfNeeded()
        handleTrackingPauseExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()
        let action = Self.trackingReconcileAction(
            trackAndReportLocation: settings.trackAndReportLocation,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            authorizationStatus: status,
            isTracking: isTracking,
            trackingPaused: settings.isTrackingPaused
        )
        if Self.shouldPreserveEnabledTrackingPreferenceForUITests,
           settings.trackAndReportLocation {
            isTracking = true
            return .applyTrackingMode
        }

        let effectiveReason = didRefreshExternalSettings ? "\(reason) after external settings refresh" : reason
        let diagnosticsLevel: LocationDiagnosticsLogLevel
        switch action {
        case .stopAuthorizationUnavailable, .stopDeviceKeyBlocked:
            diagnosticsLevel = .warning
        default:
            diagnosticsLevel = .info
        }

        diagnosticsLog.append(
            level: diagnosticsLevel,
            event: "trackingReconcile",
            summary: "Reconciled tracking preference with current authorization and lifecycle state.",
            result: action.rawValue,
            reason: effectiveReason,
            checks: trackingEligibilityChecks(status: status),
            context: [
                "applicationStateContext": .string(String(describing: applicationStateContext)),
                "authorizationStatus": .integer(Int(status.rawValue)),
                "trackAndReportLocation": .bool(settings.trackAndReportLocation),
                "isTracking": .bool(isTracking),
                "trackingPaused": .bool(settings.isTrackingPaused),
                "trackingPauseExpiresAt": settings.trackingPauseExpiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("none"),
                "deviceKeyAuthBlocked": .bool(settings.deviceKeyAuthBlocked),
                "externalSettingsRefreshed": .bool(didRefreshExternalSettings)
            ]
        )

        switch action {
        case .stopAuthorizationUnavailable:
            isTracking = false
            if settings.trackAndReportLocation {
                settings.trackAndReportLocation = false
            }
            stopAllLocationServices()
        case .stopTrackingDisabled, .stopDeviceKeyBlocked:
            isTracking = false
            stopAllLocationServices()
        case .startTracking:
            startTracking(applicationStateContext: applicationStateContext)
        case .applyTrackingMode:
            applyTrackingMode(reason: effectiveReason, applicationStateContext: applicationStateContext)
        }

        return action
    }

    @discardableResult
    func reconcileTrackingStateForIntent(reason: String) -> TrackingReconcileAction {
        reconcileTrackingState(reason: reason)
    }

    private func applyTrackingMode(reason: String, applicationStateContext: TrackingApplicationStateContext = .current) {
        let state = Self.effectiveApplicationStateForTracking(
            currentState: UIApplication.shared.applicationState,
            context: applicationStateContext
        )
        let status = locationManager.authorizationStatus
        if Self.shouldPreserveEnabledTrackingPreferenceForUITests,
           settings.trackAndReportLocation {
            authorizationStatus = status
            isTracking = true
            return
        }

        if settings.deviceKeyAuthBlocked {
            debugLog("[LocationManager] applyTrackingMode stopped because DeviceKey auth is blocked")
            isTracking = false
            stopAllLocationServices()
            return
        }

        handleFrequentBackgroundLocationExpirationIfNeeded()
        handleTrackingPauseExpirationIfNeeded(reconcileTrackingMode: false)
        if Self.shouldEvaluateSmartFrequentRuntime(applicationState: state) {
            handleSmartFrequentBackgroundInactivityIfNeeded(applicationState: state)
        }
        if isTracking, state != .active {
            disableFrequentBackgroundLocationUpdatesIfBatteryIsLow()
        }
        syncFrequentBackgroundAccuracyRecoveryEligibility(applicationState: state)

        if Self.shouldDisableTrackingPreference(authorizationStatus: status) {
            debugLog("Location permission denied/restricted; disabling trackAndReportLocation and stopping services")
            isTracking = false
            if settings.trackAndReportLocation {
                settings.trackAndReportLocation = false
            }
        }

        let mode = Self.resolvedTrackingMode(
            isTracking: isTracking,
            authorizationStatus: status,
            applicationState: state,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter,
            hasNavigationLocationSession: !backgroundNavigationLocationSessionIDs.isEmpty,
            accuracyRecoveryActive: frequentBackgroundAccuracyRecoveryActive
        )
        let shouldMaintainRecoveryAnchor = Self.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: settings.trackAndReportLocation && isTracking,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            trackingPaused: settings.isTrackingPaused
        )
        let shouldMaintainFrequentActivitySession = Self.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: settings.trackAndReportLocation,
            isTracking: isTracking,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            trackingPaused: settings.isTrackingPaused,
            hasNavigationLocationSession: !backgroundNavigationLocationSessionIDs.isEmpty
        )
        let commandPlan = Self.locationServiceCommandPlan(
            for: mode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor
        )
        if state != .active {
            evaluateBackgroundTrackingGap(trigger: reason)
        }
        recordForensicModeResolution(mode: mode, applicationState: state, reason: reason)
        debugLog("[LocationManager] applyTrackingMode reason=\(reason), context=\(applicationStateContext), state=\(state.rawValue), status=\(status.rawValue), isTracking=\(isTracking), navigationSessions=\(navigationLocationSessionIDs.count), backgroundNavigationSessions=\(backgroundNavigationLocationSessionIDs.count), manualFrequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), smartEnabled=\(settings.smartFrequentBackgroundLocationUpdatesEnabled), smartRuntimeActive=\(smartFrequentBackgroundRuntimeActive), effectiveFrequent=\(effectiveFrequentBackgroundUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), primaryRecoveryAnchorActive=\(isSignificantChangeRecoveryAnchorActive), mode=\(mode), commandPlan=\(commandPlan)")
        diagnosticsLog.append(
            level: .info,
            event: "trackingModeResolution",
            summary: "Resolved location tracking mode.",
            result: String(describing: mode),
            reason: reason,
            checks: trackingEligibilityChecks(status: status) + [
                LocationDiagnosticsLogStore.check(
                    "backgroundEligible",
                    state != .active && status == .authorizedAlways && isTracking,
                    detail: "applicationState=\(state.rawValue)."
                )
            ],
            context: [
                "applicationState": .integer(state.rawValue),
                "authorizationStatus": .integer(Int(status.rawValue)),
                "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                "smartRuntimeActive": .bool(smartFrequentBackgroundRuntimeActive),
                "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue),
                "effectiveFrequent": .bool(effectiveFrequentBackgroundUpdatesEnabled),
                "trackingPaused": .bool(settings.isTrackingPaused),
                "trackingPauseExpiresAt": settings.trackingPauseExpiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("none"),
                "accuracyRecoveryActive": .bool(frequentBackgroundAccuracyRecoveryActive),
                "primaryRecoveryAnchorActive": .bool(isSignificantChangeRecoveryAnchorActive),
                "navigationSessions": .integer(navigationLocationSessionIDs.count),
                "backgroundNavigationSessions": .integer(backgroundNavigationLocationSessionIDs.count)
            ],
            persistence: .immediate
        )
        coreLocationServices.syncLocationServiceSession(
            reason: reason,
            shouldMaintainSession: Self.shouldMaintainLocationServiceSession(
                trackAndReportLocation: settings.trackAndReportLocation,
                isTracking: isTracking,
                authorizationStatus: status,
                deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
                trackingPaused: settings.isTrackingPaused
            )
        )
        coreLocationServices.syncFrequentBackgroundActivitySession(
            reason: reason,
            shouldMaintainSession: shouldMaintainFrequentActivitySession
        )
        apply(mode)
        ensureSignificantChangeRecoveryAnchorIfNeeded(reason: reason, shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor)
        reconcileSmartFrequentExitFence(reason: reason, applicationState: state)
    }

    private func apply(_ mode: TrackingMode) {
        syncBackgroundLocationIndicator(for: mode)
        switch mode {
        case .stopped:
            stopAllLocationServices()
        case .foregroundHighAccuracy:
            startHighAccuracyUpdates()
        case .backgroundSignificantChange:
            startSignificantChangeMonitoring()
        case .backgroundNavigation:
            let configuration = BackgroundUpdateConfiguration(
                usesSignificantChangeMonitoring: false,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyBestForNavigation
            )
            startFrequentBackgroundLocationUpdates(configuration: configuration)
        case .backgroundFrequent(let distanceFilter, let desiredAccuracy):
            let configuration = BackgroundUpdateConfiguration(
                usesSignificantChangeMonitoring: false,
                distanceFilter: distanceFilter,
                desiredAccuracy: desiredAccuracy
            )
            startFrequentBackgroundLocationUpdates(configuration: configuration)
        }
    }

    private func syncBackgroundLocationIndicator(for mode: TrackingMode) {
        let shouldShowIndicator = Self.shouldShowBackgroundLocationIndicator(for: mode)
        coreLocationServices.syncBackgroundLocationIndicator(shouldShowIndicator: shouldShowIndicator)
    }

    private func startHighAccuracyUpdates() {
        debugLog("Calling startHighAccuracyUpdates")
        recordForensicServiceAssertion(mode: .foregroundHighAccuracy)
        let shouldMaintainPrimarySignificantChangeMonitor = Self.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: settings.trackAndReportLocation && isTracking,
            authorizationStatus: locationManager.authorizationStatus,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            trackingPaused: settings.isTrackingPaused
        )
        coreLocationServices.startHighAccuracyUpdates(
            shouldMaintainPrimarySignificantChangeMonitor: shouldMaintainPrimarySignificantChangeMonitor
        )
        startHeadingUpdatesIfAvailable()
        if foregroundLocationTimer == nil {
            debugLog("App is active, will start foreground location timer")
            startForegroundLocationTimer()
        } else {
            debugLog("Foreground location timer already running")
        }
    }
    
    private func startSignificantChangeMonitoring() {
        debugLog("Starting significant-change background updates")
        recordForensicServiceAssertion(mode: .backgroundSignificantChange)
        coreLocationServices.startSignificantChangeMonitoring()
        stopHeadingUpdates()
        stopForegroundLocationTimer()
        diagnosticsLog.append(
            level: .info,
            event: "locationServiceStart",
            summary: "Started significant-change background monitoring.",
            result: "significant-change active",
            reason: nil,
            checks: trackingEligibilityChecks(status: locationManager.authorizationStatus),
            context: [
                "allowsBackgroundLocationUpdates": .bool(locationManager.allowsBackgroundLocationUpdates),
                "primaryRecoveryAnchorActive": .bool(isSignificantChangeRecoveryAnchorActive)
            ],
            persistence: .immediate
        )
    }

    private func startFrequentBackgroundLocationUpdates(configuration: BackgroundUpdateConfiguration) {
        debugLog("Starting frequent background updates with distanceFilter=\(configuration.distanceFilter)m")
        recordForensicServiceAssertion(mode: .backgroundFrequent(distanceFilter: configuration.distanceFilter, desiredAccuracy: configuration.desiredAccuracy))
        // Keep the primary manager registered for significant-change relaunch; run frequent standard updates separately.
        stopHeadingUpdates()
        coreLocationServices.startFrequentBackgroundLocationUpdates(
            configuration: configuration,
            delegate: self,
            activityType: Self.activityTypeFrom(settings.locationActivityType)
        )
        scheduleSmartFrequentBackgroundWatchdogIfNeeded()
        stopForegroundLocationTimer()
        diagnosticsLog.append(
            level: .info,
            event: "locationServiceStart",
            summary: "Started frequent background location updates.",
            result: "frequent background active",
            reason: nil,
            checks: trackingEligibilityChecks(status: locationManager.authorizationStatus),
            context: [
                "distanceFilterMeters": .double(configuration.distanceFilter),
                "desiredAccuracy": .double(configuration.desiredAccuracy),
                "primaryRecoveryAnchorActive": .bool(isSignificantChangeRecoveryAnchorActive),
                "secondaryStandardUpdatesActive": .bool(isFrequentBackgroundStandardUpdatesActive),
                "frequentManagerAllowsBackground": .bool(frequentBackgroundLocationManager.allowsBackgroundLocationUpdates),
                "frequentManagerShowsIndicator": .bool(frequentBackgroundLocationManager.showsBackgroundLocationIndicator),
                "frequentActivitySessionActive": .bool(coreLocationServices.frequentBackgroundActivitySessionActive),
                "accuracyRecoveryActive": .bool(frequentBackgroundAccuracyRecoveryActive),
                "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue)
            ],
            persistence: .immediate
        )
    }

    private func cleanUpStaleFrequentBackgroundCallbackIfNeeded(
        updateSource: LocationUpdateSource,
        didSwitchFrequentBackgroundMode: Bool
    ) -> StaleFrequentBackgroundCallbackCleanupResult {
        guard Self.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            updateSourceIsFrequentBackground: updateSource == .frequentBackground
        ) else { return .noCleanup }

        let shouldSuppressCallback = Self.shouldSuppressStaleFrequentBackgroundCallback(
            allowNextStaleCallback: coreLocationServices.consumeAllowNextStaleFrequentBackgroundCallback()
        )

        let handling = shouldSuppressCallback ? "suppressing repeated stale location" : "location remains eligible for upload"
        debugLog("[LocationManager] Cleaning up stale frequent background callback while frequent mode is disabled; \(handling)")
        coreLocationServices.stopFrequentBackgroundStandardUpdates()
        coreLocationServices.stopFrequentBackgroundActivitySession(reason: "stale frequent background callback")

        return StaleFrequentBackgroundCallbackCleanupResult(
            didCleanUp: true,
            shouldSuppressCallback: shouldSuppressCallback
        )
    }

    private func reassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeIfNeeded(
        applicationState: UIApplication.State,
        updateSource: LocationUpdateSource,
        didSwitchFrequentBackgroundMode: Bool
    ) {
        guard Self.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: isFrequentBackgroundStandardUpdatesActive,
            updateSourceIsPrimary: updateSource == .primary
        ) else { return }

        debugLog("[LocationManager] Reasserting frequent background updates after primary significant-change callback")
        applyTrackingMode(
            reason: "frequent background reassert after primary significant-change callback",
            applicationStateContext: .forceBackground
        )
    }

    private func reassertStandardSignificantChangeAfterPrimaryCallbackIfNeeded(
        applicationState: UIApplication.State,
        updateSource: LocationUpdateSource,
        didSwitchFrequentBackgroundMode: Bool
    ) {
        let shouldMaintainRecoveryAnchor = Self.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: settings.trackAndReportLocation && isTracking,
            authorizationStatus: locationManager.authorizationStatus,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            trackingPaused: settings.isTrackingPaused
        )
        guard Self.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor,
            updateSourceIsPrimary: updateSource == .primary
        ) else { return }

        debugLog("[LocationManager] Reasserting standard significant-change tracking after primary background callback")
        coreLocationServices.allowPrimaryBackgroundLocationUpdates()
        coreLocationServices.startSignificantChangeRecoveryAnchor(reason: "standard significant-change callback reassert")
    }

    private func ensureSignificantChangeRecoveryAnchorIfNeeded(reason: String, shouldMaintainRecoveryAnchor: Bool) {
        guard shouldMaintainRecoveryAnchor else {
            coreLocationServices.stopSignificantChangeRecoveryAnchor(reason: "recovery anchor no longer eligible: \(reason)")
            return
        }

        coreLocationServices.startSignificantChangeRecoveryAnchor(reason: "recovery anchor: \(reason)")
    }

    private func reconcileSmartFrequentExitFence(reason: String,
                                                applicationState: UIApplication.State = UIApplication.shared.applicationState) {
        let regionMonitoringAvailable = CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
        let shouldMaintainFence = Self.shouldMaintainSmartFrequentExitFence(
            trackAndReportLocation: settings.trackAndReportLocation,
            isTracking: isTracking,
            authorizationStatus: locationManager.authorizationStatus,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
            regionMonitoringAvailable: regionMonitoringAvailable
        ) &&
        applicationState != .active &&
        smartFrequentBackgroundRuntimePhase != .probing &&
        !smartFrequentExitFenceRecoveryAwaitingLocationUpdate

        guard shouldMaintainFence else {
            stopSmartFrequentExitFence(reason: "not eligible: \(reason)")
            return
        }

        let existingRegion = smartFrequentExitFenceRegion()
        guard let anchorLocation = smartFrequentExitFenceAnchorLocation() else {
            isSmartFrequentExitFenceActive = existingRegion != nil
            return
        }

        let radius = Self.smartFrequentExitFenceRadius(
            configuredRadiusMeters: settings.smartFrequentBackgroundExitFenceRadiusMeters,
            maximumRegionMonitoringDistance: locationManager.maximumRegionMonitoringDistance
        )
        if let existingRegion {
            let existingCenterLocation = CLLocation(
                latitude: existingRegion.center.latitude,
                longitude: existingRegion.center.longitude
            )
            let anchorDrift = anchorLocation.distance(from: existingCenterLocation)
            if anchorDrift < 25,
               abs(existingRegion.radius - radius) < 1 {
                isSmartFrequentExitFenceActive = true
                return
            }
        }

        stopSmartFrequentExitFence(reason: "recenter: \(reason)")
        let region = CLCircularRegion(
            center: anchorLocation.coordinate,
            radius: radius,
            identifier: Self.smartFrequentExitFenceIdentifier
        )
        region.notifyOnEntry = false
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
        isSmartFrequentExitFenceActive = true
        let context = diagnosticsLocationContext(anchorLocation, extra: [
            ("radiusMeters", .double(radius))
        ])
        if reason == "location update" {
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "smartFrequentExitFence",
                summary: "Started Smart frequent exit-fence monitoring.",
                result: "active",
                reason: reason,
                coalescingKey: "smartFrequentExitFence|active|locationUpdate",
                context: context
            )
        } else {
            diagnosticsLog.append(
                level: .info,
                event: "smartFrequentExitFence",
                summary: "Started Smart frequent exit-fence monitoring.",
                result: "active",
                reason: reason,
                context: context
            )
        }
    }

    private func stopSmartFrequentExitFence(reason: String) {
        let regions = locationManager.monitoredRegions.filter {
            $0.identifier == Self.smartFrequentExitFenceIdentifier
        }
        guard !regions.isEmpty || isSmartFrequentExitFenceActive else {
            return
        }

        for region in regions {
            locationManager.stopMonitoring(for: region)
        }
        isSmartFrequentExitFenceActive = false
        if reason.hasPrefix("recenter:") {
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "smartFrequentExitFence",
                summary: "Stopped Smart frequent exit-fence monitoring.",
                result: "stopped",
                reason: reason,
                coalescingKey: "smartFrequentExitFence|stopped|recenter"
            )
        } else {
            diagnosticsLog.append(
                level: .info,
                event: "smartFrequentExitFence",
                summary: "Stopped Smart frequent exit-fence monitoring.",
                result: "stopped",
                reason: reason
            )
        }
    }

    private func smartFrequentExitFenceRegion() -> CLCircularRegion? {
        locationManager.monitoredRegions
            .compactMap { $0 as? CLCircularRegion }
            .first { $0.identifier == Self.smartFrequentExitFenceIdentifier }
    }

    private func smartFrequentExitFenceAnchorLocation() -> CLLocation? {
        Self.newestSmartFrequentExitFenceAnchor(from: [
            latestRawLocation,
            currentLocation,
            smartFrequentBackgroundSpeedReferenceLocation
        ])
    }

    private static func isUsableForSmartFenceAnchor(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        CLLocationCoordinate2DIsValid(coordinate) &&
        location.timestamp.timeIntervalSince1970.isFinite &&
        location.horizontalAccuracy.isFinite &&
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= 300
    }

    private func handleSmartFrequentExitFenceExit(region: CLRegion) {
        guard region.identifier == Self.smartFrequentExitFenceIdentifier else {
            return
        }

        let now = Date()
        let applicationState = UIApplication.shared.applicationState
        guard let circularRegion = region as? CLCircularRegion else {
            diagnosticsLog.append(
                level: .warning,
                event: "smartFrequentExitFence",
                summary: "Ignored non-circular Smart frequent exit-fence event.",
                result: "ignored",
                reason: "Unexpected region type."
            )
            return
        }
        let radius = circularRegion.radius
        let batteryAboveThreshold = !isBatteryAtOrBelowFrequentBackgroundThreshold()
        let baseEligibility = applicationState != .active &&
        isTracking &&
        settings.trackAndReportLocation &&
        locationManager.authorizationStatus == .authorizedAlways &&
        !settings.deviceKeyAuthBlocked &&
        settings.smartFrequentBackgroundLocationUpdatesEnabled &&
        !settings.frequentBackgroundLocationUpdatesEnabled &&
        batteryAboveThreshold

        if smartFrequentBackgroundRuntimeActive {
            guard baseEligibility else {
                diagnosticsLog.append(
                    level: .info,
                    event: "smartFrequentExitFence",
                    summary: NSLocalizedString("location_diagnostics_smart_frequent_recovery_fence_blocked_summary", tableName: "LocationTracking", comment: "Diagnostics summary when Smart frequent recovery fence cannot reassert frequent background updates"
                    ),
                    result: "blocked",
                    reason: batteryAboveThreshold ? NSLocalizedString("location_diagnostics_smart_frequent_recovery_ineligible_reason", tableName: "LocationTracking", comment: "Diagnostics reason when Smart frequent recovery is not currently eligible"
                    ) : "Battery is at or below frequent background threshold.",
                    context: [
                        "applicationState": .integer(applicationState.rawValue),
                        "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                        "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                        "smartRuntimeActive": .bool(smartFrequentBackgroundRuntimeActive),
                        "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue),
                        "radiusMeters": .double(radius)
                    ]
                )
                reconcileSmartFrequentExitFence(reason: "recovery-fence exit blocked")
                return
            }

            stopSmartFrequentExitFence(reason: "Smart frequent recovery-fence triggered")
            smartFrequentExitFenceRecoveryAwaitingLocationUpdate = true
            var recoveryContext = smartFrequentRecoveryDiagnosticsContext(
                now: now,
                recoveryAttemptCount: smartFrequentBackgroundRecoveryAttemptCount
            )
            recoveryContext["radiusMeters"] = .double(radius)
            diagnosticsLog.append(
                level: .warning,
                event: "smartFrequentRecovery",
                summary: NSLocalizedString("location_diagnostics_smart_frequent_recovery_fence_reasserted_summary", tableName: "LocationTracking", comment: "Diagnostics summary when a Smart frequent recovery fence reasserts frequent background updates"
                ),
                result: "reasserted",
                reason: NSLocalizedString("location_diagnostics_smart_frequent_recovery_fence_exit_reason", tableName: "LocationTracking", comment: "Diagnostics reason when Smart frequent recovery was triggered by a recovery fence exit"
                ),
                checks: [],
                context: recoveryContext,
                timestamp: now,
                persistence: .immediate
            )
            applyTrackingMode(reason: "smart frequent recovery-fence", applicationStateContext: .forceBackground)
            requestFrequentBackgroundLocationIfSafe(reason: "smart frequent recovery-fence", now: now)
            scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
            return
        }

        let shouldActivate = baseEligibility

        guard shouldActivate else {
            diagnosticsLog.append(
                level: .info,
                event: "smartFrequentExitFence",
                summary: "Smart frequent exit-fence event did not activate runtime.",
                result: "blocked",
                reason: batteryAboveThreshold ? "Smart frequent is not eligible." : "Battery is at or below frequent background threshold.",
                context: [
                    "applicationState": .integer(applicationState.rawValue),
                    "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                    "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                    "smartRuntimeActive": .bool(smartFrequentBackgroundRuntimeActive),
                    "radiusMeters": .double(radius)
                ]
            )
            reconcileSmartFrequentExitFence(reason: "exit event blocked")
            return
        }

        let activationLocation = CLLocation(
            coordinate: circularRegion.center,
            altitude: 0,
            horizontalAccuracy: max(circularRegion.radius, 0),
            verticalAccuracy: -1,
            course: -1,
            speed: -1,
            timestamp: now
        )

        stopSmartFrequentExitFence(reason: "Smart frequent exit-fence triggered")
        beginSmartFrequentBackgroundProbe(
            location: activationLocation,
            evidence: .regionExit(radiusMeters: radius),
            now: now
        )
        applyTrackingMode(reason: "smart frequent exit-fence", applicationStateContext: .forceBackground)
    }

    @discardableResult
    private func disableFrequentBackgroundLocationUpdatesIfBatteryIsLow() -> Bool {
        let thresholdPercent = settings.frequentBackgroundBatteryAutoDisableLevel
        guard let batteryPercent = Self.batteryPercent(from: UIDevice.current.batteryLevel),
              Self.shouldDisableFrequentBackgroundUpdatesForBattery(
                frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
                batteryPercent: batteryPercent,
                thresholdPercent: thresholdPercent
              ) else {
            return false
        }

        if settings.frequentBackgroundLocationUpdatesEnabled {
            settings.frequentBackgroundLocationUpdatesEnabled = false
        }
        if smartFrequentBackgroundRuntimeActive {
            deactivateSmartFrequentBackgroundRuntime(reason: "smart frequent battery auto-disable")
        }
        scheduleFrequentBackgroundLocationExpirationTimer()
        debugLog("[LocationManager] Effective frequent background updates disabled because battery is at \(batteryPercent)% (threshold \(thresholdPercent)%)")

        Task {
            await Self.recordLowBatteryDisabledFrequentTrackingEvent(
                batteryPercent: batteryPercent,
                thresholdPercent: thresholdPercent
            )
            await FrequentBackgroundTrackingReminderService.shared.notifyBatteryAutoDisable(
                batteryPercent: batteryPercent,
                thresholdPercent: thresholdPercent
            )
        }
        return true
    }

    @discardableResult
    private func handleFrequentBackgroundLocationExpirationIfNeeded(now: Date = Date()) -> Bool {
        let didExpire = settings.disableExpiredFrequentBackgroundLocationUpdatesIfNeeded(now: now)
        if didExpire {
            debugLog("[LocationManager] Frequent background updates expired; returning to significant-change monitoring")
            Task {
                await Self.recordFrequentTrackingExpiredEvent(at: now)
            }
        } else {
            settings.ensureFrequentBackgroundLocationUpdatesExpiration(now: now)
        }
        scheduleFrequentBackgroundLocationExpirationTimer()
        return didExpire
    }

    @discardableResult
    private func handleTrackingPauseExpirationIfNeeded(now: Date = Date(),
                                                       reconcileTrackingMode: Bool = true) -> Bool {
        let didExpire = settings.disableExpiredTrackingPauseIfNeeded(now: now)
        if didExpire {
            debugLog("[LocationManager] Server update pause expired; uploads can resume")
            Task {
                await Self.recordTrackingResumedEvent(at: now, reason: "server update pause expired")
            }
            if reconcileTrackingMode, isTracking {
                applyTrackingMode(reason: "server update pause expired")
            }
        }
        scheduleTrackingPauseExpirationTimer()
        Task {
            await TrackingPauseNotificationService.shared.refresh(pauseExpiresAt: settings.trackingPauseExpiresAt)
        }
        return didExpire
    }

    static func recordLowBatteryDisabledFrequentTrackingEvent(
        batteryPercent: Int,
        thresholdPercent: Int,
        recorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared
    ) async {
        await recorder.record(
            kind: .lowBatteryDisabledFrequentTracking,
            privacyLevel: .publicSummary,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: [
                "batteryPercent": String(batteryPercent),
                "thresholdPercent": String(thresholdPercent)
            ]
        )
    }

    static func recordFrequentTrackingExpiredEvent(
        at date: Date,
        recorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared
    ) async {
        await recorder.record(
            kind: .frequentTrackingExpired,
            privacyLevel: .publicSummary,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: ["expiredAt": ISO8601DateFormatter().string(from: date)]
        )
    }

    static func recordTrackingPausedEvent(
        until expiresAt: Date,
        at date: Date = Date(),
        recorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared
    ) async {
        await recorder.record(
            kind: .trackingPaused,
            privacyLevel: .publicSummary,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: [
                "pausedAt": ISO8601DateFormatter().string(from: date),
                "expiresAt": ISO8601DateFormatter().string(from: expiresAt)
            ]
        )
    }

    static func recordTrackingResumedEvent(
        at date: Date = Date(),
        reason: String,
        recorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared
    ) async {
        await recorder.record(
            kind: .trackingResumed,
            privacyLevel: .publicSummary,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: [
                "resumedAt": ISO8601DateFormatter().string(from: date),
                "reason": reason
            ]
        )
    }

    private func scheduleFrequentBackgroundLocationExpirationTimer() {
        frequentBackgroundLocationExpirationTimer?.invalidate()
        frequentBackgroundLocationExpirationTimer = nil

        guard settings.frequentBackgroundLocationUpdatesEnabled,
              let expiresAt = settings.frequentBackgroundLocationUpdatesExpiresAt else {
            return
        }

        let interval = expiresAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.handleFrequentBackgroundLocationExpirationIfNeeded(), self.isTracking {
                self.applyTrackingMode(reason: "frequent background expiration timer")
            }
        }
        frequentBackgroundLocationExpirationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleTrackingPauseExpirationTimer() {
        trackingPauseExpirationTimer?.invalidate()
        trackingPauseExpirationTimer = nil

        guard let expiresAt = settings.trackingPauseExpiresAt,
              expiresAt > Date() else {
            return
        }

        let interval = expiresAt.timeIntervalSinceNow
        guard interval > 0 else { return }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            _ = self.handleTrackingPauseExpirationIfNeeded()
        }
        trackingPauseExpirationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshFrequentBackgroundTrackingReminder() {
        let locationTrackingEnabled = settings.trackAndReportLocation
        let frequentBackgroundUpdatesEnabled = settings.frequentBackgroundLocationUpdatesEnabled
        let durationMode = settings.frequentBackgroundLocationUpdateDurationMode
        let expiresAt = settings.frequentBackgroundLocationUpdatesExpiresAt

        Task {
            await FrequentBackgroundTrackingReminderService.shared.refresh(
                locationTrackingEnabled: locationTrackingEnabled,
                frequentBackgroundUpdatesEnabled: frequentBackgroundUpdatesEnabled,
                durationMode: durationMode,
                expiresAt: expiresAt
            )
        }
    }

    private func recordLocationTrackingHealthReminderActivity(reason: String) {
        let locationTrackingEnabled = locationTrackingHealthReminderIsEnabled
        let interval = settings.locationTrackingHealthReminderIntervalSelection

        Task {
            await LocationTrackingHealthReminderService.shared.recordConfirmedActivity(
                locationTrackingEnabled: locationTrackingEnabled,
                interval: interval
            )
        }

        debugLog("[LocationManager] Location tracking health reminder activity recorded: \(reason)")
    }

    private func refreshLocationTrackingHealthReminder() {
        let locationTrackingEnabled = locationTrackingHealthReminderIsEnabled
        let interval = settings.locationTrackingHealthReminderIntervalSelection

        Task {
            await LocationTrackingHealthReminderService.shared.refresh(
                locationTrackingEnabled: locationTrackingEnabled,
                interval: interval
            )
        }
    }

    private var locationTrackingHealthReminderIsEnabled: Bool {
        settings.trackAndReportLocation
    }

    private func notifySmartFrequentBackgroundModeChangeIfEnabled(
        isActive: Bool,
        deactivationReason: FrequentBackgroundTrackingReminderService.SmartFrequentDeactivationReason = .inactivity
    ) {
        guard settings.smartFrequentBackgroundModeChangeNotificationsEnabled else {
            return
        }

        Task {
            await FrequentBackgroundTrackingReminderService.shared.notifySmartFrequentModeChange(
                isActive: isActive,
                deactivationReason: deactivationReason
            )
        }
    }

    private func persistConfirmedSmartFrequentBackgroundRuntimeMarker(confirmedAt: Date) {
        smartFrequentBackgroundConfirmedAt = confirmedAt
        let marker = SmartFrequentBackgroundRuntimeMarker(
            phase: .confirmedActive,
            confirmedAt: confirmedAt,
            lastRelevantMovementAt: smartFrequentBackgroundLastRelevantMovementAt,
            activationNotificationDelivered: smartFrequentBackgroundActivationNotificationDelivered
        )
        smartFrequentBackgroundRuntimeMarkerStore.save(marker)
    }

    private func persistCurrentConfirmedSmartFrequentBackgroundRuntimeMarkerIfNeeded() {
        guard smartFrequentBackgroundRuntimePhase == .confirmedActive else {
            return
        }

        let confirmedAt = smartFrequentBackgroundConfirmedAt ??
        smartFrequentBackgroundProbeStartedAt ??
        smartFrequentBackgroundLastRelevantMovementAt ??
        Date()
        persistConfirmedSmartFrequentBackgroundRuntimeMarker(confirmedAt: confirmedAt)
    }

    private func clearPersistedSmartFrequentBackgroundRuntimeMarker() {
        smartFrequentBackgroundConfirmedAt = nil
        smartFrequentBackgroundRuntimeMarkerStore.clear()
    }

    @discardableResult
    private func consumePersistedSmartFrequentBackgroundRuntimeMarkerAfterLaunchIfNeeded(reason: String,
                                                                                        now: Date = Date()) -> Bool {
        guard let marker = smartFrequentBackgroundRuntimeMarkerStore.consume() else {
            return false
        }

        let inactivityWindow = settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
        let restartAction = Self.smartFrequentRestartRecoveryAction(
            marker: marker,
            now: now,
            inactivityWindow: inactivityWindow,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            authorizationStatus: authorizationStatus,
            trackAndReportLocation: settings.trackAndReportLocation,
            isTracking: isTracking,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            modeChangeNotificationsEnabled: settings.smartFrequentBackgroundModeChangeNotificationsEnabled
        )
        let markerReferenceAt = Self.smartFrequentRuntimeMarkerReferenceDate(marker)
        let markerReferenceAge = now.timeIntervalSince(markerReferenceAt)
        let markerIsFresh = Self.isSmartFrequentRuntimeMarkerFresh(
            marker,
            now: now,
            inactivityWindow: inactivityWindow
        )

        diagnosticsLog.append(
            level: restartAction == .ignore ? .info : .warning,
            event: "smartFrequentRestartRecovery",
            summary: restartAction == .resume ? "Restored persisted Smart frequent runtime after launch." : "Consumed persisted Smart frequent runtime marker after launch.",
            result: restartAction.rawValue,
            reason: reason,
            checks: [
                LocationDiagnosticsLogStore.check(
                    "confirmedActiveMarker",
                    marker.phase == .confirmedActive,
                    detail: "Persisted phase: \(marker.phase.rawValue)."
                ),
                LocationDiagnosticsLogStore.check(
                    "runtimeMarkerFresh",
                    markerIsFresh,
                    detail: "Marker reference age: \(markerReferenceAge)s, inactivity window: \(inactivityWindow)s."
                ),
                LocationDiagnosticsLogStore.check(
                    "smartEnabled",
                    settings.smartFrequentBackgroundLocationUpdatesEnabled,
                    detail: "Smart frequent enabled: \(settings.smartFrequentBackgroundLocationUpdatesEnabled)."
                ),
                LocationDiagnosticsLogStore.check(
                    "manualFrequentDisabled",
                    !settings.frequentBackgroundLocationUpdatesEnabled,
                    detail: "Manual frequent enabled: \(settings.frequentBackgroundLocationUpdatesEnabled)."
                ),
                LocationDiagnosticsLogStore.check(
                    "authorizedAlways",
                    authorizationStatus == .authorizedAlways,
                    detail: "Authorization status: \(authorizationStatus.rawValue)."
                ),
                LocationDiagnosticsLogStore.check(
                    "trackingRestored",
                    settings.trackAndReportLocation && isTracking && !settings.deviceKeyAuthBlocked,
                    detail: "Tracking restored: \(settings.trackAndReportLocation && isTracking && !settings.deviceKeyAuthBlocked)."
                ),
                LocationDiagnosticsLogStore.check(
                    "modeChangeNotificationsEnabled",
                    settings.smartFrequentBackgroundModeChangeNotificationsEnabled,
                    detail: "Smart frequent mode-change notifications enabled: \(settings.smartFrequentBackgroundModeChangeNotificationsEnabled)."
                )
            ],
            context: [
                "confirmedAt": .string(ISO8601DateFormatter().string(from: marker.confirmedAt)),
                "lastRelevantMovementAt": marker.lastRelevantMovementAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("unknown"),
                "restartRecoveryReferenceAt": .string(ISO8601DateFormatter().string(from: markerReferenceAt)),
                "restartRecoveryReferenceAgeSeconds": .double(markerReferenceAge),
                "inactivityWindowSeconds": .double(inactivityWindow),
                "activationNotificationDelivered": .bool(marker.activationNotificationDelivered)
            ],
            persistence: .immediate
        )

        switch restartAction {
        case .resume:
            resumePersistedSmartFrequentBackgroundRuntime(marker: marker, referenceAt: markerReferenceAt, now: now)
            return true

        case .notifyDeactivation:
            notifySmartFrequentBackgroundModeChangeIfEnabled(
                isActive: false,
                deactivationReason: .restartRecovery
            )
            return false

        case .ignore:
            return false
        }
    }

    private func resumePersistedSmartFrequentBackgroundRuntime(marker: SmartFrequentBackgroundRuntimeMarker,
                                                              referenceAt: Date,
                                                              now: Date) {
        smartFrequentBackgroundConfirmedAt = marker.confirmedAt
        smartFrequentBackgroundActivationNotificationDelivered = marker.activationNotificationDelivered
        smartFrequentBackgroundLastRelevantMovementAt = marker.lastRelevantMovementAt ?? marker.confirmedAt
        lastSmartFrequentBackgroundLocationUpdateAt = referenceAt
        smartFrequentBackgroundProbeStartedAt = referenceAt
        smartFrequentBackgroundLastFrequentCallbackAt = referenceAt
        smartFrequentBackgroundRecoveryAttemptCount = 0
        smartFrequentBackgroundLastMovementLocationKey = nil
        smartFrequentBackgroundLastMovementDistanceMeters = nil
        smartFrequentBackgroundLastMovementThresholdMeters = nil
        smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false
        if let seedLocation = smartFrequentBackgroundSpeedReferenceLocation,
           isUsableForSmartFrequentBackgroundState(seedLocation) {
            smartFrequentBackgroundMovementAnchor = seedLocation
        }
        smartFrequentBackgroundLastActivationReason = NSLocalizedString("smart_frequent_background_activation_movement", tableName: "LocationTracking", comment: "Smart frequent activation reason when movement is detected"
        )
        resetFrequentBackgroundAccuracyRecoveryState()
        transitionSmartFrequentBackgroundRuntime(
            to: .confirmedActive,
            reason: "restored confirmed Smart frequent runtime after launch",
            now: now
        )
        persistConfirmedSmartFrequentBackgroundRuntimeMarker(confirmedAt: marker.confirmedAt)
        scheduleSmartFrequentBackgroundInactivityTimer(now: now)
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
    }

    private func requestSmartFrequentRestartRecoveryLocationIfNeeded(
        didResume: Bool,
        applicationStateContext: TrackingApplicationStateContext
    ) {
        let applicationState = Self.effectiveApplicationStateForTracking(
            currentState: UIApplication.shared.applicationState,
            context: applicationStateContext
        )
        guard didResume,
              applicationState != .active,
              settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled,
              smartFrequentBackgroundRuntimeActive else {
            return
        }

        requestFrequentBackgroundLocationIfSafe(reason: "smart frequent restart recovery")
    }

    private func requestFrequentBackgroundLocationIfSafe(reason: String, now: Date = Date()) {
        let status = locationManager.authorizationStatus
        let frequentUpdatesEnabled = effectiveFrequentBackgroundUpdatesEnabled
        let frequentStandardUpdatesActive = isFrequentBackgroundStandardUpdatesActive
        let delegateReady = coreLocationServices.frequentBackgroundLocationRequestDelegateReady
        let shouldRequest = Self.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: isTracking,
            authorizationStatus: status,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            frequentBackgroundStandardUpdatesActive: frequentStandardUpdatesActive,
            delegateReady: delegateReady
        )

        guard shouldRequest else {
            let checks = [
                LocationDiagnosticsLogStore.check(
                    "trackingActive",
                    isTracking,
                    detail: "isTracking=\(isTracking)."
                ),
                LocationDiagnosticsLogStore.check(
                    "authorizedAlways",
                    status == .authorizedAlways,
                    detail: "Authorization status: \(status.rawValue)."
                ),
                LocationDiagnosticsLogStore.check(
                    "effectiveFrequentBackgroundEnabled",
                    frequentUpdatesEnabled,
                    detail: "effectiveFrequent=\(frequentUpdatesEnabled)."
                ),
                LocationDiagnosticsLogStore.check(
                    "frequentStandardUpdatesActive",
                    frequentStandardUpdatesActive,
                    detail: "frequent standard updates active=\(frequentStandardUpdatesActive)."
                ),
                LocationDiagnosticsLogStore.check(
                    "frequentDelegateReady",
                    delegateReady,
                    detail: "Frequent background delegate can receive one-shot callbacks."
                )
            ]
            diagnosticsLog.append(
                level: .warning,
                event: "frequentBackgroundOneShotRequest",
                summary: "Skipped frequent background one-shot location request.",
                result: "skipped",
                reason: checks.first(where: { !$0.passed })?.detail,
                checks: checks,
                context: [
                    "requestReason": .string(reason),
                    "applicationState": .integer(UIApplication.shared.applicationState.rawValue),
                    "authorizationStatus": .integer(Int(status.rawValue)),
                    "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                    "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                    "smartRuntimeActive": .bool(smartFrequentBackgroundRuntimeActive),
                    "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue),
                    "effectiveFrequent": .bool(frequentUpdatesEnabled),
                    "frequentStandardUpdatesActive": .bool(frequentStandardUpdatesActive),
                    "frequentDelegateReady": .bool(delegateReady),
                    "frequentManagerAllowsBackground": .bool(frequentBackgroundLocationManager.allowsBackgroundLocationUpdates),
                    "frequentManagerShowsIndicator": .bool(frequentBackgroundLocationManager.showsBackgroundLocationIndicator)
                ],
                timestamp: now,
                persistence: .immediate
            )
            return
        }

        coreLocationServices.requestFrequentBackgroundLocation()
    }

    private func syncFrequentBackgroundAccuracyRecoveryEligibility(applicationState: UIApplication.State) {
        guard Self.isFrequentBackgroundAccuracyRecoveryEligible(
            applicationState: applicationState,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
            distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter
        ) else {
            resetFrequentBackgroundAccuracyRecoveryState()
            return
        }
    }

    @discardableResult
    private func handleFrequentBackgroundAccuracyRecovery(for location: CLLocation,
                                                          updateSource: LocationUpdateSource,
                                                          applicationState: UIApplication.State,
                                                          now: Date) -> Bool {
        guard updateSource == .frequentBackground,
              applicationState != .active else {
            return false
        }

        let evaluation = Self.frequentBackgroundAccuracyRecoveryEvaluation(
            applicationState: applicationState,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
            distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter,
            horizontalAccuracy: location.horizontalAccuracy,
            currentPoorAccuracyStreak: frequentBackgroundPoorAccuracyStreak,
            recoveryActive: frequentBackgroundAccuracyRecoveryActive,
            recoveryStartedAt: frequentBackgroundAccuracyRecoveryStartedAt,
            lastRecoveryEndedAt: frequentBackgroundAccuracyRecoveryEndedAt,
            now: now
        )
        frequentBackgroundPoorAccuracyStreak = evaluation.poorAccuracyStreak

        if evaluation.shouldStopRecovery {
            let reason = Self.isFrequentBackgroundLocationAccuracyAcceptable(
                applicationState: applicationState,
                updateSourceIsFrequentBackground: true,
                horizontalAccuracy: location.horizontalAccuracy,
                distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter
            ) ? "frequent background accuracy recovered" : "frequent background accuracy recovery timeout"
            return stopFrequentBackgroundAccuracyRecovery(reason: reason, location: location, now: now)
        }

        if evaluation.shouldStartRecovery {
            startFrequentBackgroundAccuracyRecovery(location: location, now: now)
            return true
        }

        return false
    }

    private func startFrequentBackgroundAccuracyRecovery(location: CLLocation,
                                                         now: Date) {
        guard !frequentBackgroundAccuracyRecoveryActive else { return }
        frequentBackgroundAccuracyRecoveryActive = true
        frequentBackgroundAccuracyRecoveryStartedAt = now
        frequentBackgroundAccuracyRecoveryTimer?.invalidate()
        scheduleFrequentBackgroundAccuracyRecoveryTimer()

        diagnosticsLog.append(
            level: .warning,
            event: "frequentBackgroundAccuracyRecovery",
            summary: "Started frequent background accuracy recovery.",
            result: "started",
            reason: "frequent background location accuracy is poor",
            checks: [],
            context: diagnosticsLocationContext(location, extra: [
                ("configuredDistanceFilterMeters", .integer(settings.frequentBackgroundLocationDistanceFilter)),
                ("recoveryDistanceFilterMeters", .integer(LocationTrackingPolicy.frequentBackgroundAccuracyRecoveryDistanceFilterMeters)),
                ("poorAccuracyStreak", .integer(frequentBackgroundPoorAccuracyStreak))
            ]),
            timestamp: now
        )

        applyTrackingMode(reason: "frequent background accuracy recovery", applicationStateContext: .forceBackground)
        requestFrequentBackgroundLocationIfSafe(reason: "frequent background accuracy recovery", now: now)
    }

    @discardableResult
    private func stopFrequentBackgroundAccuracyRecovery(reason: String,
                                                        location: CLLocation? = nil,
                                                        now: Date = Date()) -> Bool {
        guard frequentBackgroundAccuracyRecoveryActive else {
            frequentBackgroundPoorAccuracyStreak = 0
            return false
        }

        frequentBackgroundAccuracyRecoveryActive = false
        frequentBackgroundPoorAccuracyStreak = 0
        frequentBackgroundAccuracyRecoveryStartedAt = nil
        frequentBackgroundAccuracyRecoveryEndedAt = now
        frequentBackgroundAccuracyRecoveryTimer?.invalidate()
        frequentBackgroundAccuracyRecoveryTimer = nil

        var context: [String: LocationDiagnosticsValue] = [
            "configuredDistanceFilterMeters": .integer(settings.frequentBackgroundLocationDistanceFilter),
            "cooldownSeconds": .integer(Int(LocationTrackingPolicy.frequentBackgroundAccuracyRecoveryCooldown))
        ]
        if let location {
            context.merge(diagnosticsLocationContext(location)) { _, new in new }
        }

        diagnosticsLog.append(
            level: .info,
            event: "frequentBackgroundAccuracyRecovery",
            summary: "Stopped frequent background accuracy recovery.",
            result: "stopped",
            reason: reason,
            checks: [],
            context: context,
            timestamp: now
        )

        applyTrackingMode(reason: reason, applicationStateContext: .forceBackground)
        return true
    }

    private func resetFrequentBackgroundAccuracyRecoveryState() {
        frequentBackgroundAccuracyRecoveryActive = false
        frequentBackgroundPoorAccuracyStreak = 0
        frequentBackgroundAccuracyRecoveryStartedAt = nil
        frequentBackgroundAccuracyRecoveryTimer?.invalidate()
        frequentBackgroundAccuracyRecoveryTimer = nil
    }

    private func scheduleFrequentBackgroundAccuracyRecoveryTimer() {
        frequentBackgroundAccuracyRecoveryTimer?.invalidate()
        let timer = Timer(timeInterval: Self.frequentBackgroundAccuracyRecoveryDuration, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stopFrequentBackgroundAccuracyRecovery(
                reason: "frequent background accuracy recovery timeout",
                now: Date()
            )
        }
        frequentBackgroundAccuracyRecoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func isUsableForSmartFrequentBackgroundState(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        CLLocationCoordinate2DIsValid(coordinate) &&
        location.timestamp.timeIntervalSince1970.isFinite &&
        location.horizontalAccuracy.isFinite &&
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= Self.maximumSmartFrequentBackgroundStateAccuracy
    }

    private func updateSmartFrequentBackgroundRuntime(for location: CLLocation,
                                                      updateSource: LocationUpdateSource,
                                                      applicationState: UIApplication.State,
                                                      isStartupBatch: Bool = false,
                                                      now: Date = Date()) -> Bool {
        guard settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            if settings.frequentBackgroundLocationUpdatesEnabled,
               smartFrequentBackgroundRuntimeActive {
                deactivateSmartFrequentBackgroundRuntime(reason: "manual frequent override")
                return true
            }
            if isUsableForSmartFrequentBackgroundState(location) {
                updateSmartFrequentBackgroundSpeedReference(with: location)
            }
            return false
        }

        guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: applicationState) else {
            if isUsableForSmartFrequentBackgroundState(location) {
                updateSmartFrequentBackgroundSpeedReference(with: location)
            }
            return false
        }

        let didDeactivateForInactivity = handleSmartFrequentBackgroundInactivityIfNeeded(
            now: now,
            applicationState: applicationState
        )
        if smartFrequentBackgroundRuntimeActive {
            lastSmartFrequentBackgroundLocationUpdateAt = now
        }
        guard isUsableForSmartFrequentBackgroundState(location) else {
            return didDeactivateForInactivity
        }
        let previousLocationUpdateAt = smartFrequentBackgroundSpeedReferenceLocation?.timestamp
        let didUpdateMovement = refreshSmartFrequentBackgroundMovementState(for: location, now: now)
        let activationEvidence = Self.smartFrequentActivationEvidence(
            for: location,
            previousLocation: smartFrequentBackgroundSpeedReferenceLocation,
            detectionMode: settings.smartFrequentBackgroundSpeedDetectionModeSelection,
            thresholdKmh: settings.smartFrequentBackgroundSpeedThresholdKmh,
            frequentDistanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter,
            isStartupBatch: isStartupBatch
        )
        updateSmartFrequentBackgroundSpeedReference(with: location)

        guard !smartFrequentBackgroundRuntimeActive else {
            if didUpdateMovement {
                scheduleSmartFrequentBackgroundInactivityTimer(now: now)
            }
            return didDeactivateForInactivity
        }

        let sourceIsPrimary = updateSource == .primary
        let canActivate = Self.canActivateSmartFrequentBackgroundUpdates(
            now: now,
            locationTimestamp: location.timestamp,
            previousLocationUpdateAt: previousLocationUpdateAt,
            inactivityWindow: settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval,
            evidenceKind: activationEvidence.kind
        )
        let evidenceActivates = activationEvidence.activates
        let batteryAboveThreshold = !isBatteryAtOrBelowFrequentBackgroundThreshold()

        guard sourceIsPrimary,
              canActivate,
              evidenceActivates,
              batteryAboveThreshold else {
            if diagnosticsLog.isEnabled {
                let activationChecks = [
                    LocationDiagnosticsLogStore.check(
                        "sourceIsPrimary",
                        sourceIsPrimary,
                        detail: "Update source: \(updateSource.rawValue)."
                    ),
                    LocationDiagnosticsLogStore.check(
                        "smartCanActivate",
                        canActivate,
                        detail: "Previous location timestamp: \(String(describing: previousLocationUpdateAt))."
                    ),
                    LocationDiagnosticsLogStore.check(
                        "activationEvidenceTrusted",
                        evidenceActivates,
                        detail: activationEvidence.reason
                    ),
                    LocationDiagnosticsLogStore.check(
                        "batteryAboveThreshold",
                        batteryAboveThreshold,
                        detail: "Battery is above frequent background auto-disable threshold."
                    )
                ]
                diagnosticsLog.append(
                    level: .info,
                    event: "smartFrequentActivation",
                    summary: "Smart frequent runtime was not activated.",
                    result: "blocked",
                    reason: activationChecks.first(where: { !$0.passed })?.detail,
                    checks: activationChecks,
                    context: diagnosticsLocationContext(location, extra: [
                        ("smartFrequentActivationEvidence", .string(activationEvidence.kind.rawValue)),
                        ("smartFrequentStartupGuardActive", .bool(isStartupBatch)),
                        ("speedKmh", activationEvidence.speedKmh.map { .double($0) } ?? .string("unknown")),
                        ("speedAccuracyMetersPerSecond", activationEvidence.speedAccuracyMetersPerSecond.map { .double($0) } ?? .string("unknown")),
                        ("distanceMeters", activationEvidence.distanceMeters.map { .double($0) } ?? .string("unknown")),
                        ("elapsedSeconds", activationEvidence.elapsedSeconds.map { .double($0) } ?? .string("unknown")),
                        ("thresholdKmh", .integer(settings.smartFrequentBackgroundSpeedThresholdKmh))
                    ])
                )
            }
            return didDeactivateForInactivity
        }

        beginSmartFrequentBackgroundProbe(
            location: location,
            evidence: activationEvidence,
            now: now
        )
        return true
    }

    private func beginSmartFrequentBackgroundProbe(location: CLLocation,
                                                   evidence: SmartFrequentActivationEvidence,
                                                   now: Date) {
        transitionSmartFrequentBackgroundRuntime(to: .probing, reason: evidence.reason, location: location, evidence: evidence, now: now)
        lastSmartFrequentBackgroundLocationUpdateAt = now
        smartFrequentBackgroundLastRelevantMovementAt = now
        smartFrequentBackgroundMovementAnchor = location
        smartFrequentBackgroundProbeStartedAt = now
        smartFrequentBackgroundLastFrequentCallbackAt = nil
        smartFrequentBackgroundRecoveryAttemptCount = 0
        smartFrequentBackgroundLastMovementLocationKey = nil
        smartFrequentBackgroundLastMovementDistanceMeters = nil
        smartFrequentBackgroundLastMovementThresholdMeters = nil
        smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false
        if let speedKmh = evidence.speedKmh {
            smartFrequentBackgroundLastActivationReason = String(
                format: NSLocalizedString("smart_frequent_background_activation_speed_format", tableName: "LocationTracking", comment: "Smart frequent activation reason with speed in km/h"
                ),
                speedKmh
            )
        } else {
            smartFrequentBackgroundLastActivationReason = NSLocalizedString("smart_frequent_background_activation_movement", tableName: "LocationTracking", comment: "Smart frequent activation reason when movement is detected"
            )
        }
        scheduleSmartFrequentBackgroundInactivityTimer(now: now)
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
        debugLog("[LocationManager] Smart frequent background probe started evidence=\(evidence.kind.rawValue), speedKmh=\(String(describing: evidence.speedKmh))")
        recordForensicSmartActivation(at: now)
        diagnosticsLog.append(
            level: .warning,
            event: "smartFrequentActivation",
            summary: "Smart frequent runtime probe started.",
            result: "probing",
            reason: smartFrequentBackgroundLastActivationReason,
            checks: [
                LocationDiagnosticsLogStore.check("smartCanActivate", true, detail: "Smart frequent activation criteria passed."),
                LocationDiagnosticsLogStore.check("activationEvidenceTrusted", true, detail: evidence.reason),
                LocationDiagnosticsLogStore.check("batteryAboveThreshold", true, detail: "Battery is above frequent background auto-disable threshold.")
            ],
            context: diagnosticsLocationContext(location, extra: [
                ("smartFrequentActivationEvidence", .string(evidence.kind.rawValue)),
                ("speedKmh", evidence.speedKmh.map { .double($0) } ?? .string("unknown")),
                ("speedAccuracyMetersPerSecond", evidence.speedAccuracyMetersPerSecond.map { .double($0) } ?? .string("unknown")),
                ("distanceMeters", evidence.distanceMeters.map { .double($0) } ?? .string("unknown")),
                ("elapsedSeconds", evidence.elapsedSeconds.map { .double($0) } ?? .string("unknown")),
                ("distanceFilterMeters", .integer(settings.frequentBackgroundLocationDistanceFilter))
            ]),
            persistence: .immediate
        )
    }

    private func transitionSmartFrequentBackgroundRuntime(to phase: SmartFrequentRuntimePhase,
                                                          reason: String,
                                                          location: CLLocation? = nil,
                                                          evidence: SmartFrequentActivationEvidence? = nil,
                                                          now: Date = Date()) {
        let previousPhase = smartFrequentBackgroundRuntimePhase
        smartFrequentBackgroundRuntimePhase = phase
        smartFrequentBackgroundRuntimeActive = phase != .waiting
        guard previousPhase != phase else { return }

        var context: [String: LocationDiagnosticsValue] = [
            "previousPhase": .string(previousPhase.rawValue),
            "phase": .string(phase.rawValue),
            "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
            "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
            "runtimeActive": .bool(smartFrequentBackgroundRuntimeActive)
        ]
        if let location {
            context.merge(diagnosticsLocationContext(location)) { _, new in new }
        }
        if let evidence {
            context["smartFrequentActivationEvidence"] = .string(evidence.kind.rawValue)
            context["speedKmh"] = evidence.speedKmh.map { .double($0) } ?? .string("unknown")
            context["distanceMeters"] = evidence.distanceMeters.map { .double($0) } ?? .string("unknown")
            context["elapsedSeconds"] = evidence.elapsedSeconds.map { .double($0) } ?? .string("unknown")
        }

        diagnosticsLog.append(
            level: phase == .waiting ? .info : .warning,
            event: "smartFrequentRuntimePhase",
            summary: "Smart frequent runtime phase changed.",
            result: phase.rawValue,
            reason: reason,
            checks: [],
            context: context,
            timestamp: now,
            persistence: .immediate
        )
    }

    private func confirmSmartFrequentBackgroundRuntimeIfNeeded(location: CLLocation,
                                                               updateSource: LocationUpdateSource,
                                                               applicationState: UIApplication.State,
                                                               now: Date = Date()) {
        guard smartFrequentBackgroundRuntimePhase == .probing,
              updateSource == .frequentBackground,
              Self.shouldEvaluateSmartFrequentRuntime(applicationState: applicationState) else {
            return
        }

        let locationKey = Self.locationSubmissionDeduplicationKey(for: location)
        let movementWasConfirmed = locationKey != nil &&
        locationKey == smartFrequentBackgroundLastMovementLocationKey &&
        Self.shouldConfirmSmartFrequentBackgroundMovement(
            distanceMeters: smartFrequentBackgroundLastMovementDistanceMeters,
            thresholdMeters: smartFrequentBackgroundLastMovementThresholdMeters ?? CLLocationDistance(settings.frequentBackgroundLocationDistanceFilter)
        )

        guard movementWasConfirmed else {
            return
        }

        transitionSmartFrequentBackgroundRuntime(
            to: .confirmedActive,
            reason: "confirmed frequent background movement",
            location: location,
            now: now
        )
        smartFrequentBackgroundActivationNotificationDelivered = true
        persistConfirmedSmartFrequentBackgroundRuntimeMarker(confirmedAt: now)
        notifySmartFrequentBackgroundModeChangeIfEnabled(isActive: true)
        scheduleSmartFrequentBackgroundInactivityTimer(now: now)
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
        diagnosticsLog.append(
            level: .warning,
            event: "smartFrequentActivation",
            summary: "Smart frequent runtime confirmed active.",
            result: "confirmedActive",
            reason: "accepted frequent background movement",
            checks: [
                LocationDiagnosticsLogStore.check("sourceIsFrequentBackground", true, detail: "Update source: \(updateSource.rawValue)."),
                LocationDiagnosticsLogStore.check("movementConfirmed", true, detail: "Movement crossed the frequent threshold.")
            ],
            context: diagnosticsLocationContext(location, extra: [
                ("distanceMeters", smartFrequentBackgroundLastMovementDistanceMeters.map { .double($0) } ?? .string("unknown")),
                ("distanceFilterMeters", .integer(settings.frequentBackgroundLocationDistanceFilter))
            ]),
            timestamp: now,
            persistence: .immediate
        )
    }

    @discardableResult
    private func deactivateSmartFrequentBackgroundRuntime(reason: String,
                                                          sendsModeChangeNotification: Bool = true,
                                                          diagnosticsContext: [String: LocationDiagnosticsValue] = [:]) -> Bool {
        let wasActive = smartFrequentBackgroundRuntimeActive
        let shouldNotifyDeactivation = wasActive && smartFrequentBackgroundActivationNotificationDelivered && sendsModeChangeNotification
        transitionSmartFrequentBackgroundRuntime(to: .waiting, reason: reason)
        lastSmartFrequentBackgroundLocationUpdateAt = nil
        smartFrequentBackgroundMovementAnchor = nil
        smartFrequentBackgroundProbeStartedAt = nil
        smartFrequentBackgroundLastFrequentCallbackAt = nil
        smartFrequentBackgroundRecoveryAttemptCount = 0
        smartFrequentBackgroundActivationNotificationDelivered = false
        smartFrequentBackgroundLastMovementLocationKey = nil
        smartFrequentBackgroundLastMovementDistanceMeters = nil
        smartFrequentBackgroundLastMovementThresholdMeters = nil
        smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false
        smartFrequentBackgroundNextInactivityTimeoutAt = nil
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil
        resetFrequentBackgroundAccuracyRecoveryState()
        clearPersistedSmartFrequentBackgroundRuntimeMarker()
        if wasActive {
            debugLog("[LocationManager] Smart frequent background runtime deactivated: \(reason)")
            recordForensicSmartDeactivation()
            var context: [String: LocationDiagnosticsValue] = [
                "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled)
            ]
            context.merge(diagnosticsContext) { _, new in new }
            diagnosticsLog.append(
                level: .warning,
                event: "smartFrequentDeactivation",
                summary: "Smart frequent runtime deactivated.",
                result: "deactivated",
                reason: reason,
                checks: [],
                context: context,
                persistence: .immediate
            )
            if shouldNotifyDeactivation {
                notifySmartFrequentBackgroundModeChangeIfEnabled(isActive: false)
            }
        }
        return wasActive
    }

    private func resetSmartFrequentBackgroundRuntime() {
        smartFrequentBackgroundRuntimeActive = false
        smartFrequentBackgroundRuntimePhase = .waiting
        smartFrequentBackgroundLastActivationReason = nil
        smartFrequentBackgroundLastRelevantMovementAt = nil
        smartFrequentBackgroundNextInactivityTimeoutAt = nil
        lastSmartFrequentBackgroundLocationUpdateAt = nil
        smartFrequentBackgroundMovementAnchor = nil
        smartFrequentBackgroundSpeedReferenceLocation = nil
        smartFrequentBackgroundProbeStartedAt = nil
        smartFrequentBackgroundLastFrequentCallbackAt = nil
        smartFrequentBackgroundRecoveryAttemptCount = 0
        smartFrequentBackgroundActivationNotificationDelivered = false
        smartFrequentBackgroundLastMovementLocationKey = nil
        smartFrequentBackgroundLastMovementDistanceMeters = nil
        smartFrequentBackgroundLastMovementThresholdMeters = nil
        smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil
        resetFrequentBackgroundAccuracyRecoveryState()
        clearPersistedSmartFrequentBackgroundRuntimeMarker()
    }

    @discardableResult
    private func handleSmartFrequentBackgroundInactivityIfNeeded(now: Date = Date(),
                                                                 applicationState: UIApplication.State = UIApplication.shared.applicationState) -> Bool {
        guard settings.smartFrequentBackgroundLocationUpdatesEnabled,
              smartFrequentBackgroundRuntimeActive,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            scheduleSmartFrequentBackgroundInactivityTimer(now: now)
            return false
        }
        guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: applicationState) else {
            return false
        }

        let inactivityWindow = settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
        guard Self.shouldDeactivateSmartFrequentBackgroundUpdates(
            now: now,
            lastLocationUpdateAt: lastSmartFrequentBackgroundLocationUpdateAt,
            lastRelevantMovementAt: smartFrequentBackgroundLastRelevantMovementAt,
            inactivityWindow: inactivityWindow
        ) else {
            scheduleSmartFrequentBackgroundInactivityTimer(now: now)
            return false
        }

        return deactivateSmartFrequentBackgroundRuntime(reason: "smart frequent inactivity timeout")
    }

    @discardableResult
    private func refreshSmartFrequentBackgroundMovementState(for location: CLLocation,
                                                             now: Date) -> Bool {
        smartFrequentBackgroundLastMovementLocationKey = nil
        smartFrequentBackgroundLastMovementDistanceMeters = nil
        smartFrequentBackgroundLastMovementThresholdMeters = nil
        guard smartFrequentBackgroundRuntimeActive else { return false }
        lastSmartFrequentBackgroundLocationUpdateAt = now
        smartFrequentExitFenceRecoveryAwaitingLocationUpdate = false

        guard let anchor = smartFrequentBackgroundMovementAnchor else {
            smartFrequentBackgroundMovementAnchor = location
            smartFrequentBackgroundLastRelevantMovementAt = now
            smartFrequentBackgroundLastMovementLocationKey = Self.locationSubmissionDeduplicationKey(for: location)
            smartFrequentBackgroundLastMovementDistanceMeters = nil
            smartFrequentBackgroundLastMovementThresholdMeters = CLLocationDistance(settings.frequentBackgroundLocationDistanceFilter)
            persistCurrentConfirmedSmartFrequentBackgroundRuntimeMarkerIfNeeded()
            return true
        }

        let distance = location.distance(from: anchor)
        let movementThreshold = Self.smartFrequentMovementDistanceThreshold(
            frequentDistanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter,
            from: anchor,
            to: location
        )
        guard distance.isFinite,
              distance >= movementThreshold else {
            return false
        }

        smartFrequentBackgroundMovementAnchor = location
        smartFrequentBackgroundLastRelevantMovementAt = now
        smartFrequentBackgroundLastMovementLocationKey = Self.locationSubmissionDeduplicationKey(for: location)
        smartFrequentBackgroundLastMovementDistanceMeters = distance
        smartFrequentBackgroundLastMovementThresholdMeters = movementThreshold
        persistCurrentConfirmedSmartFrequentBackgroundRuntimeMarkerIfNeeded()
        return true
    }

    private func scheduleSmartFrequentBackgroundInactivityTimer(now: Date = Date()) {
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil

        guard settings.smartFrequentBackgroundLocationUpdatesEnabled,
              smartFrequentBackgroundRuntimeActive,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            setSmartFrequentBackgroundNextInactivityTimeout(nil)
            return
        }

        let inactivityWindow = settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
        switch Self.smartFrequentBackgroundInactivityTimerAction(
            now: now,
            lastLocationUpdateAt: lastSmartFrequentBackgroundLocationUpdateAt,
            lastRelevantMovementAt: smartFrequentBackgroundLastRelevantMovementAt,
            inactivityWindow: inactivityWindow
        ) {
        case .none:
            setSmartFrequentBackgroundNextInactivityTimeout(nil)
            logSmartFrequentInactivityTimerNotScheduledForStaleCallbackGap(
                now: now,
                inactivityWindow: inactivityWindow
            )
            return

        case .expired:
            setSmartFrequentBackgroundNextInactivityTimeout(nil)
            guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.shared.applicationState) else {
                return
            }
            if handleSmartFrequentBackgroundInactivityIfNeeded(now: now, applicationState: .background), isTracking {
                applyTrackingMode(reason: "smart frequent inactivity timer")
            }
            return

        case .schedule(let timeout):
            setSmartFrequentBackgroundNextInactivityTimeout(timeout)

            let interval = timeout.timeIntervalSince(now)
            guard interval > 0 else {
                return
            }

            let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
                guard let self else { return }
                guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.shared.applicationState) else {
                    return
                }
                if self.handleSmartFrequentBackgroundInactivityIfNeeded(applicationState: .background), self.isTracking {
                    self.applyTrackingMode(reason: "smart frequent inactivity timer")
                }
            }
            smartFrequentBackgroundInactivityTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func setSmartFrequentBackgroundNextInactivityTimeout(_ timeout: Date?) {
        guard smartFrequentBackgroundNextInactivityTimeoutAt != timeout else { return }
        smartFrequentBackgroundNextInactivityTimeoutAt = timeout
    }

    private func logSmartFrequentInactivityTimerNotScheduledForStaleCallbackGap(now: Date,
                                                                                inactivityWindow: TimeInterval) {
        guard inactivityWindow > 0,
              let lastLocationUpdateAt = lastSmartFrequentBackgroundLocationUpdateAt,
              let lastRelevantMovementAt = smartFrequentBackgroundLastRelevantMovementAt,
              now.timeIntervalSince(lastLocationUpdateAt) >= inactivityWindow,
              lastRelevantMovementAt.addingTimeInterval(inactivityWindow) <= now else {
            return
        }

        let formatter = ISO8601DateFormatter()
        diagnosticsLog.appendCoalesced(
            level: .info,
            event: "smartFrequentInactivityTimer",
            summary: "Smart frequent inactivity timer was not scheduled.",
            result: "notScheduled",
            reason: "stale callback gap prevents inactivity evaluation",
            coalescingKey: "smartFrequentInactivityTimer|notScheduled|staleCallbackGap",
            context: [
                "lastLocationUpdateAt": .string(formatter.string(from: lastLocationUpdateAt)),
                "lastRelevantMovementAt": .string(formatter.string(from: lastRelevantMovementAt)),
                "lastLocationUpdateAgeSeconds": .double(now.timeIntervalSince(lastLocationUpdateAt)),
                "lastRelevantMovementAgeSeconds": .double(now.timeIntervalSince(lastRelevantMovementAt)),
                "inactivityWindowSeconds": .double(inactivityWindow),
                "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue)
            ],
            timestamp: now
        )
    }

    private func scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: Date = Date()) {
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil

        guard smartFrequentBackgroundRuntimePhase != .waiting,
              settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            return
        }

        let timer = Timer(timeInterval: Self.smartFrequentBackgroundRuntimeWatchdogInterval, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.handleSmartFrequentBackgroundWatchdog(now: Date())
        }
        smartFrequentBackgroundWatchdogTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func recordSmartFrequentBackgroundFrequentCallbackIfNeeded(updateSource: LocationUpdateSource,
                                                                       now: Date = Date()) {
        guard updateSource == .frequentBackground,
              smartFrequentBackgroundRuntimeActive else {
            return
        }
        smartFrequentBackgroundLastFrequentCallbackAt = now
        smartFrequentBackgroundRecoveryAttemptCount = 0
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
    }

    private func smartFrequentRecoveryDiagnosticsContext(now: Date,
                                                         recoveryAttemptCount: Int,
                                                         watchdogReference: Date? = nil) -> [String: LocationDiagnosticsValue] {
        SmartFrequentBackgroundPolicy.recoveryDiagnosticsContext(
            now: now,
            recoveryAttemptCount: recoveryAttemptCount,
            maximumRecoveryAttempts: Self.maximumSmartFrequentBackgroundRuntimeRecoveryAttempts,
            phase: smartFrequentBackgroundRuntimePhase,
            frequentManagerAllowsBackground: frequentBackgroundLocationManager.allowsBackgroundLocationUpdates,
            frequentManagerShowsIndicator: frequentBackgroundLocationManager.showsBackgroundLocationIndicator,
            frequentStandardUpdatesActive: isFrequentBackgroundStandardUpdatesActive,
            frequentActivitySessionActive: coreLocationServices.frequentBackgroundActivitySessionActive,
            lastFrequentCallbackAt: smartFrequentBackgroundLastFrequentCallbackAt,
            lastBackgroundUploadAt: backgroundForensicsRecorder.state.lastBackgroundUploadAt,
            runtimeStartedAt: smartFrequentBackgroundProbeStartedAt,
            lastRelevantMovementAt: smartFrequentBackgroundLastRelevantMovementAt,
            watchdogReference: watchdogReference
        )
    }

    private func handleSmartFrequentBackgroundWatchdog(now: Date = Date()) {
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil

        guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.shared.applicationState) else {
            return
        }

        let runtimeReference = smartFrequentBackgroundLastFrequentCallbackAt ??
        smartFrequentBackgroundProbeStartedAt ??
        smartFrequentBackgroundLastRelevantMovementAt
        switch Self.smartFrequentBackgroundWatchdogAction(
            phase: smartFrequentBackgroundRuntimePhase,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            lastFrequentCallbackAt: smartFrequentBackgroundLastFrequentCallbackAt,
            runtimeStartedAt: runtimeReference,
            recoveryAttemptCount: smartFrequentBackgroundRecoveryAttemptCount,
            now: now
        ) {
        case .ignore:
            return
        case .wait:
            scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
            return
        case .deactivate:
            let diagnosticsContext = smartFrequentRecoveryDiagnosticsContext(
                now: now,
                recoveryAttemptCount: smartFrequentBackgroundRecoveryAttemptCount,
                watchdogReference: runtimeReference
            )
            let didDeactivate = deactivateSmartFrequentBackgroundRuntime(
                reason: "smart frequent recovery watchdog exhausted",
                diagnosticsContext: diagnosticsContext
            )
            if didDeactivate, isTracking {
                applyTrackingMode(reason: "smart frequent recovery watchdog exhausted", applicationStateContext: .forceBackground)
            }
            return
        case .reassert:
            break
        }

        smartFrequentBackgroundRecoveryAttemptCount += 1
        let diagnosticsContext = smartFrequentRecoveryDiagnosticsContext(
            now: now,
            recoveryAttemptCount: smartFrequentBackgroundRecoveryAttemptCount,
            watchdogReference: runtimeReference
        )
        diagnosticsLog.append(
            level: .warning,
            event: "smartFrequentRecovery",
            summary: "Reasserted Smart frequent background updates.",
            result: "reasserted",
            reason: "frequent background callback watchdog",
            checks: [],
            context: diagnosticsContext,
            timestamp: now,
            persistence: .immediate
        )

        if isTracking {
            applyTrackingMode(reason: "smart frequent recovery watchdog", applicationStateContext: .forceBackground)
            requestFrequentBackgroundLocationIfSafe(reason: "smart frequent recovery watchdog", now: now)
        }
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
    }

    private func restorePersistedSmartFrequentBackgroundSeedIfNeeded(now: Date = Date()) {
        guard smartFrequentBackgroundSpeedReferenceLocation == nil,
              let seedLocation = persistedSmartFrequentBackgroundSeedLocation(now: now) else {
            return
        }

        smartFrequentBackgroundSpeedReferenceLocation = seedLocation
        debugLog("[LocationManager] Restored Smart frequent seed timestamp=\(seedLocation.timestamp)")
    }

    private func persistedSmartFrequentBackgroundSeedLocation(now: Date = Date()) -> CLLocation? {
        guard let latitude = userDefaults.object(forKey: smartFrequentBackgroundSeedLatitudeKey) as? Double,
              let longitude = userDefaults.object(forKey: smartFrequentBackgroundSeedLongitudeKey) as? Double,
              let horizontalAccuracy = userDefaults.object(forKey: smartFrequentBackgroundSeedHorizontalAccuracyKey) as? Double,
              let timestamp = userDefaults.object(forKey: smartFrequentBackgroundSeedTimestampKey) as? Date else {
            return nil
        }

        let inactivityWindow = settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
        let seedLocation = Self.smartFrequentBackgroundSeedLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: userDefaults.object(forKey: smartFrequentBackgroundSeedAltitudeKey) as? Double ?? 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: userDefaults.object(forKey: smartFrequentBackgroundSeedVerticalAccuracyKey) as? Double ?? -1,
            course: userDefaults.object(forKey: smartFrequentBackgroundSeedCourseKey) as? Double ?? -1,
            speed: userDefaults.object(forKey: smartFrequentBackgroundSeedSpeedKey) as? Double ?? -1,
            timestamp: timestamp,
            now: now,
            inactivityWindow: inactivityWindow
        )
        if seedLocation == nil {
            clearPersistedSmartFrequentBackgroundSeed()
        }
        return seedLocation
    }

    private func persistSmartFrequentBackgroundSeed(with location: CLLocation) {
        guard location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(location.coordinate),
              location.timestamp.timeIntervalSince1970.isFinite,
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumSmartFrequentBackgroundStateAccuracy else {
            return
        }

        userDefaults.set(location.coordinate.latitude, forKey: smartFrequentBackgroundSeedLatitudeKey)
        userDefaults.set(location.coordinate.longitude, forKey: smartFrequentBackgroundSeedLongitudeKey)
        userDefaults.set(location.altitude.isFinite ? location.altitude : 0, forKey: smartFrequentBackgroundSeedAltitudeKey)
        userDefaults.set(location.horizontalAccuracy, forKey: smartFrequentBackgroundSeedHorizontalAccuracyKey)
        userDefaults.set(location.verticalAccuracy.isFinite ? location.verticalAccuracy : -1, forKey: smartFrequentBackgroundSeedVerticalAccuracyKey)
        userDefaults.set(location.course.isFinite ? location.course : -1, forKey: smartFrequentBackgroundSeedCourseKey)
        userDefaults.set(location.speed.isFinite ? location.speed : -1, forKey: smartFrequentBackgroundSeedSpeedKey)
        userDefaults.set(location.timestamp, forKey: smartFrequentBackgroundSeedTimestampKey)
    }

    private func clearPersistedSmartFrequentBackgroundSeed() {
        [
            smartFrequentBackgroundSeedLatitudeKey,
            smartFrequentBackgroundSeedLongitudeKey,
            smartFrequentBackgroundSeedAltitudeKey,
            smartFrequentBackgroundSeedHorizontalAccuracyKey,
            smartFrequentBackgroundSeedVerticalAccuracyKey,
            smartFrequentBackgroundSeedCourseKey,
            smartFrequentBackgroundSeedSpeedKey,
            smartFrequentBackgroundSeedTimestampKey
        ].forEach { userDefaults.removeObject(forKey: $0) }
    }

    private func updateSmartFrequentBackgroundSpeedReference(with location: CLLocation) {
        if isUsableForSmartFrequentBackgroundState(location) {
            smartFrequentBackgroundSpeedReferenceLocation = location
        }
    }

    private func isBatteryAtOrBelowFrequentBackgroundThreshold() -> Bool {
        guard let batteryPercent = Self.batteryPercent(from: UIDevice.current.batteryLevel) else {
            return false
        }
        return Self.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: batteryPercent,
            thresholdPercent: settings.frequentBackgroundBatteryAutoDisableLevel
        )
    }
    
    // MARK: - Server Communication
    @MainActor
    private func sendLocationToServer(_ location: CLLocation, enableHistoryOverride: Bool? = nil) async {
        if settings.isTrackingPaused {
            serverUpdateStatus = .idle
            diagnosticsLog.append(
                level: .info,
                event: "locationUpload",
                summary: "Skipped location upload because server updates are paused.",
                result: "paused",
                reason: "server update pause active",
                checks: trackingEligibilityChecks(status: locationManager.authorizationStatus),
                context: diagnosticsLocationContext(location, extra: [
                    ("trackingPauseExpiresAt", settings.trackingPauseExpiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("none"))
                ]),
                persistence: .immediate
            )
            return
        }
        if settings.deviceKeyAuthBlocked {
            self.serverUpdateStatus = .failed(
                NSLocalizedString("device_key_auth_mismatch_message", tableName: "Devices", comment: "Message when stored DeviceKey does not match server")
            )
            diagnosticsLog.append(
                level: .error,
                event: "locationUpload",
                summary: "Skipped location upload.",
                result: "blocked",
                reason: "DeviceKey auth blocked",
                checks: [
                    LocationDiagnosticsLogStore.check("deviceKeyNotBlocked", false, detail: "DeviceKey auth is blocked.")
                ],
                context: LocationDiagnosticsLogStore.roundedLocationContext(location),
                persistence: .immediate
            )
            return
        }
        guard !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            self.serverUpdateStatus = .failed("Invalid server configuration")
            diagnosticsLog.append(
                level: .error,
                event: "locationUpload",
                summary: "Skipped location upload.",
                result: "failed",
                reason: "invalid server configuration",
                checks: [],
                context: LocationDiagnosticsLogStore.roundedLocationContext(location),
                persistence: .immediate
            )
            return
        }
        let applicationState = UIApplication.shared.applicationState
        let deliveryDelay = frequentBackgroundLocationDeliveryDelay(for: applicationState)
        let processKnownVisitorAlerts = frequentBackgroundVisitorChecksEnabled(for: applicationState)
        let visitorCheckMinimumInterval = frequentBackgroundVisitorCheckMinimumInterval(for: applicationState)
        self.serverUpdateStatus = .updating

        let submission = await locationUpdateUploadService.submit(
            location: location,
            serverURL: serverURL,
            deviceID: thisDeviceIDManager.shared.deviceID,
            deviceKey: settings.deviceKey,
            enableHistory: enableHistoryOverride ?? settings.saveLocationHistoryOnServer,
            retentionTime: settings.locationDataRetentionTime,
            deliveryDelay: deliveryDelay,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval,
            processKnownVisitorAlerts: processKnownVisitorAlerts,
            applicationState: applicationState,
            batteryLevel: UIDevice.current.batteryLevel
        )

        let result: LocationUpdateDeliveryCoordinator.SubmitResult
        switch submission {
        case .invalidPayload:
            debugLog("[LocationManager] Skipping server update due to invalid location values")
            self.serverUpdateStatus = .failed("Invalid location values")
            diagnosticsLog.append(
                level: .error,
                event: "locationUpload",
                summary: "Skipped location upload.",
                result: "failed",
                reason: "invalid location values",
                checks: [],
                context: LocationDiagnosticsLogStore.roundedLocationContext(location),
                persistence: .immediate
            )
            return
        case .delivery(let deliveryResult):
            result = deliveryResult
        }

        switch result {
        case .sent:
            recordForensicUpload(applicationState: applicationState)
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationUpload",
                summary: "Location update sent to server.",
                result: "sent",
                reason: nil,
                coalescingKey: "locationUpload|sent|\(applicationState.rawValue)",
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
            )
            Task {
                await UnknownVisitorAlertService.shared.processAfterSuccessfulLocationUpdate(
                    serverURL: serverURL,
                    minimumInterval: visitorCheckMinimumInterval,
                    processKnownVisitorAlerts: processKnownVisitorAlerts
                )
            }
        case .queued:
            debugLog("[LocationManager] updateLocation queued for retry/outbox delivery")
            self.serverUpdateStatus = .idle
            self.refreshPendingLocationUpdateCount()
            diagnosticsLog.appendCoalesced(
                level: .warning,
                event: "locationUpload",
                summary: "Location update queued for retry/outbox delivery.",
                result: "queued",
                reason: nil,
                coalescingKey: "locationUpload|queued|\(applicationState.rawValue)",
                context: LocationDiagnosticsLogStore.roundedLocationContext(location),
                sampleEvery: 100
            )
        case .dropped:
            debugLog("[LocationManager] updateLocation dropped because server updates are paused")
            self.serverUpdateStatus = .idle
            self.refreshPendingLocationUpdateCount()
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationUpload",
                summary: "Dropped location update because server updates are paused.",
                result: "paused",
                reason: "server update pause active",
                coalescingKey: "locationUpload|paused|\(applicationState.rawValue)",
                context: diagnosticsLocationContext(location, extra: [
                    ("trackingPauseExpiresAt", settings.trackingPauseExpiresAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .string("none"))
                ]),
                sampleEvery: 100
            )
        case .failed(let error):
            if let authMessage = DeviceKeyAuthHandler.handle(error: error) {
                settings.deviceKeyAuthBlocked = true
                settings.deviceKeyAuthBlockedKey = settings.deviceKey
                self.stopTracking()
                self.serverUpdateStatus = .failed(authMessage)
            } else {
                self.serverUpdateStatus = .failed(error.localizedDescription)
            }
            diagnosticsLog.append(
                level: .error,
                event: "locationUpload",
                summary: "Location upload failed.",
                result: "failed",
                reason: error.localizedDescription,
                checks: [],
                context: diagnosticsLocationContext(location, extra: [
                    ("apiErrorCategory", .string(Self.apiErrorDiagnosticCategory(error))),
                    ("retryable", .bool(MiataruRetryClassifier.isRetryable(error)))
                ]),
                persistence: .immediate
            )
        }
    }

    private func scheduleStartupHeartbeatIfNeeded() {
        guard !didScheduleStartupHeartbeat else { return }
        didScheduleStartupHeartbeat = true

        let heartbeatTimestamp = Date()
        guard Self.shouldSendStartupHeartbeat(
                reportingEnabled: settings.trackAndReportLocation,
                lastServerUpdate: lastServerUpdate,
                now: heartbeatTimestamp
              ),
              !settings.isTrackingPaused,
              let cachedLocation = DeviceLocationCacheStore.shared.getLocation(
                for: thisDeviceIDManager.shared.deviceID
              ),
              let heartbeatLocation = Self.startupHeartbeatLocation(
                from: cachedLocation,
                timestamp: heartbeatTimestamp
              ) else {
            return
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            await self.sendLocationToServer(heartbeatLocation, enableHistoryOverride: false)
        }
    }

    static func shouldSendStartupHeartbeat(
        reportingEnabled: Bool,
        lastServerUpdate: Date?,
        now: Date = Date(),
        minimumServerUpdateAge: TimeInterval = startupHeartbeatMinimumServerUpdateAge
    ) -> Bool {
        guard reportingEnabled else { return false }
        guard let lastServerUpdate else { return true }
        return now.timeIntervalSince(lastServerUpdate) >= max(0, minimumServerUpdateAge)
    }

    static func startupHeartbeatLocation(
        from cachedLocation: CachedDeviceLocation,
        timestamp: Date = Date()
    ) -> CLLocation? {
        let coordinate = CLLocationCoordinate2D(
            latitude: cachedLocation.latitude,
            longitude: cachedLocation.longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate),
              cachedLocation.accuracy.isFinite,
              cachedLocation.accuracy >= 0,
              timestamp.timeIntervalSince1970.isFinite else {
            return nil
        }

        let altitude = cachedLocation.altitude.flatMap { $0.isFinite ? $0 : nil }
        let speed = cachedLocation.speed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return CLLocation(
            coordinate: coordinate,
            altitude: altitude ?? 0,
            horizontalAccuracy: cachedLocation.accuracy,
            verticalAccuracy: altitude == nil ? -1 : 0,
            course: -1,
            speed: speed ?? -1,
            timestamp: timestamp
        )
    }

    static func apiErrorDiagnosticCategory(_ error: Error) -> String {
        LocationUpdateUploadService.apiErrorDiagnosticCategory(error)
    }

    private func frequentBackgroundLocationDeliveryDelay(for applicationState: UIApplication.State) -> TimeInterval? {
        Self.frequentBackgroundLocationDeliveryDelay(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            deliveryMode: settings.frequentBackgroundLocationDeliveryModeSelection
        )
    }

    private func frequentBackgroundVisitorCheckMinimumInterval(for applicationState: UIApplication.State) -> TimeInterval? {
        Self.frequentBackgroundVisitorCheckMinimumInterval(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            visitorCheckInterval: settings.frequentBackgroundVisitorCheckIntervalSelection
        )
    }

    private func frequentBackgroundVisitorChecksEnabled(for applicationState: UIApplication.State) -> Bool {
        Self.frequentBackgroundVisitorChecksEnabled(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled
        )
    }

    @MainActor
    private func markServerUpdateSucceeded() {
        self.serverUpdateStatus = .success
        let updateDate = Date()
        self.lastServerUpdate = updateDate
        self.userDefaults.set(updateDate, forKey: self.lastServerUpdateKey)
    }

    private func refreshPendingLocationUpdateCount() {
        Task {
            let pendingCount = await locationUpdateDeliveryCoordinator.pendingOutboxCount()
            await MainActor.run {
                self.pendingLocationUpdateCount = pendingCount
            }
        }
    }
    // MARK: - Logging
    private func locationUpdateLogModeText(for mode: LocationUpdateCounterMode) -> String {
        switch mode {
        case .foregroundLive:
            return NSLocalizedString("lm_foreground_status", tableName: "LocationTracking", comment: "shown in the Location Status overview for foreground updates")
        case .significantChange:
            return NSLocalizedString("location_update_mode_significant_change", tableName: "LocationTracking", comment: "Location update log mode for significant-change updates")
        case .smartFrequent:
            return NSLocalizedString("location_update_mode_smart_frequent", tableName: "LocationTracking", comment: "Location update log mode for smart frequent updates")
        case .manualFrequent:
            return NSLocalizedString("location_update_mode_manual_frequent", tableName: "LocationTracking", comment: "Location update log mode for manually enabled frequent updates")
        }
    }

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
                self.coreLocationServices.requestPrimaryLocation()
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
        applyTrackingMode(reason: "start background tracking", applicationStateContext: .forceBackground)
    }
    
    func stopBackgroundTracking() {
        applyTrackingMode(reason: "stop background tracking")
    }
    
    // MARK: - App Delegate Extension
    func applicationDidEnterBackground(_ application: UIApplication) {
        startBackgroundTracking()
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        appDidEnterForeground()
    }
    
    // MARK: - App Lifecycle Hooks
    func appDidEnterForeground() {
        debugLog("[LocationManager] App did enter foreground")
        smartFrequentBackgroundStartupGuardPending = false
        recordForensicForegroundOpen(trigger: "app did enter foreground")
        // Check daily reset on foreground entry so UI reflects a new day immediately
        maybeResetBackgroundMetricsIfNeeded()
        reconcileTrackingState(
            reason: "app did enter foreground",
            applicationStateContext: .forceForeground,
            refreshExternalSettings: true
        )
        recordLocationTrackingHealthReminderActivity(reason: "app did enter foreground")
    }

    func appDidEnterBackground() {
        debugLog("[LocationManager] App did enter background")
        reconcileTrackingState(reason: "app did enter background", applicationStateContext: .forceBackground)
    }

    private func stopAllLocationServices() {
        debugLog("[LocationManager] Stopping all location services")
        recordForensicServiceAssertion(mode: .stopped)
        coreLocationServices.stopManagedLocationUpdates()
        stopSmartFrequentExitFence(reason: "stop all location services")
        resetSmartFrequentBackgroundRuntime()
        coreLocationServices.stopLocationServiceSession(reason: "stop all location services")
        coreLocationServices.stopFrequentBackgroundActivitySession(reason: "stop all location services")
        stopHeadingUpdates()
        stopForegroundLocationTimer()
    }

    private func locationUpdateSource(for manager: CLLocationManager) -> LocationUpdateSource {
        if manager === locationManager {
            return .primary
        }
        if manager === frequentBackgroundLocationManager {
            return .frequentBackground
        }
        return .unknown
    }

    private func startHeadingUpdatesIfAvailable() {
        guard CLLocationManager.headingAvailable() else {
            isHeadingValid = false
            userHeading = nil
            return
        }
        coreLocationServices.startHeadingUpdatesIfAvailable()
    }

    private func stopHeadingUpdates() {
        coreLocationServices.stopHeadingUpdates()
        isHeadingValid = false
        userHeading = nil
        headingSmoother.reset()
    }
    
    private func mappedSensitivityValues(for level: Int) -> (distance: CLLocationDistance, accuracy: CLLocationAccuracy) {
        LocationSamplePolicy.sensitivityValues(for: level)
    }

    // MARK: - 24h diagnostics reset
    private func maybeResetBackgroundMetricsIfNeeded(now: Date = Date()) {
        if let snapshot = locationUpdateMetricsStore.resetIfNeeded(now: now) {
            applyLocationUpdateMetricsSnapshot(snapshot)
        }
    }

    private func recordLocationUpdateMetric(mode: LocationUpdateCounterMode, now: Date = Date()) {
        applyLocationUpdateMetricsSnapshot(locationUpdateMetricsStore.record(mode: mode, now: now))
    }

    private func applyLocationUpdateMetricsSnapshot(_ snapshot: LocationUpdateMetricsSnapshot) {
        backgroundUpdateCount = snapshot.backgroundUpdateCount
        locationUpdateModeCounts = snapshot.modeCounts
        lastBackgroundUpdate = snapshot.lastBackgroundUpdate
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let orderedLocations = Self.processableLocationUpdates(from: locations)
            guard !orderedLocations.isEmpty else {
                debugLog("[LocationManager] didUpdateLocations ignored empty/invalid batch count=\(locations.count)")
                self.diagnosticsLog.append(
                    level: .warning,
                    event: "locationCallback",
                    summary: "Ignored CoreLocation location batch.",
                    result: "ignored",
                    reason: "empty or invalid batch",
                    checks: [
                        LocationDiagnosticsLogStore.check(
                            "hasProcessableLocations",
                            false,
                            detail: "processable=0, raw=\(locations.count)."
                        )
                    ],
                    context: ["rawCount": .integer(locations.count)]
                )
                return
            }

            let applicationState = UIApplication.shared.applicationState
            let updateSource = self.locationUpdateSource(for: manager)
            let isSmartFrequentStartupBatch = self.smartFrequentBackgroundStartupGuardPending &&
            applicationState != .active &&
            updateSource == .primary
            self.recordForensicLocationCallback(applicationState: applicationState, source: updateSource)
            debugLog("[LocationManager] didUpdateLocations source=\(updateSource.rawValue), count=\(locations.count), processable=\(orderedLocations.count), state=\(applicationState.rawValue), manualFrequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), smartEnabled=\(settings.smartFrequentBackgroundLocationUpdatesEnabled), smartRuntimeActive=\(smartFrequentBackgroundRuntimeActive)")
            let callbackContext: [String: LocationDiagnosticsValue] = [
                "source": .string(updateSource.rawValue),
                "rawCount": .integer(locations.count),
                "processableCount": .integer(orderedLocations.count),
                "applicationState": .integer(applicationState.rawValue),
                "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled),
                "smartRuntimeActive": .bool(smartFrequentBackgroundRuntimeActive),
                "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue),
                "smartStartupGuardActive": .bool(isSmartFrequentStartupBatch)
            ]
            self.diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationCallback",
                summary: "Received CoreLocation location batch.",
                result: orderedLocations.isEmpty ? "ignored" : "processing",
                coalescingKey: "locationCallback|\(applicationState.rawValue)|\(updateSource.rawValue)|manual:\(settings.frequentBackgroundLocationUpdatesEnabled)|smart:\(settings.smartFrequentBackgroundLocationUpdatesEnabled)|runtime:\(smartFrequentBackgroundRuntimeActive)",
                context: callbackContext
            )
            _ = self.handleTrackingPauseExpirationIfNeeded()
            let didExpireFrequentBackgroundUpdates = self.handleFrequentBackgroundLocationExpirationIfNeeded()
            let didDisableFrequentBackgroundUpdatesForBattery = self.disableFrequentBackgroundLocationUpdatesIfBatteryIsLow()
            var didSwitchFrequentBackgroundMode = didExpireFrequentBackgroundUpdates || didDisableFrequentBackgroundUpdatesForBattery
            var didCleanUpStaleFrequentCallback = false
            var shouldSuppressCallback = false
            var locationsPendingUpload: [CLLocation] = []

            for location in orderedLocations {
                let sampleProcessingNow = Date()
                guard self.shouldProcessLocationSample(
                    location,
                    now: sampleProcessingNow,
                    applicationState: applicationState,
                    updateSource: updateSource
                ) else {
                    continue
                }
                self.recordSmartFrequentBackgroundFrequentCallbackIfNeeded(
                    updateSource: updateSource,
                    now: sampleProcessingNow
                )
                self.handleFrequentBackgroundAccuracyRecovery(
                    for: location,
                    updateSource: updateSource,
                    applicationState: applicationState,
                    now: sampleProcessingNow
                )

                let didSwitchSmartFrequentBackgroundMode = self.updateSmartFrequentBackgroundRuntime(
                    for: location,
                    updateSource: updateSource,
                    applicationState: applicationState,
                    isStartupBatch: isSmartFrequentStartupBatch,
                    now: sampleProcessingNow
                )
                didSwitchFrequentBackgroundMode = didSwitchFrequentBackgroundMode || didSwitchSmartFrequentBackgroundMode

                let cleanupResult = self.cleanUpStaleFrequentBackgroundCallbackIfNeeded(
                    updateSource: updateSource,
                    didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
                )
                didCleanUpStaleFrequentCallback = didCleanUpStaleFrequentCallback || cleanupResult.didCleanUp
                if cleanupResult.shouldSuppressCallback {
                    shouldSuppressCallback = true
                    break
                }

                self.latestRawLocation = location
                self.persistSmartFrequentBackgroundSeed(with: location)

                let updateCounterMode = Self.locationUpdateCounterMode(
                    applicationState: applicationState,
                    manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
                    smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
                    smartRuntimeActive: smartFrequentBackgroundRuntimeActive,
                    trackingPaused: settings.isTrackingPaused
                )
                self.recordLocationUpdateMetric(mode: updateCounterMode)
                self.updateCourseHeadingFallbackIfNeeded(from: location)

                guard self.shouldAcceptLocationUpdate(location, applicationState: applicationState, updateSource: updateSource) else {
                    continue
                }

                let mode = self.locationUpdateLogModeText(for: updateCounterMode)
                self.acceptLocationUpdate(location, mode: mode, locationsPendingUpload: &locationsPendingUpload)
                self.confirmSmartFrequentBackgroundRuntimeIfNeeded(
                    location: location,
                    updateSource: updateSource,
                    applicationState: applicationState
                )
            }

            if didCleanUpStaleFrequentCallback, isTracking, applicationState != .active {
                self.applyTrackingMode(reason: "stale frequent background callback cleanup", applicationStateContext: .forceBackground)
            } else if didSwitchFrequentBackgroundMode, applicationState != .active {
                self.applyTrackingMode(reason: Self.frequentBackgroundModeSwitchReason(
                    didExpire: didExpireFrequentBackgroundUpdates,
                    didDisableForBattery: didDisableFrequentBackgroundUpdatesForBattery
                ))
            } else {
                self.reassertStandardSignificantChangeAfterPrimaryCallbackIfNeeded(
                    applicationState: applicationState,
                    updateSource: updateSource,
                    didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
                )
                self.reassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeIfNeeded(
                    applicationState: applicationState,
                    updateSource: updateSource,
                    didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
                )
            }
            if isSmartFrequentStartupBatch {
                self.smartFrequentBackgroundStartupGuardPending = false
            }
            self.reconcileSmartFrequentExitFence(reason: "location update")

            guard !shouldSuppressCallback,
                  !locationsPendingUpload.isEmpty else {
                return
            }

            let uploadLocations = locationsPendingUpload
            for location in uploadLocations {
                Task { @MainActor in
                    await self.sendLocationToServer(location)
                }
            }
        }
    }

    private func shouldAcceptLocationUpdate(_ location: CLLocation,
                                            applicationState: UIApplication.State,
                                            updateSource: LocationUpdateSource) -> Bool {
        let (minimumDistance, significantAccuracyImprovement) = mappedSensitivityValues(for: settings.locationSensitivityLevel)
        guard Self.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: applicationState,
            updateSourceIsFrequentBackground: updateSource == .frequentBackground,
            horizontalAccuracy: location.horizontalAccuracy,
            distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter
        ) else {
            let maximumAccuracy = Self.maximumAcceptedFrequentBackgroundAccuracy(
                distanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter
            )
            debugLog("[LocationManager] Location update ignored: frequent background accuracy \(location.horizontalAccuracy)m exceeds maximum \(maximumAccuracy)m")
            diagnosticsLog.appendCoalesced(
                level: .warning,
                event: "locationAcceptance",
                summary: "Ignored frequent background location update.",
                result: "rejected",
                reason: "frequent background accuracy threshold not met",
                coalescingKey: "locationAcceptance|rejected|accuracyQuality|\(applicationState.rawValue)|\(updateSource.rawValue)",
                context: diagnosticsLocationContext(location, extra: [
                    ("maximumAccuracyMeters", .double(maximumAccuracy)),
                    ("distanceFilterMeters", .integer(settings.frequentBackgroundLocationDistanceFilter)),
                    ("accuracyRecoveryActive", .bool(frequentBackgroundAccuracyRecoveryActive)),
                    ("poorAccuracyStreak", .integer(frequentBackgroundPoorAccuracyStreak)),
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                ])
            )
            return false
        }

        var confirmedPendingLargeJump: PendingLargeJumpLocation?
        if let pendingLargeJumpLocation {
            if LocationSamplePolicy.confirmsLargeJump(
                candidate: location,
                pendingCandidate: pendingLargeJumpLocation.candidate
            ) {
                confirmedPendingLargeJump = pendingLargeJumpLocation
            } else if LocationSamplePolicy.returnsToPreviousAcceptedLocation(
                candidate: location,
                previousAcceptedLocation: pendingLargeJumpLocation.previousAcceptedLocation
            ) {
                debugLog("[LocationManager] Deferred large-jump location discarded after return near previous accepted location.")
                diagnosticsLog.appendCoalesced(
                    level: .warning,
                    event: "locationAcceptance",
                    summary: "Discarded deferred large-jump location update.",
                    result: "rejected",
                    reason: "large jump discarded",
                    coalescingKey: "locationAcceptance|rejected|largeJumpDiscarded|\(applicationState.rawValue)|\(updateSource.rawValue)",
                    context: diagnosticsLocationContext(location, acceptanceMetrics: pendingLargeJumpLocation.metrics, extra: [
                        ("pendingCandidateAgeSeconds", .double(location.timestamp.timeIntervalSince(pendingLargeJumpLocation.candidate.timestamp))),
                        ("pendingCandidateReplaced", .bool(false)),
                        ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                    ])
                )
                self.pendingLargeJumpLocation = nil
            }
        }

        let acceptanceDecision = LocationSamplePolicy.acceptanceDecision(
            for: location,
            previousAcceptedLocation: currentLocation
        )
        switch acceptanceDecision {
        case .accept(let metrics):
            if let confirmedPendingLargeJump {
                pendingLargeJumpLocation = nil
                debugLog("[LocationManager] Deferred large-jump location confirmed.")
                diagnosticsLog.appendCoalesced(
                    level: .info,
                    event: "locationAcceptance",
                    summary: "Confirmed deferred large-jump location update.",
                    result: "accepted",
                    reason: "large jump confirmed",
                    coalescingKey: "locationAcceptance|accepted|largeJumpConfirmed|\(applicationState.rawValue)|\(updateSource.rawValue)",
                    context: diagnosticsLocationContext(location, acceptanceMetrics: metrics, extra: [
                        ("pendingCandidateAgeSeconds", .double(location.timestamp.timeIntervalSince(confirmedPendingLargeJump.candidate.timestamp))),
                        ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                    ])
                )
            }
        case .reject(let reason, let metrics):
            debugLog("[LocationManager] Location update ignored: \(reason.rawValue)")
            diagnosticsLog.appendCoalesced(
                level: .warning,
                event: "locationAcceptance",
                summary: "Ignored implausible location update.",
                result: "rejected",
                reason: reason.rawValue,
                coalescingKey: "locationAcceptance|rejected|plausibility|\(reason.rawValue)|\(applicationState.rawValue)|\(updateSource.rawValue)",
                context: diagnosticsLocationContext(location, acceptanceMetrics: metrics, extra: [
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                ])
            )
            return false
        case .deferForConfirmation(let metrics):
            if let confirmedPendingLargeJump {
                pendingLargeJumpLocation = nil
                debugLog("[LocationManager] Deferred large-jump location confirmed.")
                diagnosticsLog.appendCoalesced(
                    level: .info,
                    event: "locationAcceptance",
                    summary: "Confirmed deferred large-jump location update.",
                    result: "accepted",
                    reason: "large jump confirmed",
                    coalescingKey: "locationAcceptance|accepted|largeJumpConfirmed|\(applicationState.rawValue)|\(updateSource.rawValue)",
                    context: diagnosticsLocationContext(location, acceptanceMetrics: metrics, extra: [
                        ("pendingCandidateAgeSeconds", .double(location.timestamp.timeIntervalSince(confirmedPendingLargeJump.candidate.timestamp))),
                        ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                    ])
                )
            } else if let previousLocation = currentLocation {
                let replacedPendingLargeJump = pendingLargeJumpLocation != nil
                pendingLargeJumpLocation = PendingLargeJumpLocation(
                    candidate: location,
                    previousAcceptedLocation: previousLocation,
                    metrics: metrics
                )
                debugLog("[LocationManager] Location update deferred: large jump awaiting confirmation.")
                diagnosticsLog.appendCoalesced(
                    level: .warning,
                    event: "locationAcceptance",
                    summary: "Deferred large-jump location update.",
                    result: "deferred",
                    reason: "large jump awaiting confirmation",
                    coalescingKey: "locationAcceptance|deferred|largeJumpAwaitingConfirmation|\(applicationState.rawValue)|\(updateSource.rawValue)",
                    context: diagnosticsLocationContext(location, acceptanceMetrics: metrics, extra: [
                        ("pendingCandidateReplaced", .bool(replacedPendingLargeJump)),
                        ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                    ])
                )
                return false
            }
        }

        let shouldBypassSensitivityForFrequentUpload = Self.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: applicationState,
            updateSourceIsFrequentBackground: updateSource == .frequentBackground,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartRuntimePhase: smartFrequentBackgroundRuntimePhase
        )
        guard let previousLocation = self.currentLocation else {
            debugLog("[LocationManager] First location update accepted.")
            pendingLargeJumpLocation = nil
            recordForensicAcceptedLocation(applicationState: applicationState, source: updateSource)
            diagnosticsLog.append(
                level: .info,
                event: "locationAcceptance",
                summary: "Accepted first location update.",
                result: "accepted",
                reason: "first location update",
                checks: [
                    LocationDiagnosticsLogStore.check("hasPreviousLocation", false, detail: "No previous accepted location exists.")
                ],
                context: diagnosticsLocationContext(location, extra: [
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                ])
            )
            return true
        }

        let distance = location.distance(from: previousLocation)
        let accuracyImprovement = previousLocation.horizontalAccuracy - location.horizontalAccuracy
        if distance >= minimumDistance {
            debugLog("[LocationManager] Location update accepted: distance (\(distance)m) >= minimum (\(minimumDistance)m)")
            pendingLargeJumpLocation = nil
            recordForensicAcceptedLocation(applicationState: applicationState, source: updateSource)
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationAcceptance",
                summary: "Accepted location update.",
                result: "accepted",
                reason: "distance threshold met",
                coalescingKey: "locationAcceptance|accepted|distance|\(applicationState.rawValue)|\(updateSource.rawValue)",
                context: diagnosticsLocationContext(location, extra: [
                    ("distanceMeters", .double(distance)),
                    ("minimumDistanceMeters", .double(minimumDistance)),
                    ("accuracyImprovementMeters", .double(accuracyImprovement)),
                    ("minimumAccuracyImprovementMeters", .double(significantAccuracyImprovement)),
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                ])
            )
            return true
        }
        if accuracyImprovement >= significantAccuracyImprovement {
            debugLog("[LocationManager] Location update accepted: accuracy improved by (\(accuracyImprovement)m) >= minimum (\(significantAccuracyImprovement)m)")
            pendingLargeJumpLocation = nil
            recordForensicAcceptedLocation(applicationState: applicationState, source: updateSource)
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationAcceptance",
                summary: "Accepted location update.",
                result: "accepted",
                reason: "accuracy improvement threshold met",
                coalescingKey: "locationAcceptance|accepted|accuracy|\(applicationState.rawValue)|\(updateSource.rawValue)",
                context: diagnosticsLocationContext(location, extra: [
                    ("distanceMeters", .double(distance)),
                    ("minimumDistanceMeters", .double(minimumDistance)),
                    ("accuracyImprovementMeters", .double(accuracyImprovement)),
                    ("minimumAccuracyImprovementMeters", .double(significantAccuracyImprovement)),
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
                ])
            )
            return true
        }
        if shouldBypassSensitivityForFrequentUpload {
            debugLog("[LocationManager] Location update accepted: preserving frequent background upload despite sensitivity thresholds")
            pendingLargeJumpLocation = nil
            recordForensicAcceptedLocation(applicationState: applicationState, source: updateSource)
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationAcceptance",
                summary: "Accepted frequent background location update.",
                result: "accepted",
                reason: "frequent background upload preservation",
                coalescingKey: "locationAcceptance|accepted|frequentBackgroundPreserved|\(applicationState.rawValue)|\(updateSource.rawValue)|manual:\(settings.frequentBackgroundLocationUpdatesEnabled)|smartPhase:\(smartFrequentBackgroundRuntimePhase.rawValue)",
                context: diagnosticsLocationContext(location, extra: [
                    ("distanceMeters", .double(distance)),
                    ("minimumDistanceMeters", .double(minimumDistance)),
                    ("accuracyImprovementMeters", .double(accuracyImprovement)),
                    ("minimumAccuracyImprovementMeters", .double(significantAccuracyImprovement)),
                    ("sensitivityLevel", .integer(settings.locationSensitivityLevel)),
                    ("manualFrequentEnabled", .bool(settings.frequentBackgroundLocationUpdatesEnabled)),
                    ("smartRuntimePhase", .string(smartFrequentBackgroundRuntimePhase.rawValue))
                ])
            )
            return true
        }

        debugLog("[LocationManager] Location update ignored: distance (\(distance)m), accuracy improvement (\(accuracyImprovement)m)")
        diagnosticsLog.appendCoalesced(
            level: .info,
            event: "locationAcceptance",
            summary: "Ignored location update.",
            result: "rejected",
            reason: "distance and accuracy thresholds not met",
            coalescingKey: "locationAcceptance|rejected|thresholds|\(applicationState.rawValue)|\(updateSource.rawValue)",
            context: diagnosticsLocationContext(location, extra: [
                ("distanceMeters", .double(distance)),
                ("minimumDistanceMeters", .double(minimumDistance)),
                ("accuracyImprovementMeters", .double(accuracyImprovement)),
                ("minimumAccuracyImprovementMeters", .double(significantAccuracyImprovement)),
                ("sensitivityLevel", .integer(settings.locationSensitivityLevel))
            ])
        )
        return false
    }

    private func updateCourseHeadingFallbackIfNeeded(from location: CLLocation) {
        if (userHeading == nil || !isHeadingValid),
           location.course >= 0,
           location.speed >= HeadingSmoother.defaultMinimumCourseSpeed {
            userHeading = headingSmoother.smooth(location.course)
        }
    }

    private func acceptLocationUpdate(_ location: CLLocation,
                                      mode: String,
                                      locationsPendingUpload: inout [CLLocation]) {
        self.currentLocation = location
        self.lastUpdateTime = Date()
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

        if Self.shouldSubmitLocationForUpload(location, lastSubmittedKey: self.lastSubmittedLocationDeduplicationKey) {
            self.lastSubmittedLocationDeduplicationKey = Self.locationSubmissionDeduplicationKey(for: location)
            locationsPendingUpload.append(location)
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationUploadDecision",
                summary: "Location update queued for upload submission.",
                result: "eligible",
                reason: "deduplication key is new",
                coalescingKey: "locationUploadDecision|eligible",
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
            )
        } else {
            debugLog("[LocationManager] Skipping duplicate location upload from parallel location services")
            diagnosticsLog.appendCoalesced(
                level: .info,
                event: "locationUploadDecision",
                summary: "Skipped duplicate location upload.",
                result: "duplicate",
                reason: "parallel location services delivered the same location",
                coalescingKey: "locationUploadDecision|duplicate",
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
            )
        }
        self.addUpdateLogEntry(mode: mode)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            let accuracy = newHeading.headingAccuracy
            guard accuracy >= 0 else {
                isHeadingValid = false
                return
            }
            isHeadingValid = accuracy <= HeadingSmoother.defaultAccuracyThreshold
            let headingReferenceLocation = latestRawLocation ?? currentLocation
            if isHeadingValid {
                let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
                let blended = headingSmoother.blended(
                    compass: rawHeading,
                    course: headingReferenceLocation?.course,
                    speed: headingReferenceLocation?.speed
                )
                userHeading = headingSmoother.smooth(blended)
            } else if let course = headingReferenceLocation?.course,
                      let speed = headingReferenceLocation?.speed,
                      course >= 0,
                      speed >= HeadingSmoother.defaultMinimumCourseSpeed {
                // Fallback to smoothed course when compass quality is poor.
                userHeading = headingSmoother.smooth(course)
            }
        }
    }
    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationChange(status)
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .notDetermined, .denied, .restricted:
                self.pendingAlwaysAuthorizationRequestTask?.cancel()
                self.pendingAlwaysAuthorizationRequestTask = nil
                self.didAttemptAlwaysAuthorizationInCurrentSession = false
            case .authorizedAlways:
                self.pendingAlwaysAuthorizationRequestTask?.cancel()
                self.pendingAlwaysAuthorizationRequestTask = nil
            case .authorizedWhenInUse:
                break
            @unknown default:
                break
            }

            if Self.shouldPreserveEnabledTrackingPreferenceForUITests,
               self.settings.trackAndReportLocation {
                self.isTracking = true
                return
            }
            if status == .authorizedWhenInUse,
               settings.trackAndReportLocation {
                self.requestAlwaysAuthorizationIfPossible(reason: "authorization changed")
            }
            self.reconcileTrackingState(reason: "authorization changed")
            self.diagnosticsLog.append(
                level: status == .authorizedAlways ? .info : .warning,
                event: "authorizationChange",
                summary: "Location authorization changed.",
                result: "\(status.rawValue)",
                reason: nil,
                checks: self.trackingEligibilityChecks(status: status),
                context: ["authorizationStatus": .integer(Int(status.rawValue))]
            )
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.serverUpdateStatus = .failed(error.localizedDescription)
            self.diagnosticsLog.append(
                level: .error,
                event: "locationManagerError",
                summary: "CoreLocation reported an error.",
                result: "failed",
                reason: error.localizedDescription,
                checks: [],
                context: ["source": .string(self.locationUpdateSource(for: manager).rawValue)]
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            self.handleSmartFrequentExitFenceExit(region: region)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Task { @MainActor in
            guard region?.identifier == Self.smartFrequentExitFenceIdentifier else {
                return
            }
            self.isSmartFrequentExitFenceActive = false
            self.diagnosticsLog.append(
                level: .warning,
                event: "smartFrequentExitFence",
                summary: "Smart frequent exit-fence monitoring failed.",
                result: "failed",
                reason: error.localizedDescription
            )
        }
    }
} 

extension Notification.Name {
    static let didSendOwnLocationUpdate = Notification.Name("didSendOwnLocationUpdate")
} 
