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
    private let locationManager = CLLocationManager()
    private let frequentBackgroundLocationManager = CLLocationManager()
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
    private let significantChangeRearmedBuildIdentifierKey = "miataru_significantChangeRearmedBuildIdentifier"
    private let lastSignificantChangeRearmStatusKey = "miataru_lastSignificantChangeRearmStatus"
    private let backgroundTrackingForensicStateKey = "miataru_backgroundTrackingForensicState"
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared
    private let diagnosticsLog = LocationDiagnosticsLogStore.shared
    private let locationUpdateMetricsStore = LocationUpdateMetricsStore()
    private let locationUpdateUploadService = LocationUpdateUploadService()
    private var foregroundLocationTimer: Timer?
    private var frequentBackgroundLocationExpirationTimer: Timer?
    private var smartFrequentBackgroundInactivityTimer: Timer?
    private var foregroundLocationUpdateTimerTimeframe: Double = 30
    private let networkMonitor = NWPathMonitor()
    private let locationUpdateDeliveryCoordinator = LocationUpdateDeliveryCoordinator.shared
    @Published private(set) var isNetworkAvailable: Bool = true
    @Published private(set) var pendingLocationUpdateCount: Int = 0
    private var pendingAlwaysAuthorizationRequestTask: Task<Void, Never>?
    private var didAttemptAlwaysAuthorizationInCurrentSession = false
    private var isSignificantChangeRecoveryAnchorActive = false
    private var isFrequentBackgroundStandardUpdatesActive = false
    private var shouldAllowNextStaleFrequentBackgroundCallback = false
    private var locationServiceSession: CLServiceSession?
    private var frequentBackgroundActivitySession: CLBackgroundActivitySession?
    private var lastSubmittedLocationDeduplicationKey: LocationSubmissionDeduplicationKey?
    private var smartFrequentBackgroundSpeedReferenceLocation: CLLocation?
    private var smartFrequentBackgroundMovementAnchor: CLLocation?
    private var lastSmartFrequentBackgroundLocationUpdateAt: Date?
    private var smartFrequentBackgroundProbeStartedAt: Date?
    private var smartFrequentBackgroundLastFrequentCallbackAt: Date?
    private var smartFrequentBackgroundRecoveryAttemptCount = 0
    private var smartFrequentBackgroundWatchdogTimer: Timer?
    private var smartFrequentBackgroundActivationNotificationDelivered = false
    private var smartFrequentBackgroundLastMovementLocationKey: LocationSubmissionDeduplicationKey?
    private var smartFrequentBackgroundLastMovementDistanceMeters: CLLocationDistance?
    private var smartFrequentBackgroundLastMovementThresholdMeters: CLLocationDistance?
    private var smartFrequentBackgroundStartupGuardPending = true
    private var isSmartFrequentExitFenceActive = false
    private var headingSmoother = HeadingSmoother()
    static let smartFrequentExitFenceIdentifier = SmartFrequentBackgroundPolicy.exitFenceIdentifier
    static let defaultSmartFrequentExitFenceRadius: CLLocationDistance = SmartFrequentBackgroundPolicy.defaultExitFenceRadius
    static let minimumSmartFrequentDerivedSpeedElapsed: TimeInterval = SmartFrequentBackgroundPolicy.minimumDerivedSpeedElapsed
    static let maximumTrustedSmartFrequentSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy = SmartFrequentBackgroundPolicy.maximumTrustedSpeedAccuracyMetersPerSecond
    static let maximumLocationSampleFutureSkew: TimeInterval = LocationSamplePolicy.maximumFutureSkew
    static let maximumLocationSampleAge: TimeInterval = LocationSamplePolicy.maximumAge
    static let forensicFrequentBackgroundGapThreshold: TimeInterval = LocationBackgroundForensics.frequentBackgroundGapThreshold
    static let forensicForegroundRecoveryBurstWindow: TimeInterval = LocationBackgroundForensics.foregroundRecoveryBurstWindow
    static let smartFrequentBackgroundRuntimeWatchdogInterval: TimeInterval = SmartFrequentBackgroundPolicy.runtimeWatchdogInterval
    static let maximumSmartFrequentBackgroundRuntimeRecoveryAttempts = SmartFrequentBackgroundPolicy.maximumRuntimeRecoveryAttempts
    static let smartFrequentBackgroundProbeWatchdogInterval = smartFrequentBackgroundRuntimeWatchdogInterval
    static let maximumSmartFrequentBackgroundProbeRecoveryAttempts = maximumSmartFrequentBackgroundRuntimeRecoveryAttempts
    
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

    typealias LocationUpdateCounterMode = LocationUpdateMetricsStore.CounterMode
    typealias LocationUpdateModeCounts = LocationUpdateMetricsStore.ModeCounts
    typealias BackgroundTrackingForensicState = LocationBackgroundForensics.State
    typealias BackgroundTrackingGapKind = LocationBackgroundForensics.GapKind
    typealias BackgroundTrackingGapAssessment = LocationBackgroundForensics.GapAssessment
    typealias BackgroundTrackingDisplayMode = LocationTrackingPolicy.BackgroundTrackingDisplayMode
    typealias BackgroundUpdateConfiguration = LocationTrackingPolicy.BackgroundUpdateConfiguration
    typealias TrackingMode = LocationTrackingPolicy.TrackingMode
    typealias SmartFrequentRuntimePhase = SmartFrequentBackgroundPolicy.RuntimePhase
    typealias SmartFrequentActivationEvidenceKind = SmartFrequentBackgroundPolicy.ActivationEvidenceKind
    typealias LocationSampleProcessingDecision = LocationSamplePolicy.ProcessingDecision
    typealias SmartFrequentBackgroundWatchdogAction = SmartFrequentBackgroundPolicy.WatchdogAction
    typealias SmartFrequentActivationEvidence = SmartFrequentBackgroundPolicy.ActivationEvidence
    typealias TrackingApplicationStateContext = LocationTrackingPolicy.ApplicationStateContext
    typealias TrackingReconcileAction = LocationTrackingPolicy.ReconcileAction
    typealias PrimaryLocationServiceCommand = LocationTrackingPolicy.PrimaryLocationServiceCommand
    typealias SecondaryLocationServiceCommand = LocationTrackingPolicy.SecondaryLocationServiceCommand
    typealias LocationServiceCommandPlan = LocationTrackingPolicy.ServiceCommandPlan
    typealias SignificantChangeRearmDecision = LocationBackgroundForensics.SignificantChangeRearmDecision
    typealias LocationSubmissionDeduplicationKey = LocationSamplePolicy.SubmissionDeduplicationKey

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

    private var navigationLocationSessionIDs = Set<UUID>()
    
    // MARK: - Init
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.activityType = Self.activityTypeFrom(settings.locationActivityType)
        frequentBackgroundLocationManager.delegate = self
        frequentBackgroundLocationManager.allowsBackgroundLocationUpdates = true
        frequentBackgroundLocationManager.pausesLocationUpdatesAutomatically = false
        frequentBackgroundLocationManager.showsBackgroundLocationIndicator = false
        frequentBackgroundLocationManager.activityType = Self.activityTypeFrom(settings.locationActivityType)
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 1
        }
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
        scheduleFrequentBackgroundLocationExpirationTimer()
        refreshFrequentBackgroundTrackingReminder()
        // Ensure permission state is handled on startup
        ensureAuthorizationIfNeeded()
        applyLocationUpdateMetricsSnapshot(locationUpdateMetricsStore.load())
        // Load persisted lastServerUpdate
        if let savedDate = userDefaults.object(forKey: lastServerUpdateKey) as? Date {
            lastServerUpdate = savedDate
        }
        lastSignificantChangeRearmStatus = loadLastSignificantChangeRearmStatus()
        backgroundTrackingForensicState = loadBackgroundTrackingForensicState()
        restorePersistedSmartFrequentBackgroundSeedIfNeeded()
        // Perform initial daily reset check
        maybeResetBackgroundMetricsIfNeeded()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        frequentBackgroundLocationExpirationTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer?.invalidate()
        pendingAlwaysAuthorizationRequestTask?.cancel()
        stopLocationServiceSession(reason: "deinit")
        stopFrequentBackgroundActivitySession(reason: "deinit")
    }
    
    @objc private func appDidBecomeActive() {
        debugLog("App did become active")
        smartFrequentBackgroundStartupGuardPending = false
        recordForensicForegroundOpen(trigger: "app did become active")
        reconcileTrackingState(
            reason: "app did become active",
            applicationStateContext: .forceForeground,
            refreshExternalSettings: true
        )
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
                self.refreshFrequentBackgroundTrackingReminder()
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
        .receive(on: DispatchQueue.main)
        .sink { [weak self] smartEnabled, _, _, _ in
            guard let self else { return }
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
        await locationUpdateDeliveryCoordinator.sendPendingOutbox(to: serverURL)
        refreshPendingLocationUpdateCount()
    }

    func flushPendingLocationUpdatesNow() async {
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
                self.locationManager.activityType = activityType
                self.frequentBackgroundLocationManager.activityType = activityType
                if self.isTracking {
                    // Restart location updates to apply new activityType immediately
                    self.applyTrackingMode(reason: "activity type changed")
                }
            }
            .store(in: &cancellables)
    }
    
    private static func activityTypeFrom(_ value: Int) -> CLActivityType {
        LocationTrackingPolicy.activityType(from: value)
    }

    static func backgroundUpdateConfiguration(frequentUpdatesEnabled: Bool,
                                              distanceFilterMeters: Int) -> BackgroundUpdateConfiguration {
        LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            distanceFilterMeters: distanceFilterMeters
        )
    }

    static func effectiveFrequentBackgroundUpdatesEnabled(manualFrequentEnabled: Bool,
                                                          smartEnabled: Bool,
                                                          smartRuntimeActive: Bool) -> Bool {
        LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: manualFrequentEnabled,
            smartEnabled: smartEnabled,
            smartRuntimeActive: smartRuntimeActive
        )
    }

    static func shouldShowBackgroundLocationIndicator(for mode: TrackingMode) -> Bool {
        LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: mode)
    }

    static func locationUpdateCounterMode(applicationState: UIApplication.State,
                                          manualFrequentEnabled: Bool,
                                          smartEnabled: Bool,
                                          smartRuntimeActive: Bool) -> LocationUpdateCounterMode {
        LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: applicationState,
            manualFrequentEnabled: manualFrequentEnabled,
            smartEnabled: smartEnabled,
            smartRuntimeActive: smartRuntimeActive
        )
    }

    static func backgroundTrackingDisplayMode(applicationState: UIApplication.State,
                                              smartEnabled: Bool,
                                              manualFrequentEnabled: Bool,
                                              smartRuntimeActive: Bool) -> BackgroundTrackingDisplayMode {
        LocationTrackingPolicy.backgroundTrackingDisplayMode(
            applicationState: applicationState,
            smartEnabled: smartEnabled,
            manualFrequentEnabled: manualFrequentEnabled,
            smartRuntimeActive: smartRuntimeActive
        )
    }

    static func shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.State) -> Bool {
        LocationTrackingPolicy.shouldEvaluateSmartFrequentRuntime(applicationState: applicationState)
    }

    static func shouldResetLocationUpdateMetrics(now: Date,
                                                 lastReset: Date?,
                                                 interval: TimeInterval = 24 * 60 * 60) -> Bool {
        LocationUpdateMetricsStore.shouldReset(now: now, lastReset: lastReset, interval: interval)
    }

    static func resolvedTrackingMode(isTracking: Bool,
                                     authorizationStatus: CLAuthorizationStatus,
                                     applicationState: UIApplication.State,
                                     frequentUpdatesEnabled: Bool,
                                     distanceFilterMeters: Int,
                                     hasNavigationLocationSession: Bool) -> TrackingMode {
        LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: isTracking,
            authorizationStatus: authorizationStatus,
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            distanceFilterMeters: distanceFilterMeters,
            hasNavigationLocationSession: hasNavigationLocationSession
        )
    }

    static func effectiveApplicationStateForTracking(currentState: UIApplication.State,
                                                     context: TrackingApplicationStateContext) -> UIApplication.State {
        LocationTrackingPolicy.effectiveApplicationState(currentState: currentState, context: context)
    }

    static func batteryPercent(from batteryLevel: Float) -> Int? {
        LocationTrackingPolicy.batteryPercent(from: batteryLevel)
    }

    static func processableLocationUpdates(from locations: [CLLocation]) -> [CLLocation] {
        LocationSamplePolicy.processableLocationUpdates(from: locations)
    }

    static func locationSampleProcessingDecision(for location: CLLocation,
                                                 now: Date,
                                                 latestRawLocation: CLLocation?,
                                                 currentLocation: CLLocation?,
                                                 smartReferenceLocation: CLLocation?,
                                                 maximumAge: TimeInterval = maximumLocationSampleAge,
                                                 futureTolerance: TimeInterval = maximumLocationSampleFutureSkew) -> LocationSampleProcessingDecision {
        LocationSamplePolicy.processingDecision(
            for: location,
            now: now,
            latestRawLocation: latestRawLocation,
            currentLocation: currentLocation,
            smartReferenceLocation: smartReferenceLocation,
            maximumAge: maximumAge,
            futureTolerance: futureTolerance
        )
    }

    static func newestSmartFrequentExitFenceAnchor(from candidates: [CLLocation?]) -> CLLocation? {
        SmartFrequentBackgroundPolicy.newestExitFenceAnchor(from: candidates)
    }

    static func shouldUsePersistedSmartFrequentBackgroundSeed(now: Date,
                                                             seedTimestamp: Date,
                                                             inactivityWindow: TimeInterval) -> Bool {
        SmartFrequentBackgroundPolicy.shouldUsePersistedSeed(
            now: now,
            seedTimestamp: seedTimestamp,
            inactivityWindow: inactivityWindow
        )
    }

    static func smartFrequentBackgroundSeedLocation(latitude: Double,
                                                    longitude: Double,
                                                    altitude: Double,
                                                    horizontalAccuracy: Double,
                                                    verticalAccuracy: Double,
                                                    course: Double,
                                                    speed: Double,
                                                    timestamp: Date,
                                                    now: Date,
                                                    inactivityWindow: TimeInterval) -> CLLocation? {
        SmartFrequentBackgroundPolicy.seedLocation(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp,
            now: now,
            inactivityWindow: inactivityWindow
        )
    }

    static func smartFrequentBackgroundSpeedKmh(for location: CLLocation,
                                                previousLocation: CLLocation?,
                                                detectionMode: SmartFrequentBackgroundSpeedDetectionMode) -> Double? {
        SmartFrequentBackgroundPolicy.speedKmh(
            for: location,
            previousLocation: previousLocation,
            detectionMode: detectionMode
        )
    }

    static func smartFrequentExitFenceRadius(frequentDistanceFilterMeters: Int,
                                             maximumRegionMonitoringDistance: CLLocationDistance) -> CLLocationDistance {
        SmartFrequentBackgroundPolicy.exitFenceRadius(
            frequentDistanceFilterMeters: frequentDistanceFilterMeters,
            maximumRegionMonitoringDistance: maximumRegionMonitoringDistance
        )
    }

    static func shouldMaintainSmartFrequentExitFence(trackAndReportLocation: Bool,
                                                     isTracking: Bool,
                                                     authorizationStatus: CLAuthorizationStatus,
                                                     deviceKeyAuthBlocked: Bool,
                                                     smartEnabled: Bool,
                                                     manualFrequentEnabled: Bool,
                                                     smartRuntimeActive: Bool,
                                                     regionMonitoringAvailable: Bool) -> Bool {
        SmartFrequentBackgroundPolicy.shouldMaintainExitFence(
            trackAndReportLocation: trackAndReportLocation,
            isTracking: isTracking,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            smartEnabled: smartEnabled,
            manualFrequentEnabled: manualFrequentEnabled,
            smartRuntimeActive: smartRuntimeActive,
            regionMonitoringAvailable: regionMonitoringAvailable
        )
    }

    static func smartFrequentActivationEvidence(for location: CLLocation,
                                                previousLocation: CLLocation?,
                                                detectionMode: SmartFrequentBackgroundSpeedDetectionMode,
                                                thresholdKmh: Int,
                                                frequentDistanceFilterMeters: Int,
                                                isStartupBatch: Bool,
                                                regionExitRadiusMeters: CLLocationDistance? = nil) -> SmartFrequentActivationEvidence {
        SmartFrequentBackgroundPolicy.activationEvidence(
            for: location,
            previousLocation: previousLocation,
            detectionMode: detectionMode,
            thresholdKmh: thresholdKmh,
            frequentDistanceFilterMeters: frequentDistanceFilterMeters,
            isStartupBatch: isStartupBatch,
            regionExitRadiusMeters: regionExitRadiusMeters
        )
    }

    static func shouldActivateSmartFrequentBackgroundUpdates(speedKmh: Double?,
                                                             thresholdKmh: Int) -> Bool {
        SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: speedKmh, thresholdKmh: thresholdKmh)
    }

    static func canActivateSmartFrequentBackgroundUpdates(now: Date,
                                                          locationTimestamp: Date,
                                                          previousLocationUpdateAt: Date?,
                                                          inactivityWindow: TimeInterval,
                                                          evidenceKind: SmartFrequentActivationEvidenceKind = .trustedDerivedSpeed) -> Bool {
        SmartFrequentBackgroundPolicy.canActivate(
            now: now,
            locationTimestamp: locationTimestamp,
            previousLocationUpdateAt: previousLocationUpdateAt,
            inactivityWindow: inactivityWindow,
            evidenceKind: evidenceKind
        )
    }

    static func shouldDeactivateSmartFrequentBackgroundUpdates(now: Date,
                                                               lastLocationUpdateAt: Date?,
                                                               lastRelevantMovementAt: Date?,
                                                               inactivityWindow: TimeInterval) -> Bool {
        SmartFrequentBackgroundPolicy.shouldDeactivate(
            now: now,
            lastLocationUpdateAt: lastLocationUpdateAt,
            lastRelevantMovementAt: lastRelevantMovementAt,
            inactivityWindow: inactivityWindow
        )
    }

    static func nextSmartFrequentBackgroundInactivityTimeout(lastLocationUpdateAt: Date?,
                                                             lastRelevantMovementAt: Date?,
                                                             inactivityWindow: TimeInterval) -> Date? {
        SmartFrequentBackgroundPolicy.nextInactivityTimeout(
            lastLocationUpdateAt: lastLocationUpdateAt,
            lastRelevantMovementAt: lastRelevantMovementAt,
            inactivityWindow: inactivityWindow
        )
    }

    static func smartFrequentMovementDistanceThreshold(frequentDistanceFilterMeters: Int,
                                                       from previousLocation: CLLocation?,
                                                       to location: CLLocation) -> CLLocationDistance {
        SmartFrequentBackgroundPolicy.movementDistanceThreshold(
            frequentDistanceFilterMeters: frequentDistanceFilterMeters,
            from: previousLocation,
            to: location
        )
    }

    static func shouldConfirmSmartFrequentBackgroundMovement(distanceMeters: CLLocationDistance?,
                                                             thresholdMeters: CLLocationDistance) -> Bool {
        SmartFrequentBackgroundPolicy.shouldConfirmMovement(
            distanceMeters: distanceMeters,
            thresholdMeters: thresholdMeters
        )
    }

    static func smartFrequentBackgroundWatchdogAction(phase: SmartFrequentRuntimePhase,
                                                      smartEnabled: Bool,
                                                      manualFrequentEnabled: Bool,
                                                      lastFrequentCallbackAt: Date?,
                                                      runtimeStartedAt: Date?,
                                                      recoveryAttemptCount: Int,
                                                      now: Date,
                                                      interval: TimeInterval = smartFrequentBackgroundRuntimeWatchdogInterval,
                                                      maximumRecoveryAttempts: Int = maximumSmartFrequentBackgroundRuntimeRecoveryAttempts) -> SmartFrequentBackgroundWatchdogAction {
        SmartFrequentBackgroundPolicy.watchdogAction(
            phase: phase,
            smartEnabled: smartEnabled,
            manualFrequentEnabled: manualFrequentEnabled,
            lastFrequentCallbackAt: lastFrequentCallbackAt,
            runtimeStartedAt: runtimeStartedAt,
            recoveryAttemptCount: recoveryAttemptCount,
            now: now,
            interval: interval,
            maximumRecoveryAttempts: maximumRecoveryAttempts
        )
    }

    static func shouldBypassLocationSensitivityForFrequentBackgroundUpload(applicationState: UIApplication.State,
                                                                           updateSourceIsFrequentBackground: Bool,
                                                                           manualFrequentEnabled: Bool,
                                                                           smartRuntimePhase: SmartFrequentRuntimePhase) -> Bool {
        LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: applicationState,
            updateSourceIsFrequentBackground: updateSourceIsFrequentBackground,
            manualFrequentEnabled: manualFrequentEnabled,
            smartRuntimePhase: smartRuntimePhase
        )
    }

    static func shouldDisableFrequentBackgroundUpdatesForBattery(frequentUpdatesEnabled: Bool,
                                                                 batteryPercent: Int?,
                                                                 thresholdPercent: Int) -> Bool {
        LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            batteryPercent: batteryPercent,
            thresholdPercent: thresholdPercent
        )
    }

    static func frequentBackgroundLocationDeliveryDelay(applicationState: UIApplication.State,
                                                        frequentUpdatesEnabled: Bool,
                                                        deliveryMode: FrequentBackgroundLocationDeliveryMode) -> TimeInterval? {
        LocationTrackingPolicy.frequentBackgroundLocationDeliveryDelay(
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            deliveryMode: deliveryMode
        )
    }

    static func frequentBackgroundVisitorCheckMinimumInterval(applicationState: UIApplication.State,
                                                              frequentUpdatesEnabled: Bool,
                                                              visitorCheckInterval: FrequentBackgroundVisitorCheckInterval) -> TimeInterval? {
        LocationTrackingPolicy.frequentBackgroundVisitorCheckMinimumInterval(
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            visitorCheckInterval: visitorCheckInterval
        )
    }

    static func shouldMaintainSignificantChangeRecoveryAnchor(trackAndReportLocation: Bool,
                                                              authorizationStatus: CLAuthorizationStatus,
                                                              deviceKeyAuthBlocked: Bool) -> Bool {
        LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: trackAndReportLocation,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked
        )
    }

    static func shouldMaintainLocationServiceSession(trackAndReportLocation: Bool,
                                                     isTracking: Bool,
                                                     authorizationStatus: CLAuthorizationStatus,
                                                     deviceKeyAuthBlocked: Bool) -> Bool {
        LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: trackAndReportLocation,
            isTracking: isTracking,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked
        )
    }

    static func shouldRestoreTrackingAfterLaunch(trackAndReportLocation: Bool,
                                                  deviceKeyAuthBlocked: Bool) -> Bool {
        LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: trackAndReportLocation,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked
        )
    }

    static func trackingReconcileAction(trackAndReportLocation: Bool,
                                        deviceKeyAuthBlocked: Bool,
                                        authorizationStatus: CLAuthorizationStatus,
                                        isTracking: Bool) -> TrackingReconcileAction {
        LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: trackAndReportLocation,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            authorizationStatus: authorizationStatus,
            isTracking: isTracking
        )
    }

    static func shouldDisableTrackingPreference(authorizationStatus: CLAuthorizationStatus) -> Bool {
        LocationTrackingPolicy.shouldDisableTrackingPreference(authorizationStatus: authorizationStatus)
    }

    static func significantChangeRearmDecision(buildIdentifier: String,
                                               alreadyRearmedBuildIdentifier: String?,
                                               reason: String,
                                               trackAndReportLocation: Bool,
                                               authorizationStatus: CLAuthorizationStatus,
                                               deviceKeyAuthBlocked: Bool,
                                               now: Date = Date()) -> SignificantChangeRearmDecision {
        LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: buildIdentifier,
            alreadyRearmedBuildIdentifier: alreadyRearmedBuildIdentifier,
            reason: reason,
            trackAndReportLocation: trackAndReportLocation,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            now: now
        )
    }

    static func shouldMaintainFrequentBackgroundActivitySession(trackAndReportLocation: Bool,
                                                                isTracking: Bool,
                                                                frequentUpdatesEnabled: Bool,
                                                                authorizationStatus: CLAuthorizationStatus,
                                                                deviceKeyAuthBlocked: Bool) -> Bool {
        LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: trackAndReportLocation,
            isTracking: isTracking,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked
        )
    }

    static func locationServiceCommandPlan(for mode: TrackingMode,
                                           shouldMaintainRecoveryAnchor: Bool) -> LocationServiceCommandPlan {
        LocationTrackingPolicy.locationServiceCommandPlan(
            for: mode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor
        )
    }

    static func locationSubmissionDeduplicationKey(for location: CLLocation) -> LocationSubmissionDeduplicationKey? {
        LocationSamplePolicy.submissionDeduplicationKey(for: location)
    }

    static func shouldSubmitLocationForUpload(_ location: CLLocation,
                                              lastSubmittedKey: LocationSubmissionDeduplicationKey?) -> Bool {
        LocationSamplePolicy.shouldSubmitLocationForUpload(location, lastSubmittedKey: lastSubmittedKey)
    }

    static func backgroundTrackingGapAssessment(
        state: BackgroundTrackingForensicState,
        now: Date,
        frequentThreshold: TimeInterval = forensicFrequentBackgroundGapThreshold
    ) -> BackgroundTrackingGapAssessment? {
        LocationBackgroundForensics.gapAssessment(
            state: state,
            now: now,
            frequentThreshold: frequentThreshold
        )
    }

    static func shouldLogForegroundRecoveryBurst(foregroundOpenedAt: Date?,
                                                 recoveryAlreadyLoggedAt: Date?,
                                                 now: Date,
                                                 acceptedCount: Int,
                                                 uploadCount: Int,
                                                 window: TimeInterval = forensicForegroundRecoveryBurstWindow) -> Bool {
        LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: foregroundOpenedAt,
            recoveryAlreadyLoggedAt: recoveryAlreadyLoggedAt,
            now: now,
            acceptedCount: acceptedCount,
            uploadCount: uploadCount,
            window: window
        )
    }

    static func frequentBackgroundModeSwitchReason(didExpire: Bool,
                                                   didDisableForBattery: Bool) -> String {
        LocationTrackingPolicy.frequentBackgroundModeSwitchReason(
            didExpire: didExpire,
            didDisableForBattery: didDisableForBattery
        )
    }

    var currentBackgroundTrackingDisplayMode: BackgroundTrackingDisplayMode {
        Self.backgroundTrackingDisplayMode(
            applicationState: UIApplication.shared.applicationState,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive
        )
    }

    private var effectiveFrequentBackgroundUpdatesEnabled: Bool {
        Self.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
            smartRuntimeActive: smartFrequentBackgroundRuntimeActive
        )
    }

    static func shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
        applicationState: UIApplication.State,
        frequentUpdatesEnabled: Bool,
        didSwitchFrequentBackgroundMode: Bool,
        frequentBackgroundStandardUpdatesActiveInCurrentProcess: Bool,
        updateSourceIsPrimary: Bool
    ) -> Bool {
        LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: frequentBackgroundStandardUpdatesActiveInCurrentProcess,
            updateSourceIsPrimary: updateSourceIsPrimary
        )
    }

    static func shouldCleanUpStaleFrequentBackgroundCallback(frequentUpdatesEnabled: Bool,
                                                             didSwitchFrequentBackgroundMode: Bool,
                                                             updateSourceIsFrequentBackground: Bool) -> Bool {
        LocationTrackingPolicy.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            updateSourceIsFrequentBackground: updateSourceIsFrequentBackground
        )
    }

    static func shouldSuppressStaleFrequentBackgroundCallback(allowNextStaleCallback: Bool) -> Bool {
        LocationTrackingPolicy.shouldSuppressStaleFrequentBackgroundCallback(allowNextStaleCallback: allowNextStaleCallback)
    }

    static func shouldReassertStandardSignificantChangeAfterPrimaryCallback(
        applicationState: UIApplication.State,
        frequentUpdatesEnabled: Bool,
        didSwitchFrequentBackgroundMode: Bool,
        shouldMaintainRecoveryAnchor: Bool,
        updateSourceIsPrimary: Bool
    ) -> Bool {
        LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor,
            updateSourceIsPrimary: updateSourceIsPrimary
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
        if settings.deviceKeyAuthBlocked {
            debugLog("startTracking blocked due to DeviceKey auth failure")
            isTracking = false
            stopAllLocationServices()
            return
        }
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
        refreshFrequentBackgroundTrackingReminder()
        backgroundTrackingForensicState.lastRestoreAfterLaunchAt = Date()
        evaluateBackgroundTrackingGap(trigger: "restore tracking after launch: \(reason)")

        guard Self.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: settings.trackAndReportLocation,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        ) else {
            isTracking = false
            stopAllLocationServices()
            return
        }

        ensureAuthorizationIfNeeded()
        isTracking = true
        restorePersistedSmartFrequentBackgroundSeedIfNeeded()
        debugLog("[LocationManager] restoreTrackingAfterLaunch reason=\(reason), status=\(authorizationStatus.rawValue), frequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), context=\(applicationStateContext)")
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
            ]
        )
        applyTrackingMode(reason: "restore tracking after launch: \(reason)", applicationStateContext: applicationStateContext)
        refreshPendingLocationUpdateCount()
    }

    func rearmSignificantChangeMonitorAfterFreshLaunchIfNeeded(buildIdentifier: String, reason: String) {
        let status = locationManager.authorizationStatus
        let decision = Self.significantChangeRearmDecision(
            buildIdentifier: buildIdentifier,
            alreadyRearmedBuildIdentifier: userDefaults.string(forKey: significantChangeRearmedBuildIdentifierKey),
            reason: reason,
            trackAndReportLocation: settings.trackAndReportLocation,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )

        lastSignificantChangeRearmStatus = decision.status
        persistLastSignificantChangeRearmStatus(decision.status)
        backgroundTrackingForensicState.lastSignificantChangeRearmAt = decision.status.timestamp
        persistBackgroundTrackingForensicState()

        guard decision.shouldAttempt else {
            diagnosticsLog.append(
                level: .info,
                event: "significantChangeRearm",
                summary: "Skipped significant-change re-arm.",
                result: decision.status.result.rawValue,
                reason: decision.status.reason,
                checks: decision.status.checks,
                context: ["buildIdentifier": .string(buildIdentifier)]
            )
            return
        }

        debugLog("[LocationManager] Re-arming significant-change monitor after fresh launch (\(reason))")
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.stopMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = false
        locationManager.startMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = true
        userDefaults.set(buildIdentifier, forKey: significantChangeRearmedBuildIdentifierKey)

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
            ]
        )
    }
    
    func stopTracking() {
        debugLog("stopTracking called")
        isTracking = false
        applyTrackingMode(reason: "stop tracking")
    }

    @discardableResult
    func beginNavigationLocationSession() -> UUID {
        let id = UUID()
        navigationLocationSessionIDs.insert(id)
        debugLog("[LocationManager] beginNavigationLocationSession id=\(id), activeSessions=\(navigationLocationSessionIDs.count)")
        applyTrackingMode(reason: "begin navigation location session")
        return id
    }

    func endNavigationLocationSession(_ id: UUID) {
        guard navigationLocationSessionIDs.remove(id) != nil else { return }
        debugLog("[LocationManager] endNavigationLocationSession id=\(id), activeSessions=\(navigationLocationSessionIDs.count)")
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

    private func persistLastSignificantChangeRearmStatus(_ status: LocationSignificantChangeRearmStatus) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(status) {
            userDefaults.set(data, forKey: lastSignificantChangeRearmStatusKey)
        }
    }

    private func loadLastSignificantChangeRearmStatus() -> LocationSignificantChangeRearmStatus? {
        guard let data = userDefaults.data(forKey: lastSignificantChangeRearmStatusKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocationSignificantChangeRearmStatus.self, from: data)
    }

    private func persistBackgroundTrackingForensicState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(backgroundTrackingForensicState) {
            userDefaults.set(data, forKey: backgroundTrackingForensicStateKey)
        }
    }

    private func loadBackgroundTrackingForensicState() -> BackgroundTrackingForensicState {
        guard let data = userDefaults.data(forKey: backgroundTrackingForensicStateKey) else {
            return BackgroundTrackingForensicState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BackgroundTrackingForensicState.self, from: data)) ?? BackgroundTrackingForensicState()
    }

    private func trackingModeForensicDescription(_ mode: TrackingMode) -> String {
        switch mode {
        case .stopped:
            return "stopped"
        case .foregroundHighAccuracy:
            return "foregroundHighAccuracy"
        case .backgroundSignificantChange:
            return "backgroundSignificantChange"
        case .backgroundFrequent(let distanceFilter, let desiredAccuracy):
            return "backgroundFrequent(distanceFilter: \(distanceFilter), desiredAccuracy: \(desiredAccuracy))"
        }
    }

    private func recordForensicModeResolution(mode: TrackingMode,
                                              applicationState: UIApplication.State,
                                              reason: String,
                                              now: Date = Date()) {
        let expectedMode = trackingModeForensicDescription(mode)
        backgroundTrackingForensicState.currentExpectedMode = expectedMode
        backgroundTrackingForensicState.lastModeAssertionAt = now
        backgroundTrackingForensicState.lastModeAssertionReason = reason
        backgroundTrackingForensicState.lastKnownApplicationState = applicationState.rawValue

        switch mode {
        case .backgroundSignificantChange, .backgroundFrequent:
            if backgroundTrackingForensicState.backgroundTrackingExpectedSince == nil {
                backgroundTrackingForensicState.backgroundTrackingExpectedSince = now
            }
        case .foregroundHighAccuracy, .stopped:
            backgroundTrackingForensicState.backgroundTrackingExpectedSince = nil
        }
        persistBackgroundTrackingForensicState()
    }

    private func recordForensicServiceAssertion(mode: TrackingMode, now: Date = Date()) {
        switch mode {
        case .backgroundSignificantChange, .backgroundFrequent:
            backgroundTrackingForensicState.lastServiceAssertionAt = now
            backgroundTrackingForensicState.backgroundServicesAsserted = true
        case .foregroundHighAccuracy, .stopped:
            backgroundTrackingForensicState.backgroundServicesAsserted = false
        }
        persistBackgroundTrackingForensicState()
    }

    private func recordForensicForegroundOpen(trigger: String, now: Date = Date()) {
        evaluateBackgroundTrackingGap(trigger: trigger, now: now, prepareForegroundRecovery: true)
        backgroundTrackingForensicState.lastForegroundOpenAt = now
        persistBackgroundTrackingForensicState()
    }

    private func evaluateBackgroundTrackingGap(trigger: String,
                                               now: Date = Date(),
                                               prepareForegroundRecovery: Bool = false) {
        guard let assessment = Self.backgroundTrackingGapAssessment(
            state: backgroundTrackingForensicState,
            now: now
        ) else {
            if prepareForegroundRecovery {
                resetPendingForegroundRecovery()
            }
            return
        }

        if let lastLoggedAt = backgroundTrackingForensicState.lastBackgroundGapLoggedAt,
           now.timeIntervalSince(lastLoggedAt) < Self.forensicFrequentBackgroundGapThreshold {
            if prepareForegroundRecovery {
                preparePendingForegroundRecovery(assessment: assessment, now: now)
            }
            persistBackgroundTrackingForensicState()
            return
        }

        let level: LocationDiagnosticsLogLevel = assessment.kind == .suspicious ? .warning : .info
        diagnosticsLog.append(
            level: level,
            event: "backgroundTrackingGap",
            summary: assessment.kind == .suspicious ? "Expected background tracking had a long callback/upload gap." : "Significant-change background tracking had no observable wake in this interval.",
            result: assessment.kind.rawValue,
            reason: trigger,
            checks: [
                LocationDiagnosticsLogStore.check(
                    "backgroundTrackingExpected",
                    backgroundTrackingForensicState.backgroundTrackingExpectedSince != nil,
                    detail: "Expected since \(String(describing: backgroundTrackingForensicState.backgroundTrackingExpectedSince))."
                ),
                LocationDiagnosticsLogStore.check(
                    "gapExceedsThreshold",
                    true,
                    detail: "\(assessment.gapSeconds)s >= \(Int(Self.forensicFrequentBackgroundGapThreshold))s."
                )
            ],
            context: forensicGapContext(assessment: assessment)
        )
        backgroundTrackingForensicState.lastBackgroundGapLoggedAt = now
        if prepareForegroundRecovery {
            preparePendingForegroundRecovery(assessment: assessment, now: now)
        }
        persistBackgroundTrackingForensicState()
    }

    private func preparePendingForegroundRecovery(assessment: BackgroundTrackingGapAssessment, now: Date) {
        backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt = now
        backgroundTrackingForensicState.pendingForegroundRecoveryPreviousMode = backgroundTrackingForensicState.currentExpectedMode
        backgroundTrackingForensicState.pendingForegroundRecoveryGapSeconds = assessment.gapSeconds
        backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundCallbackAt = backgroundTrackingForensicState.lastBackgroundCallbackAt
        backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundUploadAt = backgroundTrackingForensicState.lastBackgroundUploadAt
        backgroundTrackingForensicState.pendingForegroundRecoveryBackgroundServicesAsserted = backgroundTrackingForensicState.backgroundServicesAsserted
        backgroundTrackingForensicState.foregroundBurstCallbackCount = 0
        backgroundTrackingForensicState.foregroundBurstAcceptedCount = 0
        backgroundTrackingForensicState.foregroundBurstUploadCount = 0
        backgroundTrackingForensicState.foregroundRecoveryBurstLoggedAt = nil
    }

    private func resetPendingForegroundRecovery() {
        backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt = nil
        backgroundTrackingForensicState.pendingForegroundRecoveryPreviousMode = nil
        backgroundTrackingForensicState.pendingForegroundRecoveryGapSeconds = nil
        backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundCallbackAt = nil
        backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundUploadAt = nil
        backgroundTrackingForensicState.pendingForegroundRecoveryBackgroundServicesAsserted = nil
        backgroundTrackingForensicState.foregroundBurstCallbackCount = 0
        backgroundTrackingForensicState.foregroundBurstAcceptedCount = 0
        backgroundTrackingForensicState.foregroundBurstUploadCount = 0
        backgroundTrackingForensicState.foregroundRecoveryBurstLoggedAt = nil
    }

    private func forensicGapContext(assessment: BackgroundTrackingGapAssessment) -> [String: LocationDiagnosticsValue] {
        var context: [String: LocationDiagnosticsValue] = [
            "gapSeconds": .integer(assessment.gapSeconds),
            "currentExpectedMode": .string(backgroundTrackingForensicState.currentExpectedMode ?? "unknown"),
            "backgroundServicesAsserted": .bool(backgroundTrackingForensicState.backgroundServicesAsserted)
        ]
        if let expectedSince = backgroundTrackingForensicState.backgroundTrackingExpectedSince {
            context["backgroundTrackingExpectedSince"] = .string(ISO8601DateFormatter().string(from: expectedSince))
        }
        if let lastObservedAt = assessment.lastObservedAt {
            context["lastObservedBackgroundActivityAt"] = .string(ISO8601DateFormatter().string(from: lastObservedAt))
        }
        if let lastCallbackAt = backgroundTrackingForensicState.lastBackgroundCallbackAt {
            context["lastBackgroundCallbackAt"] = .string(ISO8601DateFormatter().string(from: lastCallbackAt))
        }
        if let lastUploadAt = backgroundTrackingForensicState.lastBackgroundUploadAt {
            context["lastBackgroundUploadAt"] = .string(ISO8601DateFormatter().string(from: lastUploadAt))
        }
        return context
    }

    private func recordForensicLocationCallback(applicationState: UIApplication.State,
                                                source: LocationUpdateSource,
                                                timestamp: Date = Date()) {
        backgroundTrackingForensicState.lastKnownApplicationState = applicationState.rawValue
        backgroundTrackingForensicState.lastKnownSource = source.rawValue
        if applicationState == .active {
            if backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt != nil,
               source == .primary {
                backgroundTrackingForensicState.foregroundBurstCallbackCount += 1
            }
        } else {
            backgroundTrackingForensicState.lastBackgroundCallbackAt = timestamp
        }
        persistBackgroundTrackingForensicState()
    }

    private func recordForensicAcceptedLocation(applicationState: UIApplication.State,
                                                source: LocationUpdateSource,
                                                timestamp: Date = Date()) {
        if applicationState == .active {
            if backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt != nil,
               source == .primary {
                backgroundTrackingForensicState.foregroundBurstAcceptedCount += 1
                maybeLogForegroundRecoveryBurst(now: timestamp)
            }
        } else {
            backgroundTrackingForensicState.lastAcceptedBackgroundLocationAt = timestamp
        }
        persistBackgroundTrackingForensicState()
    }

    private func recordForensicUpload(applicationState: UIApplication.State, timestamp: Date = Date()) {
        if applicationState == .active {
            if backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt != nil {
                backgroundTrackingForensicState.foregroundBurstUploadCount += 1
                maybeLogForegroundRecoveryBurst(now: timestamp)
            }
        } else {
            backgroundTrackingForensicState.lastBackgroundUploadAt = timestamp
        }
        persistBackgroundTrackingForensicState()
    }

    private func maybeLogForegroundRecoveryBurst(now: Date = Date()) {
        guard Self.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt,
            recoveryAlreadyLoggedAt: backgroundTrackingForensicState.foregroundRecoveryBurstLoggedAt,
            now: now,
            acceptedCount: backgroundTrackingForensicState.foregroundBurstAcceptedCount,
            uploadCount: backgroundTrackingForensicState.foregroundBurstUploadCount
        ) else {
            return
        }

        diagnosticsLog.append(
            level: .warning,
            event: "foregroundRecoveryBurst",
            summary: "Foreground opening was followed by accepted/uploaded primary locations after a background gap.",
            result: "foreground activity after gap",
            reason: "manual foreground wake",
            checks: [
                LocationDiagnosticsLogStore.check(
                    "withinRecoveryWindow",
                    true,
                    detail: "Foreground activity occurred within \(Int(Self.forensicForegroundRecoveryBurstWindow))s."
                )
            ],
            context: foregroundRecoveryContext()
        )
        backgroundTrackingForensicState.foregroundRecoveryBurstLoggedAt = now
        persistBackgroundTrackingForensicState()
    }

    private func foregroundRecoveryContext() -> [String: LocationDiagnosticsValue] {
        var context: [String: LocationDiagnosticsValue] = [
            "previousExpectedMode": .string(backgroundTrackingForensicState.pendingForegroundRecoveryPreviousMode ?? "unknown"),
            "gapSeconds": .integer(backgroundTrackingForensicState.pendingForegroundRecoveryGapSeconds ?? 0),
            "foregroundCallbackCount": .integer(backgroundTrackingForensicState.foregroundBurstCallbackCount),
            "foregroundAcceptedCount": .integer(backgroundTrackingForensicState.foregroundBurstAcceptedCount),
            "foregroundUploadCount": .integer(backgroundTrackingForensicState.foregroundBurstUploadCount),
            "backgroundServicesAsserted": .bool(backgroundTrackingForensicState.pendingForegroundRecoveryBackgroundServicesAsserted ?? backgroundTrackingForensicState.backgroundServicesAsserted)
        ]
        if let startedAt = backgroundTrackingForensicState.pendingForegroundRecoveryStartedAt {
            context["foregroundOpenedAt"] = .string(ISO8601DateFormatter().string(from: startedAt))
        }
        if let lastCallbackAt = backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundCallbackAt {
            context["lastBackgroundCallbackAt"] = .string(ISO8601DateFormatter().string(from: lastCallbackAt))
        }
        if let lastUploadAt = backgroundTrackingForensicState.pendingForegroundRecoveryLastBackgroundUploadAt {
            context["lastBackgroundUploadAt"] = .string(ISO8601DateFormatter().string(from: lastUploadAt))
        }
        return context
    }

    @discardableResult
    private func reconcileTrackingState(reason: String,
                                        applicationStateContext: TrackingApplicationStateContext = .current,
                                        refreshExternalSettings: Bool = false) -> TrackingReconcileAction {
        let didRefreshExternalSettings: Bool
        if refreshExternalSettings {
            didRefreshExternalSettings = settings.refreshFromUserDefaultsForAppActivation()
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
        refreshFrequentBackgroundTrackingReminder()
        let action = Self.trackingReconcileAction(
            trackAndReportLocation: settings.trackAndReportLocation,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
            authorizationStatus: status,
            isTracking: isTracking
        )
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

    private func applyTrackingMode(reason: String, applicationStateContext: TrackingApplicationStateContext = .current) {
        let state = Self.effectiveApplicationStateForTracking(
            currentState: UIApplication.shared.applicationState,
            context: applicationStateContext
        )
        let status = locationManager.authorizationStatus

        if settings.deviceKeyAuthBlocked {
            debugLog("[LocationManager] applyTrackingMode stopped because DeviceKey auth is blocked")
            isTracking = false
            stopAllLocationServices()
            return
        }

        handleFrequentBackgroundLocationExpirationIfNeeded()
        if Self.shouldEvaluateSmartFrequentRuntime(applicationState: state) {
            handleSmartFrequentBackgroundInactivityIfNeeded(applicationState: state)
        }
        if isTracking, state != .active {
            disableFrequentBackgroundLocationUpdatesIfBatteryIsLow()
        }

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
            hasNavigationLocationSession: !navigationLocationSessionIDs.isEmpty
        )
        let shouldMaintainRecoveryAnchor = Self.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: settings.trackAndReportLocation && isTracking,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )
        let shouldMaintainFrequentActivitySession = Self.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: settings.trackAndReportLocation,
            isTracking: isTracking,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            authorizationStatus: status,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )
        let commandPlan = Self.locationServiceCommandPlan(
            for: mode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor
        )
        if state != .active {
            evaluateBackgroundTrackingGap(trigger: reason)
        }
        recordForensicModeResolution(mode: mode, applicationState: state, reason: reason)
        debugLog("[LocationManager] applyTrackingMode reason=\(reason), context=\(applicationStateContext), state=\(state.rawValue), status=\(status.rawValue), isTracking=\(isTracking), navigationSessions=\(navigationLocationSessionIDs.count), manualFrequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), smartEnabled=\(settings.smartFrequentBackgroundLocationUpdatesEnabled), smartRuntimeActive=\(smartFrequentBackgroundRuntimeActive), effectiveFrequent=\(effectiveFrequentBackgroundUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), primaryRecoveryAnchorActive=\(isSignificantChangeRecoveryAnchorActive), mode=\(mode), commandPlan=\(commandPlan)")
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
                "primaryRecoveryAnchorActive": .bool(isSignificantChangeRecoveryAnchorActive),
                "navigationSessions": .integer(navigationLocationSessionIDs.count)
            ]
        )
        syncLocationServiceSession(
            reason: reason,
            shouldMaintainSession: Self.shouldMaintainLocationServiceSession(
                trackAndReportLocation: settings.trackAndReportLocation,
                isTracking: isTracking,
                authorizationStatus: status,
                deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
            )
        )
        syncFrequentBackgroundActivitySession(
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
        locationManager.showsBackgroundLocationIndicator = false
        frequentBackgroundLocationManager.showsBackgroundLocationIndicator = shouldShowIndicator
    }

    private func startHighAccuracyUpdates() {
        debugLog("Calling startHighAccuracyUpdates")
        recordForensicServiceAssertion(mode: .foregroundHighAccuracy)
        let shouldMaintainPrimarySignificantChangeMonitor = Self.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: settings.trackAndReportLocation && isTracking,
            authorizationStatus: locationManager.authorizationStatus,
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )
        if shouldMaintainPrimarySignificantChangeMonitor {
            debugLog("[LocationManager] Keeping primary significant-change monitor active during foreground tracking")
            locationManager.startMonitoringSignificantLocationChanges()
        } else {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
        stopFrequentBackgroundStandardUpdates()
        locationManager.allowsBackgroundLocationUpdates = false
        debugLog("allowsBackgroundLocationUpdates set to false (foreground)")
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
    
    private func startSignificantChangeMonitoring() {
        debugLog("Starting significant-change background updates")
        recordForensicServiceAssertion(mode: .backgroundSignificantChange)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        stopFrequentBackgroundStandardUpdates()
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
            ]
        )
    }

    private func startFrequentBackgroundLocationUpdates(configuration: BackgroundUpdateConfiguration) {
        debugLog("Starting frequent background updates with distanceFilter=\(configuration.distanceFilter)m")
        recordForensicServiceAssertion(mode: .backgroundFrequent(distanceFilter: configuration.distanceFilter, desiredAccuracy: configuration.desiredAccuracy))
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        // Keep the primary manager registered for significant-change relaunch; run frequent standard updates separately.
        stopHeadingUpdates()
        frequentBackgroundLocationManager.delegate = self
        frequentBackgroundLocationManager.allowsBackgroundLocationUpdates = true
        frequentBackgroundLocationManager.pausesLocationUpdatesAutomatically = false
        frequentBackgroundLocationManager.showsBackgroundLocationIndicator = true
        frequentBackgroundLocationManager.activityType = Self.activityTypeFrom(settings.locationActivityType)
        frequentBackgroundLocationManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundLocationManager.desiredAccuracy = configuration.desiredAccuracy
        frequentBackgroundLocationManager.distanceFilter = configuration.distanceFilter
        frequentBackgroundLocationManager.startUpdatingLocation()
        isFrequentBackgroundStandardUpdatesActive = true
        shouldAllowNextStaleFrequentBackgroundCallback = false
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
                "frequentActivitySessionActive": .bool(frequentBackgroundActivitySession != nil),
                "smartRuntimePhase": .string(smartFrequentBackgroundRuntimePhase.rawValue)
            ]
        )
    }

    private func stopFrequentBackgroundStandardUpdates() {
        if isFrequentBackgroundStandardUpdatesActive {
            shouldAllowNextStaleFrequentBackgroundCallback = true
        }
        frequentBackgroundLocationManager.stopUpdatingLocation()
        frequentBackgroundLocationManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundLocationManager.allowsBackgroundLocationUpdates = false
        frequentBackgroundLocationManager.pausesLocationUpdatesAutomatically = true
        frequentBackgroundLocationManager.showsBackgroundLocationIndicator = false
        frequentBackgroundLocationManager.delegate = nil
        isFrequentBackgroundStandardUpdatesActive = false
    }

    private func syncFrequentBackgroundActivitySession(reason: String, shouldMaintainSession: Bool) {
        if shouldMaintainSession {
            startFrequentBackgroundActivitySessionIfNeeded(reason: reason)
        } else {
            stopFrequentBackgroundActivitySession(reason: reason)
        }
    }

    private func syncLocationServiceSession(reason: String, shouldMaintainSession: Bool) {
        if shouldMaintainSession {
            startLocationServiceSessionIfNeeded(reason: reason)
        } else {
            stopLocationServiceSession(reason: reason)
        }
    }

    private func startLocationServiceSessionIfNeeded(reason: String) {
        guard locationServiceSession == nil else { return }
        debugLog("[LocationManager] Starting Always CLServiceSession (\(reason))")
        locationServiceSession = CLServiceSession(authorization: .always)
    }

    private func stopLocationServiceSession(reason: String) {
        guard let locationServiceSession else { return }
        debugLog("[LocationManager] Stopping Always CLServiceSession (\(reason))")
        locationServiceSession.invalidate()
        self.locationServiceSession = nil
    }

    private func startFrequentBackgroundActivitySessionIfNeeded(reason: String) {
        if frequentBackgroundActivitySession == nil {
            debugLog("[LocationManager] Starting frequent background CLBackgroundActivitySession (\(reason))")
            frequentBackgroundActivitySession = CLBackgroundActivitySession()
        } else {
            debugLog("[LocationManager] Keeping frequent background activity session active (\(reason))")
        }
    }

    private func stopFrequentBackgroundActivitySession(reason: String) {
        if let activitySession = frequentBackgroundActivitySession {
            debugLog("[LocationManager] Stopping frequent background CLBackgroundActivitySession (\(reason))")
            activitySession.invalidate()
            frequentBackgroundActivitySession = nil
        }
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
            allowNextStaleCallback: shouldAllowNextStaleFrequentBackgroundCallback
        )
        shouldAllowNextStaleFrequentBackgroundCallback = false

        let handling = shouldSuppressCallback ? "suppressing repeated stale location" : "location remains eligible for upload"
        debugLog("[LocationManager] Cleaning up stale frequent background callback while frequent mode is disabled; \(handling)")
        stopFrequentBackgroundStandardUpdates()
        stopFrequentBackgroundActivitySession(reason: "stale frequent background callback")

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
            deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked
        )
        guard Self.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: applicationState,
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            shouldMaintainRecoveryAnchor: shouldMaintainRecoveryAnchor,
            updateSourceIsPrimary: updateSource == .primary
        ) else { return }

        debugLog("[LocationManager] Reasserting standard significant-change tracking after primary background callback")
        locationManager.allowsBackgroundLocationUpdates = true
        startSignificantChangeRecoveryAnchor(reason: "standard significant-change callback reassert")
    }

    private func ensureSignificantChangeRecoveryAnchorIfNeeded(reason: String, shouldMaintainRecoveryAnchor: Bool) {
        guard shouldMaintainRecoveryAnchor else {
            stopSignificantChangeRecoveryAnchor(reason: "recovery anchor no longer eligible: \(reason)")
            return
        }

        startSignificantChangeRecoveryAnchor(reason: "recovery anchor: \(reason)")
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
        ) && applicationState != .active

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
            frequentDistanceFilterMeters: settings.frequentBackgroundLocationDistanceFilter,
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
        diagnosticsLog.append(
            level: .info,
            event: "smartFrequentExitFence",
            summary: "Started Smart frequent exit-fence monitoring.",
            result: "active",
            reason: reason,
            context: diagnosticsLocationContext(anchorLocation, extra: [
                ("radiusMeters", .double(radius))
            ])
        )
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
        diagnosticsLog.append(
            level: .info,
            event: "smartFrequentExitFence",
            summary: "Stopped Smart frequent exit-fence monitoring.",
            result: "stopped",
            reason: reason
        )
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
        let shouldActivate = applicationState != .active &&
        isTracking &&
        settings.trackAndReportLocation &&
        locationManager.authorizationStatus == .authorizedAlways &&
        !settings.deviceKeyAuthBlocked &&
        settings.smartFrequentBackgroundLocationUpdatesEnabled &&
        !settings.frequentBackgroundLocationUpdatesEnabled &&
        !smartFrequentBackgroundRuntimeActive &&
        batteryAboveThreshold

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

    private func startSignificantChangeRecoveryAnchor(reason: String) {
        let action = isSignificantChangeRecoveryAnchorActive ? "Reasserting" : "Starting"
        debugLog("[LocationManager] \(action) primary significant-change recovery anchor (\(reason))")
        locationManager.startMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = true
    }

    private func stopSignificantChangeRecoveryAnchor(reason: String) {
        let action = isSignificantChangeRecoveryAnchorActive ? "Stopping" : "Reasserting stopped"
        debugLog("[LocationManager] \(action) primary significant-change recovery anchor (\(reason))")
        locationManager.stopMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = false
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
        } else {
            settings.ensureFrequentBackgroundLocationUpdatesExpiration(now: now)
        }
        scheduleFrequentBackgroundLocationExpirationTimer()
        return didExpire
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

    private func notifySmartFrequentBackgroundModeChangeIfEnabled(isActive: Bool) {
        guard settings.smartFrequentBackgroundModeChangeNotificationsEnabled else {
            return
        }

        Task {
            await FrequentBackgroundTrackingReminderService.shared.notifySmartFrequentModeChange(isActive: isActive)
        }
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
            updateSmartFrequentBackgroundSpeedReference(with: location)
            return false
        }

        guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: applicationState) else {
            updateSmartFrequentBackgroundSpeedReference(with: location)
            return false
        }

        let didDeactivateForInactivity = handleSmartFrequentBackgroundInactivityIfNeeded(
            now: now,
            applicationState: applicationState
        )
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
        if let speedKmh = evidence.speedKmh {
            smartFrequentBackgroundLastActivationReason = String(
                format: NSLocalizedString(
                    "smart_frequent_background_activation_speed_format",
                    comment: "Smart frequent activation reason with speed in km/h"
                ),
                speedKmh
            )
        } else {
            smartFrequentBackgroundLastActivationReason = NSLocalizedString(
                "smart_frequent_background_activation_movement",
                comment: "Smart frequent activation reason when movement is detected"
            )
        }
        scheduleSmartFrequentBackgroundInactivityTimer(now: now)
        scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
        debugLog("[LocationManager] Smart frequent background probe started evidence=\(evidence.kind.rawValue), speedKmh=\(String(describing: evidence.speedKmh))")
        backgroundTrackingForensicState.lastSmartActivationAt = now
        persistBackgroundTrackingForensicState()
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
            ])
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
            timestamp: now
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
            timestamp: now
        )
    }

    @discardableResult
    private func deactivateSmartFrequentBackgroundRuntime(reason: String,
                                                          sendsModeChangeNotification: Bool = true) -> Bool {
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
        smartFrequentBackgroundNextInactivityTimeoutAt = nil
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil
        if wasActive {
            debugLog("[LocationManager] Smart frequent background runtime deactivated: \(reason)")
            backgroundTrackingForensicState.lastSmartDeactivationAt = Date()
            persistBackgroundTrackingForensicState()
            diagnosticsLog.append(
                level: .warning,
                event: "smartFrequentDeactivation",
                summary: "Smart frequent runtime deactivated.",
                result: "deactivated",
                reason: reason,
                checks: [],
                context: [
                    "manualFrequentEnabled": .bool(settings.frequentBackgroundLocationUpdatesEnabled),
                    "smartEnabled": .bool(settings.smartFrequentBackgroundLocationUpdatesEnabled)
                ]
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
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil
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

        guard let anchor = smartFrequentBackgroundMovementAnchor else {
            smartFrequentBackgroundMovementAnchor = location
            smartFrequentBackgroundLastRelevantMovementAt = now
            smartFrequentBackgroundLastMovementLocationKey = Self.locationSubmissionDeduplicationKey(for: location)
            smartFrequentBackgroundLastMovementDistanceMeters = nil
            smartFrequentBackgroundLastMovementThresholdMeters = CLLocationDistance(settings.frequentBackgroundLocationDistanceFilter)
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
        return true
    }

    private func scheduleSmartFrequentBackgroundInactivityTimer(now: Date = Date()) {
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil

        guard settings.smartFrequentBackgroundLocationUpdatesEnabled,
              smartFrequentBackgroundRuntimeActive,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            smartFrequentBackgroundNextInactivityTimeoutAt = nil
            return
        }

        let timeout = Self.nextSmartFrequentBackgroundInactivityTimeout(
            lastLocationUpdateAt: lastSmartFrequentBackgroundLocationUpdateAt,
            lastRelevantMovementAt: smartFrequentBackgroundLastRelevantMovementAt,
            inactivityWindow: settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
        )
        smartFrequentBackgroundNextInactivityTimeoutAt = timeout

        guard let timeout else { return }
        let interval = timeout.timeIntervalSince(now)
        guard interval > 0 else {
            guard Self.shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.shared.applicationState) else {
                return
            }
            if handleSmartFrequentBackgroundInactivityIfNeeded(now: now, applicationState: .background), isTracking {
                applyTrackingMode(reason: "smart frequent inactivity timer")
            }
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
            let didDeactivate = deactivateSmartFrequentBackgroundRuntime(
                reason: "smart frequent recovery watchdog exhausted",
                sendsModeChangeNotification: false
            )
            if didDeactivate, isTracking {
                applyTrackingMode(reason: "smart frequent recovery watchdog exhausted", applicationStateContext: .forceBackground)
            }
            return
        case .reassert:
            break
        }

        smartFrequentBackgroundRecoveryAttemptCount += 1
        diagnosticsLog.append(
            level: .warning,
            event: "smartFrequentRecovery",
            summary: "Reasserted Smart frequent background updates.",
            result: "reasserted",
            reason: "frequent background callback watchdog",
            checks: [],
            context: [
                "attempt": .integer(smartFrequentBackgroundRecoveryAttemptCount),
                "maximumAttempts": .integer(Self.maximumSmartFrequentBackgroundRuntimeRecoveryAttempts),
                "phase": .string(smartFrequentBackgroundRuntimePhase.rawValue),
                "frequentManagerAllowsBackground": .bool(frequentBackgroundLocationManager.allowsBackgroundLocationUpdates),
                "frequentManagerShowsIndicator": .bool(frequentBackgroundLocationManager.showsBackgroundLocationIndicator),
                "frequentStandardUpdatesActive": .bool(isFrequentBackgroundStandardUpdatesActive),
                "frequentActivitySessionActive": .bool(frequentBackgroundActivitySession != nil)
            ],
            timestamp: now
        )

        if isTracking {
            applyTrackingMode(reason: "smart frequent recovery watchdog", applicationStateContext: .forceBackground)
            frequentBackgroundLocationManager.requestLocation()
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
              location.horizontalAccuracy >= 0 else {
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
        if location.horizontalAccuracy >= 0 {
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
    private func sendLocationToServer(_ location: CLLocation) async {
        if settings.deviceKeyAuthBlocked {
            self.serverUpdateStatus = .failed(
                NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
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
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
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
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
            )
            return
        }
        let applicationState = UIApplication.shared.applicationState
        let deliveryDelay = frequentBackgroundLocationDeliveryDelay(for: applicationState)
        let visitorCheckMinimumInterval = frequentBackgroundVisitorCheckMinimumInterval(for: applicationState)
        self.serverUpdateStatus = .updating

        let submission = await locationUpdateUploadService.submit(
            location: location,
            serverURL: serverURL,
            deviceID: thisDeviceIDManager.shared.deviceID,
            deviceKey: settings.deviceKey,
            enableHistory: settings.saveLocationHistoryOnServer,
            retentionTime: settings.locationDataRetentionTime,
            deliveryDelay: deliveryDelay,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval,
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
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
            )
            return
        case .delivery(let deliveryResult):
            result = deliveryResult
        }

        switch result {
        case .sent:
            self.markServerUpdateSucceeded()
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
            NotificationCenter.default.post(name: .didSendOwnLocationUpdate, object: nil)
            Task {
                await UnknownVisitorAlertService.shared.processAfterSuccessfulLocationUpdate(
                    serverURL: serverURL,
                    minimumInterval: visitorCheckMinimumInterval
                )
            }
        case .queued:
            debugLog("[LocationManager] updateLocation queued for retry/outbox delivery")
            self.serverUpdateStatus = .idle
            self.refreshPendingLocationUpdateCount()
            diagnosticsLog.append(
                level: .warning,
                event: "locationUpload",
                summary: "Location update queued for retry/outbox delivery.",
                result: "queued",
                reason: nil,
                checks: [],
                context: LocationDiagnosticsLogStore.roundedLocationContext(location)
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
                ])
            )
        }
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
            return NSLocalizedString("lm_foreground_status", comment: "shown in the Location Status overview for foreground updates")
        case .significantChange:
            return NSLocalizedString("location_update_mode_significant_change", comment: "Location update log mode for significant-change updates")
        case .smartFrequent:
            return NSLocalizedString("location_update_mode_smart_frequent", comment: "Location update log mode for smart frequent updates")
        case .manualFrequent:
            return NSLocalizedString("location_update_mode_manual_frequent", comment: "Location update log mode for manually enabled frequent updates")
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
    }

    func appDidEnterBackground() {
        debugLog("[LocationManager] App did enter background")
        reconcileTrackingState(reason: "app did enter background", applicationStateContext: .forceBackground)
    }

    private func stopAllLocationServices() {
        debugLog("[LocationManager] Stopping all location services")
        recordForensicServiceAssertion(mode: .stopped)
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.showsBackgroundLocationIndicator = false
        frequentBackgroundLocationManager.stopUpdatingLocation()
        frequentBackgroundLocationManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundLocationManager.allowsBackgroundLocationUpdates = false
        frequentBackgroundLocationManager.pausesLocationUpdatesAutomatically = true
        frequentBackgroundLocationManager.showsBackgroundLocationIndicator = false
        frequentBackgroundLocationManager.delegate = nil
        isSignificantChangeRecoveryAnchorActive = false
        isFrequentBackgroundStandardUpdatesActive = false
        shouldAllowNextStaleFrequentBackgroundCallback = false
        stopSmartFrequentExitFence(reason: "stop all location services")
        resetSmartFrequentBackgroundRuntime()
        stopLocationServiceSession(reason: "stop all location services")
        stopFrequentBackgroundActivitySession(reason: "stop all location services")
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
        locationManager.startUpdatingHeading()
    }

    private func stopHeadingUpdates() {
        locationManager.stopUpdatingHeading()
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
                    smartRuntimeActive: smartFrequentBackgroundRuntimeActive
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
            Task { @MainActor in
                for location in uploadLocations {
                    await self.sendLocationToServer(location)
                }
            }
        }
    }

    private func shouldAcceptLocationUpdate(_ location: CLLocation,
                                            applicationState: UIApplication.State,
                                            updateSource: LocationUpdateSource) -> Bool {
        let (minimumDistance, significantAccuracyImprovement) = mappedSensitivityValues(for: settings.locationSensitivityLevel)
        let shouldBypassSensitivityForFrequentUpload = Self.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: applicationState,
            updateSourceIsFrequentBackground: updateSource == .frequentBackground,
            manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
            smartRuntimePhase: smartFrequentBackgroundRuntimePhase
        )
        guard let previousLocation = self.currentLocation else {
            debugLog("[LocationManager] First location update accepted.")
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
