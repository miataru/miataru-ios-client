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

@MainActor
private final class LocationBackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

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
    private let backgroundUpdateCountKey = "miataru_backgroundUpdateCount"
    private let foregroundLiveUpdateCountKey = "miataru_locationUpdateCountForegroundLive"
    private let significantChangeUpdateCountKey = "miataru_locationUpdateCountSignificantChange"
    private let smartFrequentUpdateCountKey = "miataru_locationUpdateCountSmartFrequent"
    private let manualFrequentUpdateCountKey = "miataru_locationUpdateCountManualFrequent"
    private let lastBackgroundUpdateKey = "miataru_lastBackgroundUpdate"
    private let backgroundMetricsLastResetKey = "miataru_backgroundMetricsLastReset"
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
    private var lastSmoothedHeading: Double?
    private let headingSmoothingAlpha: Double = 0.25
    private let headingAccuracyThreshold: Double = 35
    private let headingMinSpeedThreshold: Double = 1.0
    private static let maximumSmartFrequentActivationSpeedKmh: Double = 200
    static let smartFrequentExitFenceIdentifier = "miataru.smartFrequentExitFence"
    static let defaultSmartFrequentExitFenceRadius: CLLocationDistance = 150
    static let minimumSmartFrequentDerivedSpeedElapsed: TimeInterval = 5
    static let maximumTrustedSmartFrequentSpeedAccuracyMetersPerSecond: CLLocationSpeedAccuracy = 2
    static let forensicFrequentBackgroundGapThreshold: TimeInterval = 10 * 60
    static let forensicForegroundRecoveryBurstWindow: TimeInterval = 30
    static let smartFrequentBackgroundProbeWatchdogInterval: TimeInterval = 75
    static let maximumSmartFrequentBackgroundProbeRecoveryAttempts = 2
    
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

    enum LocationUpdateCounterMode: String, CaseIterable, Equatable {
        case foregroundLive
        case significantChange
        case smartFrequent
        case manualFrequent
    }

    struct LocationUpdateModeCounts: Equatable {
        var foregroundLive: Int = 0
        var significantChange: Int = 0
        var smartFrequent: Int = 0
        var manualFrequent: Int = 0

        mutating func increment(_ mode: LocationUpdateCounterMode) {
            switch mode {
            case .foregroundLive:
                foregroundLive += 1
            case .significantChange:
                significantChange += 1
            case .smartFrequent:
                smartFrequent += 1
            case .manualFrequent:
                manualFrequent += 1
            }
        }

        var backgroundTotal: Int {
            significantChange + smartFrequent + manualFrequent
        }

        static let zero = LocationUpdateModeCounts()
    }

    struct BackgroundTrackingForensicState: Codable, Equatable {
        var backgroundTrackingExpectedSince: Date?
        var currentExpectedMode: String?
        var lastModeAssertionAt: Date?
        var lastModeAssertionReason: String?
        var lastServiceAssertionAt: Date?
        var lastBackgroundCallbackAt: Date?
        var lastAcceptedBackgroundLocationAt: Date?
        var lastBackgroundUploadAt: Date?
        var lastForegroundOpenAt: Date?
        var lastRestoreAfterLaunchAt: Date?
        var lastSignificantChangeRearmAt: Date?
        var lastSmartActivationAt: Date?
        var lastSmartDeactivationAt: Date?
        var lastKnownApplicationState: Int?
        var lastKnownSource: String?
        var backgroundServicesAsserted: Bool = false
        var lastBackgroundGapLoggedAt: Date?
        var pendingForegroundRecoveryStartedAt: Date?
        var pendingForegroundRecoveryPreviousMode: String?
        var pendingForegroundRecoveryGapSeconds: Int?
        var pendingForegroundRecoveryLastBackgroundCallbackAt: Date?
        var pendingForegroundRecoveryLastBackgroundUploadAt: Date?
        var pendingForegroundRecoveryBackgroundServicesAsserted: Bool?
        var foregroundBurstCallbackCount: Int = 0
        var foregroundBurstAcceptedCount: Int = 0
        var foregroundBurstUploadCount: Int = 0
        var foregroundRecoveryBurstLoggedAt: Date?

        init(backgroundTrackingExpectedSince: Date? = nil,
             currentExpectedMode: String? = nil,
             lastModeAssertionAt: Date? = nil,
             lastModeAssertionReason: String? = nil,
             lastServiceAssertionAt: Date? = nil,
             lastBackgroundCallbackAt: Date? = nil,
             lastAcceptedBackgroundLocationAt: Date? = nil,
             lastBackgroundUploadAt: Date? = nil,
             lastForegroundOpenAt: Date? = nil,
             lastRestoreAfterLaunchAt: Date? = nil,
             lastSignificantChangeRearmAt: Date? = nil,
             lastSmartActivationAt: Date? = nil,
             lastSmartDeactivationAt: Date? = nil,
             lastKnownApplicationState: Int? = nil,
             lastKnownSource: String? = nil,
             backgroundServicesAsserted: Bool = false,
             lastBackgroundGapLoggedAt: Date? = nil,
             pendingForegroundRecoveryStartedAt: Date? = nil,
             pendingForegroundRecoveryPreviousMode: String? = nil,
             pendingForegroundRecoveryGapSeconds: Int? = nil,
             pendingForegroundRecoveryLastBackgroundCallbackAt: Date? = nil,
             pendingForegroundRecoveryLastBackgroundUploadAt: Date? = nil,
             pendingForegroundRecoveryBackgroundServicesAsserted: Bool? = nil,
             foregroundBurstCallbackCount: Int = 0,
             foregroundBurstAcceptedCount: Int = 0,
             foregroundBurstUploadCount: Int = 0,
             foregroundRecoveryBurstLoggedAt: Date? = nil) {
            self.backgroundTrackingExpectedSince = backgroundTrackingExpectedSince
            self.currentExpectedMode = currentExpectedMode
            self.lastModeAssertionAt = lastModeAssertionAt
            self.lastModeAssertionReason = lastModeAssertionReason
            self.lastServiceAssertionAt = lastServiceAssertionAt
            self.lastBackgroundCallbackAt = lastBackgroundCallbackAt
            self.lastAcceptedBackgroundLocationAt = lastAcceptedBackgroundLocationAt
            self.lastBackgroundUploadAt = lastBackgroundUploadAt
            self.lastForegroundOpenAt = lastForegroundOpenAt
            self.lastRestoreAfterLaunchAt = lastRestoreAfterLaunchAt
            self.lastSignificantChangeRearmAt = lastSignificantChangeRearmAt
            self.lastSmartActivationAt = lastSmartActivationAt
            self.lastSmartDeactivationAt = lastSmartDeactivationAt
            self.lastKnownApplicationState = lastKnownApplicationState
            self.lastKnownSource = lastKnownSource
            self.backgroundServicesAsserted = backgroundServicesAsserted
            self.lastBackgroundGapLoggedAt = lastBackgroundGapLoggedAt
            self.pendingForegroundRecoveryStartedAt = pendingForegroundRecoveryStartedAt
            self.pendingForegroundRecoveryPreviousMode = pendingForegroundRecoveryPreviousMode
            self.pendingForegroundRecoveryGapSeconds = pendingForegroundRecoveryGapSeconds
            self.pendingForegroundRecoveryLastBackgroundCallbackAt = pendingForegroundRecoveryLastBackgroundCallbackAt
            self.pendingForegroundRecoveryLastBackgroundUploadAt = pendingForegroundRecoveryLastBackgroundUploadAt
            self.pendingForegroundRecoveryBackgroundServicesAsserted = pendingForegroundRecoveryBackgroundServicesAsserted
            self.foregroundBurstCallbackCount = foregroundBurstCallbackCount
            self.foregroundBurstAcceptedCount = foregroundBurstAcceptedCount
            self.foregroundBurstUploadCount = foregroundBurstUploadCount
            self.foregroundRecoveryBurstLoggedAt = foregroundRecoveryBurstLoggedAt
        }
    }

    enum BackgroundTrackingGapKind: String, Equatable {
        case suspicious
        case unobservedIdle
    }

    struct BackgroundTrackingGapAssessment: Equatable {
        let kind: BackgroundTrackingGapKind
        let gapSeconds: Int
        let lastObservedAt: Date?
    }

    enum BackgroundTrackingDisplayMode: Equatable {
        case foregroundLive
        case significantChange
        case smartWaiting
        case smartFrequent
        case manualFrequent
    }

    struct BackgroundUpdateConfiguration: Equatable {
        let usesSignificantChangeMonitoring: Bool
        let distanceFilter: CLLocationDistance
        let desiredAccuracy: CLLocationAccuracy
    }

    enum TrackingMode: Equatable {
        case stopped
        case foregroundHighAccuracy
        case backgroundSignificantChange
        case backgroundFrequent(distanceFilter: CLLocationDistance, desiredAccuracy: CLLocationAccuracy)
    }

    enum SmartFrequentRuntimePhase: String, Equatable {
        case waiting
        case probing
        case confirmedActive
    }

    enum SmartFrequentActivationEvidenceKind: String, Equatable {
        case regionExit
        case trustedGPSSpeed
        case trustedDerivedSpeed
        case insufficient
    }

    struct SmartFrequentActivationEvidence: Equatable {
        let kind: SmartFrequentActivationEvidenceKind
        let speedKmh: Double?
        let distanceMeters: CLLocationDistance?
        let elapsedSeconds: TimeInterval?
        let speedAccuracyMetersPerSecond: CLLocationSpeedAccuracy?
        let reason: String

        var activates: Bool {
            kind != .insufficient
        }

        static func regionExit(radiusMeters: CLLocationDistance) -> SmartFrequentActivationEvidence {
            SmartFrequentActivationEvidence(
                kind: .regionExit,
                speedKmh: nil,
                distanceMeters: radiusMeters,
                elapsedSeconds: nil,
                speedAccuracyMetersPerSecond: nil,
                reason: "Exited Smart wake region."
            )
        }

        static func insufficient(_ reason: String,
                                 speedKmh: Double? = nil,
                                 distanceMeters: CLLocationDistance? = nil,
                                 elapsedSeconds: TimeInterval? = nil,
                                 speedAccuracyMetersPerSecond: CLLocationSpeedAccuracy? = nil) -> SmartFrequentActivationEvidence {
            SmartFrequentActivationEvidence(
                kind: .insufficient,
                speedKmh: speedKmh,
                distanceMeters: distanceMeters,
                elapsedSeconds: elapsedSeconds,
                speedAccuracyMetersPerSecond: speedAccuracyMetersPerSecond,
                reason: reason
            )
        }
    }

    enum TrackingApplicationStateContext: Equatable {
        case current
        case forceForeground
        case forceBackground
    }

    enum TrackingReconcileAction: String, Equatable {
        case stopTrackingDisabled
        case stopDeviceKeyBlocked
        case stopAuthorizationUnavailable
        case startTracking
        case applyTrackingMode
    }

    enum PrimaryLocationServiceCommand: Equatable {
        case stopUpdatingLocation
        case stopMonitoringSignificantLocationChanges
        case startMonitoringSignificantLocationChanges
        case startUpdatingLocation(allowsBackground: Bool, distanceFilter: CLLocationDistance, desiredAccuracy: CLLocationAccuracy)
    }

    enum SecondaryLocationServiceCommand: Equatable {
        case stopUpdatingLocation
        case stopMonitoringSignificantLocationChanges
        case startUpdatingLocation(allowsBackground: Bool, distanceFilter: CLLocationDistance, desiredAccuracy: CLLocationAccuracy)
    }

    struct LocationServiceCommandPlan: Equatable {
        let primary: [PrimaryLocationServiceCommand]
        let secondary: [SecondaryLocationServiceCommand]
    }

    struct SignificantChangeRearmDecision: Equatable {
        let shouldAttempt: Bool
        let status: LocationSignificantChangeRearmStatus
    }

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

    struct LocationSubmissionDeduplicationKey: Equatable {
        let timestampSeconds: Int64
        let latitudeMicrodegrees: Int64
        let longitudeMicrodegrees: Int64
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
        // Load persisted background update metrics
        if userDefaults.object(forKey: backgroundUpdateCountKey) != nil {
            backgroundUpdateCount = userDefaults.integer(forKey: backgroundUpdateCountKey)
        }
        locationUpdateModeCounts = LocationUpdateModeCounts(
            foregroundLive: userDefaults.integer(forKey: foregroundLiveUpdateCountKey),
            significantChange: userDefaults.integer(forKey: significantChangeUpdateCountKey),
            smartFrequent: userDefaults.integer(forKey: smartFrequentUpdateCountKey),
            manualFrequent: userDefaults.integer(forKey: manualFrequentUpdateCountKey)
        )
        if let savedDate = userDefaults.object(forKey: lastBackgroundUpdateKey) as? Date {
            lastBackgroundUpdate = savedDate
        }
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

    static func backgroundUpdateConfiguration(frequentUpdatesEnabled: Bool,
                                              distanceFilterMeters: Int) -> BackgroundUpdateConfiguration {
        guard frequentUpdatesEnabled else {
            return BackgroundUpdateConfiguration(
                usesSignificantChangeMonitoring: true,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyHundredMeters
            )
        }

        let normalizedDistance = FrequentBackgroundLocationDistanceFilter.normalized(distanceFilterMeters)
        return BackgroundUpdateConfiguration(
            usesSignificantChangeMonitoring: false,
            distanceFilter: CLLocationDistance(normalizedDistance),
            desiredAccuracy: backgroundDesiredAccuracy(for: normalizedDistance)
        )
    }

    private static func backgroundDesiredAccuracy(for distanceFilterMeters: Int) -> CLLocationAccuracy {
        distanceFilterMeters <= 50 ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyHundredMeters
    }

    static func effectiveFrequentBackgroundUpdatesEnabled(manualFrequentEnabled: Bool,
                                                          smartEnabled: Bool,
                                                          smartRuntimeActive: Bool) -> Bool {
        manualFrequentEnabled || (smartEnabled && smartRuntimeActive)
    }

    static func shouldShowBackgroundLocationIndicator(for mode: TrackingMode) -> Bool {
        if case .backgroundFrequent = mode {
            return true
        }
        return false
    }

    static func locationUpdateCounterMode(applicationState: UIApplication.State,
                                          manualFrequentEnabled: Bool,
                                          smartEnabled: Bool,
                                          smartRuntimeActive: Bool) -> LocationUpdateCounterMode {
        guard applicationState != .active else {
            return .foregroundLive
        }
        if manualFrequentEnabled {
            return .manualFrequent
        }
        if smartEnabled && smartRuntimeActive {
            return .smartFrequent
        }
        return .significantChange
    }

    static func backgroundTrackingDisplayMode(applicationState: UIApplication.State,
                                              smartEnabled: Bool,
                                              manualFrequentEnabled: Bool,
                                              smartRuntimeActive: Bool) -> BackgroundTrackingDisplayMode {
        guard applicationState != .active else {
            return .foregroundLive
        }
        if manualFrequentEnabled {
            return .manualFrequent
        }
        if smartEnabled && smartRuntimeActive {
            return .smartFrequent
        }
        if smartEnabled {
            return .smartWaiting
        }
        return .significantChange
    }

    static func shouldResetLocationUpdateMetrics(now: Date,
                                                 lastReset: Date?,
                                                 interval: TimeInterval = 24 * 60 * 60) -> Bool {
        guard let lastReset else { return false }
        return now.timeIntervalSince(lastReset) >= interval
    }

    static func resolvedTrackingMode(isTracking: Bool,
                                     authorizationStatus: CLAuthorizationStatus,
                                     applicationState: UIApplication.State,
                                     frequentUpdatesEnabled: Bool,
                                     distanceFilterMeters: Int,
                                     hasNavigationLocationSession: Bool) -> TrackingMode {
        guard isTracking else { return .stopped }

        switch authorizationStatus {
        case .authorizedAlways:
            break
        case .authorizedWhenInUse:
            return applicationState == .active ? .foregroundHighAccuracy : .stopped
        default:
            return .stopped
        }

        if applicationState == .active {
            if hasNavigationLocationSession {
                return .foregroundHighAccuracy
            }
            return .foregroundHighAccuracy
        }

        let configuration = backgroundUpdateConfiguration(
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            distanceFilterMeters: distanceFilterMeters
        )
        if configuration.usesSignificantChangeMonitoring {
            return .backgroundSignificantChange
        }
        return .backgroundFrequent(
            distanceFilter: configuration.distanceFilter,
            desiredAccuracy: configuration.desiredAccuracy
        )
    }

    static func effectiveApplicationStateForTracking(currentState: UIApplication.State,
                                                     context: TrackingApplicationStateContext) -> UIApplication.State {
        switch context {
        case .current:
            return currentState
        case .forceForeground:
            return .active
        case .forceBackground:
            return .background
        }
    }

    static func batteryPercent(from batteryLevel: Float) -> Int? {
        guard batteryLevel >= 0, batteryLevel.isFinite else { return nil }
        return Int((Double(batteryLevel) * 100).rounded(.down))
    }

    static func processableLocationUpdates(from locations: [CLLocation]) -> [CLLocation] {
        locations
            .enumerated()
            .filter { _, location in
                let coordinate = location.coordinate
                return coordinate.latitude.isFinite &&
                coordinate.longitude.isFinite &&
                CLLocationCoordinate2DIsValid(coordinate) &&
                location.timestamp.timeIntervalSince1970.isFinite
            }
            .sorted { lhs, rhs in
                let lhsTimestamp = lhs.element.timestamp
                let rhsTimestamp = rhs.element.timestamp
                if lhsTimestamp == rhsTimestamp {
                    return lhs.offset < rhs.offset
                }
                return lhsTimestamp < rhsTimestamp
            }
            .map(\.element)
    }

    static func shouldUsePersistedSmartFrequentBackgroundSeed(now: Date,
                                                             seedTimestamp: Date,
                                                             inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0,
              now.timeIntervalSince1970.isFinite,
              seedTimestamp.timeIntervalSince1970.isFinite else {
            return false
        }

        let age = now.timeIntervalSince(seedTimestamp)
        return age >= 0 && age < inactivityWindow
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
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard latitude.isFinite,
              longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate),
              horizontalAccuracy.isFinite,
              horizontalAccuracy >= 0,
              shouldUsePersistedSmartFrequentBackgroundSeed(
                now: now,
                seedTimestamp: timestamp,
                inactivityWindow: inactivityWindow
              ) else {
            return nil
        }

        return CLLocation(
            coordinate: coordinate,
            altitude: altitude.isFinite ? altitude : 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy.isFinite ? verticalAccuracy : -1,
            course: course.isFinite ? course : -1,
            speed: speed.isFinite ? speed : -1,
            timestamp: timestamp
        )
    }

    static func smartFrequentBackgroundSpeedKmh(for location: CLLocation,
                                                previousLocation: CLLocation?,
                                                detectionMode: SmartFrequentBackgroundSpeedDetectionMode) -> Double? {
        if location.speed >= 0, location.speed.isFinite {
            return location.speed * 3.6
        }

        guard detectionMode == .hybrid,
              let previousLocation,
              isUsableForSmartDerivedSpeed(location),
              isUsableForSmartDerivedSpeed(previousLocation) else {
            return nil
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsed > 0, elapsed <= 30 * 60 else {
            return nil
        }

        let distance = location.distance(from: previousLocation)
        guard distance.isFinite, distance >= 0 else {
            return nil
        }

        return (distance / elapsed) * 3.6
    }

    static func smartFrequentExitFenceRadius(frequentDistanceFilterMeters: Int,
                                             maximumRegionMonitoringDistance: CLLocationDistance) -> CLLocationDistance {
        let desiredRadius = max(
            defaultSmartFrequentExitFenceRadius,
            CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        )
        guard maximumRegionMonitoringDistance.isFinite,
              maximumRegionMonitoringDistance > 0 else {
            return desiredRadius
        }
        return min(desiredRadius, maximumRegionMonitoringDistance)
    }

    static func shouldMaintainSmartFrequentExitFence(trackAndReportLocation: Bool,
                                                     isTracking: Bool,
                                                     authorizationStatus: CLAuthorizationStatus,
                                                     deviceKeyAuthBlocked: Bool,
                                                     smartEnabled: Bool,
                                                     manualFrequentEnabled: Bool,
                                                     smartRuntimeActive: Bool,
                                                     regionMonitoringAvailable: Bool) -> Bool {
        trackAndReportLocation &&
        isTracking &&
        authorizationStatus == .authorizedAlways &&
        !deviceKeyAuthBlocked &&
        smartEnabled &&
        !manualFrequentEnabled &&
        !smartRuntimeActive &&
        regionMonitoringAvailable
    }

    static func smartFrequentActivationEvidence(for location: CLLocation,
                                                previousLocation: CLLocation?,
                                                detectionMode: SmartFrequentBackgroundSpeedDetectionMode,
                                                thresholdKmh: Int,
                                                frequentDistanceFilterMeters: Int,
                                                isStartupBatch: Bool,
                                                regionExitRadiusMeters: CLLocationDistance? = nil) -> SmartFrequentActivationEvidence {
        if let regionExitRadiusMeters {
            return .regionExit(radiusMeters: regionExitRadiusMeters)
        }

        let normalizedThreshold = Double(SmartFrequentBackgroundSpeedThreshold.normalized(thresholdKmh))
        let gpsSpeedKmh = gpsSmartFrequentSpeedKmh(for: location)
        let displacement = smartFrequentDisplacementEvidence(
            from: previousLocation,
            to: location,
            frequentDistanceFilterMeters: frequentDistanceFilterMeters
        )

        if let gpsSpeedKmh,
           gpsSpeedKmh >= normalizedThreshold,
           gpsSpeedKmh <= maximumSmartFrequentActivationSpeedKmh {
            let speedAccuracy = location.speedAccuracy
            let speedAccuracyTrusted = speedAccuracy.isFinite &&
            speedAccuracy >= 0 &&
            speedAccuracy <= maximumTrustedSmartFrequentSpeedAccuracyMetersPerSecond

            if speedAccuracyTrusted && (!isStartupBatch || displacement.isTrusted) {
                return SmartFrequentActivationEvidence(
                    kind: .trustedGPSSpeed,
                    speedKmh: gpsSpeedKmh,
                    distanceMeters: displacement.distanceMeters,
                    elapsedSeconds: displacement.elapsedSeconds,
                    speedAccuracyMetersPerSecond: speedAccuracy,
                    reason: "GPS speed accuracy is trusted."
                )
            }

            if !isStartupBatch && displacement.isTrusted {
                return SmartFrequentActivationEvidence(
                    kind: .trustedGPSSpeed,
                    speedKmh: gpsSpeedKmh,
                    distanceMeters: displacement.distanceMeters,
                    elapsedSeconds: displacement.elapsedSeconds,
                    speedAccuracyMetersPerSecond: speedAccuracy.isFinite ? speedAccuracy : nil,
                    reason: "GPS speed was confirmed by displacement."
                )
            }
        }

        guard detectionMode == .hybrid,
              let derivedSpeedKmh = displacement.speedKmh else {
            return .insufficient(
                "No trusted Smart activation evidence.",
                speedKmh: gpsSpeedKmh,
                distanceMeters: displacement.distanceMeters,
                elapsedSeconds: displacement.elapsedSeconds,
                speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil
            )
        }

        guard derivedSpeedKmh >= normalizedThreshold,
              derivedSpeedKmh <= maximumSmartFrequentActivationSpeedKmh,
              displacement.isTrusted else {
            return .insufficient(
                "Derived speed or displacement did not pass Smart quality thresholds.",
                speedKmh: derivedSpeedKmh,
                distanceMeters: displacement.distanceMeters,
                elapsedSeconds: displacement.elapsedSeconds,
                speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil
            )
        }

        return SmartFrequentActivationEvidence(
            kind: .trustedDerivedSpeed,
            speedKmh: derivedSpeedKmh,
            distanceMeters: displacement.distanceMeters,
            elapsedSeconds: displacement.elapsedSeconds,
            speedAccuracyMetersPerSecond: location.speedAccuracy.isFinite ? location.speedAccuracy : nil,
            reason: "Derived speed is backed by trusted displacement."
        )
    }

    private struct SmartFrequentDisplacementEvidence {
        let distanceMeters: CLLocationDistance?
        let elapsedSeconds: TimeInterval?
        let speedKmh: Double?
        let isTrusted: Bool
    }

    private static func gpsSmartFrequentSpeedKmh(for location: CLLocation) -> Double? {
        guard location.speed >= 0,
              location.speed.isFinite else {
            return nil
        }
        return location.speed * 3.6
    }

    private static func smartFrequentDisplacementEvidence(from previousLocation: CLLocation?,
                                                          to location: CLLocation,
                                                          frequentDistanceFilterMeters: Int) -> SmartFrequentDisplacementEvidence {
        guard let previousLocation,
              isUsableForSmartDerivedSpeed(location),
              isUsableForSmartDerivedSpeed(previousLocation) else {
            return SmartFrequentDisplacementEvidence(
                distanceMeters: nil,
                elapsedSeconds: nil,
                speedKmh: nil,
                isTrusted: false
            )
        }

        let elapsed = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        let distance = location.distance(from: previousLocation)
        guard elapsed.isFinite,
              distance.isFinite,
              elapsed >= minimumSmartFrequentDerivedSpeedElapsed,
              elapsed <= 30 * 60,
              distance >= 0 else {
            return SmartFrequentDisplacementEvidence(
                distanceMeters: distance.isFinite ? distance : nil,
                elapsedSeconds: elapsed.isFinite ? elapsed : nil,
                speedKmh: nil,
                isTrusted: false
            )
        }

        let movementThreshold = CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        let combinedAccuracy = max(0, location.horizontalAccuracy) + max(0, previousLocation.horizontalAccuracy)
        let noiseAdjustedThreshold = max(movementThreshold, combinedAccuracy * 1.25)
        let isTrusted = distance >= noiseAdjustedThreshold
        return SmartFrequentDisplacementEvidence(
            distanceMeters: distance,
            elapsedSeconds: elapsed,
            speedKmh: (distance / elapsed) * 3.6,
            isTrusted: isTrusted
        )
    }

    static func shouldActivateSmartFrequentBackgroundUpdates(speedKmh: Double?,
                                                             thresholdKmh: Int) -> Bool {
        guard let speedKmh,
              speedKmh.isFinite,
              speedKmh >= 0,
              speedKmh <= maximumSmartFrequentActivationSpeedKmh else {
            return false
        }
        return speedKmh >= Double(SmartFrequentBackgroundSpeedThreshold.normalized(thresholdKmh))
    }

    static func canActivateSmartFrequentBackgroundUpdates(now: Date,
                                                          locationTimestamp: Date,
                                                          previousLocationUpdateAt: Date?,
                                                          inactivityWindow: TimeInterval,
                                                          evidenceKind: SmartFrequentActivationEvidenceKind = .trustedDerivedSpeed) -> Bool {
        guard inactivityWindow > 0 else { return false }
        guard now.timeIntervalSince(locationTimestamp) < inactivityWindow else {
            return false
        }

        switch evidenceKind {
        case .regionExit, .trustedGPSSpeed:
            return true
        case .trustedDerivedSpeed:
            guard let previousLocationUpdateAt else { return false }
            return now.timeIntervalSince(previousLocationUpdateAt) < inactivityWindow
        case .insufficient:
            return false
        }
    }

    static func shouldDeactivateSmartFrequentBackgroundUpdates(now: Date,
                                                               lastLocationUpdateAt: Date?,
                                                               lastRelevantMovementAt: Date?,
                                                               inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0 else { return true }
        guard let lastRelevantMovementAt else { return false }
        return now.timeIntervalSince(lastRelevantMovementAt) >= inactivityWindow
    }

    static func nextSmartFrequentBackgroundInactivityTimeout(lastLocationUpdateAt: Date?,
                                                             lastRelevantMovementAt: Date?,
                                                             inactivityWindow: TimeInterval) -> Date? {
        guard inactivityWindow > 0 else { return nil }
        return lastRelevantMovementAt?.addingTimeInterval(inactivityWindow)
    }

    static func smartFrequentMovementDistanceThreshold(frequentDistanceFilterMeters: Int,
                                                       from previousLocation: CLLocation?,
                                                       to location: CLLocation) -> CLLocationDistance {
        let movementThreshold = CLLocationDistance(FrequentBackgroundLocationDistanceFilter.normalized(frequentDistanceFilterMeters))
        let accuracyThresholds = [previousLocation?.horizontalAccuracy, location.horizontalAccuracy]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 >= 0 }
        let accuracyNoiseThreshold = accuracyThresholds.max() ?? 0
        return max(movementThreshold, accuracyNoiseThreshold)
    }

    static func shouldConfirmSmartFrequentBackgroundMovement(distanceMeters: CLLocationDistance?,
                                                             thresholdMeters: CLLocationDistance) -> Bool {
        guard let distanceMeters,
              distanceMeters.isFinite,
              thresholdMeters.isFinite,
              thresholdMeters >= 0 else {
            return false
        }
        return distanceMeters >= thresholdMeters
    }

    static func shouldBypassLocationSensitivityForFrequentBackgroundUpload(applicationState: UIApplication.State,
                                                                           updateSourceIsFrequentBackground: Bool,
                                                                           manualFrequentEnabled: Bool,
                                                                           smartRuntimePhase: SmartFrequentRuntimePhase) -> Bool {
        guard applicationState != .active,
              updateSourceIsFrequentBackground else {
            return false
        }

        return manualFrequentEnabled || smartRuntimePhase != .waiting
    }

    private static func isUsableForSmartDerivedSpeed(_ location: CLLocation) -> Bool {
        let coordinate = location.coordinate
        return coordinate.latitude.isFinite &&
        coordinate.longitude.isFinite &&
        location.timestamp.timeIntervalSince1970.isFinite &&
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= 300
    }

    static func shouldDisableFrequentBackgroundUpdatesForBattery(frequentUpdatesEnabled: Bool,
                                                                 batteryPercent: Int?,
                                                                 thresholdPercent: Int) -> Bool {
        guard frequentUpdatesEnabled,
              let batteryPercent else {
            return false
        }

        let normalizedThreshold = FrequentBackgroundBatteryAutoDisableLevel.normalized(thresholdPercent)
        return batteryPercent <= normalizedThreshold
    }

    static func frequentBackgroundLocationDeliveryDelay(applicationState: UIApplication.State,
                                                        frequentUpdatesEnabled: Bool,
                                                        deliveryMode: FrequentBackgroundLocationDeliveryMode) -> TimeInterval? {
        guard applicationState != .active,
              frequentUpdatesEnabled else {
            return nil
        }
        return deliveryMode.delay
    }

    static func frequentBackgroundVisitorCheckMinimumInterval(applicationState: UIApplication.State,
                                                              frequentUpdatesEnabled: Bool,
                                                              visitorCheckInterval: FrequentBackgroundVisitorCheckInterval) -> TimeInterval? {
        guard applicationState != .active,
              frequentUpdatesEnabled else {
            return nil
        }
        return visitorCheckInterval.minimumInterval
    }

    static func shouldMaintainSignificantChangeRecoveryAnchor(trackAndReportLocation: Bool,
                                                              authorizationStatus: CLAuthorizationStatus,
                                                              deviceKeyAuthBlocked: Bool) -> Bool {
        guard trackAndReportLocation,
              !deviceKeyAuthBlocked else {
            return false
        }

        return authorizationStatus == .authorizedAlways
    }

    static func shouldMaintainLocationServiceSession(trackAndReportLocation: Bool,
                                                     isTracking: Bool,
                                                     authorizationStatus: CLAuthorizationStatus,
                                                     deviceKeyAuthBlocked: Bool) -> Bool {
        shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: trackAndReportLocation && isTracking,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked
        )
    }

    static func shouldRestoreTrackingAfterLaunch(trackAndReportLocation: Bool,
                                                  deviceKeyAuthBlocked: Bool) -> Bool {
        trackAndReportLocation && !deviceKeyAuthBlocked
    }

    static func trackingReconcileAction(trackAndReportLocation: Bool,
                                        deviceKeyAuthBlocked: Bool,
                                        authorizationStatus: CLAuthorizationStatus,
                                        isTracking: Bool) -> TrackingReconcileAction {
        guard trackAndReportLocation else {
            return .stopTrackingDisabled
        }
        guard !deviceKeyAuthBlocked else {
            return .stopDeviceKeyBlocked
        }

        if shouldDisableTrackingPreference(authorizationStatus: authorizationStatus) {
            return .stopAuthorizationUnavailable
        }
        return isTracking ? .applyTrackingMode : .startTracking
    }

    static func shouldDisableTrackingPreference(authorizationStatus: CLAuthorizationStatus) -> Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    static func significantChangeRearmDecision(buildIdentifier: String,
                                               alreadyRearmedBuildIdentifier: String?,
                                               reason: String,
                                               trackAndReportLocation: Bool,
                                               authorizationStatus: CLAuthorizationStatus,
                                               deviceKeyAuthBlocked: Bool,
                                               now: Date = Date()) -> SignificantChangeRearmDecision {
        let buildNotRearmed = alreadyRearmedBuildIdentifier != buildIdentifier
        let checks = [
            LocationDiagnosticsLogStore.check(
                "trackingEnabled",
                trackAndReportLocation,
                detail: trackAndReportLocation ? "Location tracking is enabled." : "Location tracking is disabled."
            ),
            LocationDiagnosticsLogStore.check(
                "authorizedAlways",
                authorizationStatus == .authorizedAlways,
                detail: "Authorization status: \(authorizationStatus.rawValue)."
            ),
            LocationDiagnosticsLogStore.check(
                "deviceKeyNotBlocked",
                !deviceKeyAuthBlocked,
                detail: deviceKeyAuthBlocked ? "DeviceKey authentication is blocked." : "DeviceKey authentication is not blocked."
            ),
            LocationDiagnosticsLogStore.check(
                "buildNotRearmed",
                buildNotRearmed,
                detail: buildNotRearmed ? "Build has not been re-armed yet." : "Build was already re-armed."
            )
        ]

        let skipReason: String?
        if !trackAndReportLocation {
            skipReason = "location tracking disabled"
        } else if authorizationStatus != .authorizedAlways {
            skipReason = "Always authorization missing"
        } else if deviceKeyAuthBlocked {
            skipReason = "DeviceKey auth blocked"
        } else if !buildNotRearmed {
            skipReason = "already re-armed for this build"
        } else {
            skipReason = nil
        }

        let status = LocationSignificantChangeRearmStatus(
            timestamp: now,
            buildIdentifier: buildIdentifier,
            result: skipReason == nil ? .attempted : .skipped,
            reason: skipReason ?? reason,
            checks: checks
        )
        return SignificantChangeRearmDecision(
            shouldAttempt: skipReason == nil,
            status: status
        )
    }

    static func shouldMaintainFrequentBackgroundActivitySession(trackAndReportLocation: Bool,
                                                                isTracking: Bool,
                                                                frequentUpdatesEnabled: Bool,
                                                                authorizationStatus: CLAuthorizationStatus,
                                                                deviceKeyAuthBlocked: Bool) -> Bool {
        trackAndReportLocation &&
        isTracking &&
        frequentUpdatesEnabled &&
        authorizationStatus == .authorizedAlways &&
        !deviceKeyAuthBlocked
    }

    static func locationServiceCommandPlan(for mode: TrackingMode,
                                           shouldMaintainRecoveryAnchor: Bool) -> LocationServiceCommandPlan {
        let secondaryStopCommands: [SecondaryLocationServiceCommand] = [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ]

        switch mode {
        case .stopped:
            return LocationServiceCommandPlan(
                primary: [.stopUpdatingLocation, .stopMonitoringSignificantLocationChanges],
                secondary: secondaryStopCommands
            )
        case .foregroundHighAccuracy:
            let foregroundPrimaryCommands: [PrimaryLocationServiceCommand] = [
                shouldMaintainRecoveryAnchor ? .startMonitoringSignificantLocationChanges : .stopMonitoringSignificantLocationChanges,
                .startUpdatingLocation(
                    allowsBackground: false,
                    distanceFilter: kCLDistanceFilterNone,
                    desiredAccuracy: kCLLocationAccuracyBestForNavigation
                )
            ]
            return LocationServiceCommandPlan(
                primary: foregroundPrimaryCommands,
                secondary: secondaryStopCommands
            )
        case .backgroundSignificantChange:
            return LocationServiceCommandPlan(
                primary: [.stopUpdatingLocation, .startMonitoringSignificantLocationChanges],
                secondary: secondaryStopCommands
            )
        case .backgroundFrequent(let distanceFilter, let desiredAccuracy):
            return LocationServiceCommandPlan(
                primary: [
                    .stopUpdatingLocation,
                    shouldMaintainRecoveryAnchor ? .startMonitoringSignificantLocationChanges : .stopMonitoringSignificantLocationChanges
                ],
                secondary: [
                    .stopMonitoringSignificantLocationChanges,
                    .startUpdatingLocation(
                        allowsBackground: true,
                        distanceFilter: distanceFilter,
                        desiredAccuracy: desiredAccuracy
                    )
                ]
            )
        }
    }

    static func locationSubmissionDeduplicationKey(for location: CLLocation) -> LocationSubmissionDeduplicationKey? {
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let timestamp = location.timestamp.timeIntervalSince1970
        guard latitude.isFinite,
              longitude.isFinite,
              timestamp.isFinite else {
            return nil
        }

        return LocationSubmissionDeduplicationKey(
            timestampSeconds: Int64(timestamp.rounded(.down)),
            latitudeMicrodegrees: Int64((latitude * 1_000_000).rounded()),
            longitudeMicrodegrees: Int64((longitude * 1_000_000).rounded())
        )
    }

    static func shouldSubmitLocationForUpload(_ location: CLLocation,
                                              lastSubmittedKey: LocationSubmissionDeduplicationKey?) -> Bool {
        guard let candidateKey = locationSubmissionDeduplicationKey(for: location),
              let lastSubmittedKey else {
            return true
        }

        return candidateKey != lastSubmittedKey
    }

    static func backgroundTrackingGapAssessment(
        state: BackgroundTrackingForensicState,
        now: Date,
        frequentThreshold: TimeInterval = forensicFrequentBackgroundGapThreshold
    ) -> BackgroundTrackingGapAssessment? {
        guard let expectedSince = state.backgroundTrackingExpectedSince,
              let expectedMode = state.currentExpectedMode else {
            return nil
        }

        let lastObservedAt = [state.lastBackgroundCallbackAt, state.lastBackgroundUploadAt]
            .compactMap { $0 }
            .max()
        let referenceDate = lastObservedAt ?? expectedSince
        let gapSeconds = Int(now.timeIntervalSince(referenceDate).rounded(.down))
        guard gapSeconds >= Int(frequentThreshold) else {
            return nil
        }

        if expectedMode.localizedCaseInsensitiveContains("frequent") {
            return BackgroundTrackingGapAssessment(
                kind: .suspicious,
                gapSeconds: gapSeconds,
                lastObservedAt: lastObservedAt
            )
        }

        return BackgroundTrackingGapAssessment(
            kind: .unobservedIdle,
            gapSeconds: gapSeconds,
            lastObservedAt: lastObservedAt
        )
    }

    static func shouldLogForegroundRecoveryBurst(foregroundOpenedAt: Date?,
                                                 recoveryAlreadyLoggedAt: Date?,
                                                 now: Date,
                                                 acceptedCount: Int,
                                                 uploadCount: Int,
                                                 window: TimeInterval = forensicForegroundRecoveryBurstWindow) -> Bool {
        guard recoveryAlreadyLoggedAt == nil,
              let foregroundOpenedAt,
              now.timeIntervalSince(foregroundOpenedAt) >= 0,
              now.timeIntervalSince(foregroundOpenedAt) <= window else {
            return false
        }
        return acceptedCount > 0 || uploadCount > 0
    }

    static func frequentBackgroundModeSwitchReason(didExpire: Bool,
                                                   didDisableForBattery: Bool) -> String {
        if didDisableForBattery {
            return "frequent background battery auto-disable during location update"
        }
        if didExpire {
            return "frequent background expired during location update"
        }
        return "frequent background mode changed during location update"
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
        updateSourceIsPrimary &&
        applicationState != .active &&
        frequentUpdatesEnabled &&
        !didSwitchFrequentBackgroundMode &&
        frequentBackgroundStandardUpdatesActiveInCurrentProcess
    }

    static func shouldCleanUpStaleFrequentBackgroundCallback(frequentUpdatesEnabled: Bool,
                                                             didSwitchFrequentBackgroundMode: Bool,
                                                             updateSourceIsFrequentBackground: Bool) -> Bool {
        updateSourceIsFrequentBackground &&
        !frequentUpdatesEnabled &&
        !didSwitchFrequentBackgroundMode
    }

    static func shouldSuppressStaleFrequentBackgroundCallback(allowNextStaleCallback: Bool) -> Bool {
        !allowNextStaleCallback
    }

    static func shouldReassertStandardSignificantChangeAfterPrimaryCallback(
        applicationState: UIApplication.State,
        frequentUpdatesEnabled: Bool,
        didSwitchFrequentBackgroundMode: Bool,
        shouldMaintainRecoveryAnchor: Bool,
        updateSourceIsPrimary: Bool
    ) -> Bool {
        updateSourceIsPrimary &&
        applicationState != .active &&
        !frequentUpdatesEnabled &&
        !didSwitchFrequentBackgroundMode &&
        shouldMaintainRecoveryAnchor
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
        handleSmartFrequentBackgroundInactivityIfNeeded()
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
        [latestRawLocation, currentLocation, smartFrequentBackgroundSpeedReferenceLocation]
            .compactMap { $0 }
            .first { Self.isUsableForSmartFenceAnchor($0) }
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
        guard applicationState != .active,
              settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            if settings.frequentBackgroundLocationUpdatesEnabled,
               smartFrequentBackgroundRuntimeActive {
                deactivateSmartFrequentBackgroundRuntime(reason: "manual frequent override")
                return true
            }
            updateSmartFrequentBackgroundSpeedReference(with: location)
            return false
        }

        let didDeactivateForInactivity = handleSmartFrequentBackgroundInactivityIfNeeded(now: now)
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
              applicationState != .active else {
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
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil
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
    private func deactivateSmartFrequentBackgroundRuntime(reason: String) -> Bool {
        let wasActive = smartFrequentBackgroundRuntimeActive
        let shouldNotifyDeactivation = wasActive && smartFrequentBackgroundActivationNotificationDelivered
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
    private func handleSmartFrequentBackgroundInactivityIfNeeded(now: Date = Date()) -> Bool {
        guard settings.smartFrequentBackgroundLocationUpdatesEnabled,
              smartFrequentBackgroundRuntimeActive,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            scheduleSmartFrequentBackgroundInactivityTimer(now: now)
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
            if handleSmartFrequentBackgroundInactivityIfNeeded(now: now), isTracking {
                applyTrackingMode(reason: "smart frequent inactivity timer")
            }
            return
        }

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.handleSmartFrequentBackgroundInactivityIfNeeded(), self.isTracking {
                self.applyTrackingMode(reason: "smart frequent inactivity timer")
            }
        }
        smartFrequentBackgroundInactivityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: Date = Date()) {
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil

        guard smartFrequentBackgroundRuntimePhase == .probing,
              settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            return
        }

        let timer = Timer(timeInterval: Self.smartFrequentBackgroundProbeWatchdogInterval, repeats: false) { [weak self] _ in
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
        if smartFrequentBackgroundRuntimePhase == .probing {
            scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
        }
    }

    private func handleSmartFrequentBackgroundWatchdog(now: Date = Date()) {
        smartFrequentBackgroundWatchdogTimer?.invalidate()
        smartFrequentBackgroundWatchdogTimer = nil

        guard smartFrequentBackgroundRuntimePhase == .probing,
              settings.smartFrequentBackgroundLocationUpdatesEnabled,
              !settings.frequentBackgroundLocationUpdatesEnabled else {
            return
        }

        let probeReference = smartFrequentBackgroundLastFrequentCallbackAt ?? smartFrequentBackgroundProbeStartedAt ?? now
        if now.timeIntervalSince(probeReference) < Self.smartFrequentBackgroundProbeWatchdogInterval {
            scheduleSmartFrequentBackgroundWatchdogIfNeeded(now: now)
            return
        }

        guard smartFrequentBackgroundRecoveryAttemptCount < Self.maximumSmartFrequentBackgroundProbeRecoveryAttempts else {
            let didDeactivate = deactivateSmartFrequentBackgroundRuntime(reason: "smart frequent recovery watchdog exhausted")
            if didDeactivate, isTracking {
                applyTrackingMode(reason: "smart frequent recovery watchdog exhausted", applicationStateContext: .forceBackground)
            }
            return
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
                "maximumAttempts": .integer(Self.maximumSmartFrequentBackgroundProbeRecoveryAttempts),
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
        guard let payload = sanitizedPayload(from: location) else {
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
        }
        let applicationState = UIApplication.shared.applicationState
        let deliveryDelay = frequentBackgroundLocationDeliveryDelay(for: applicationState)
        let visitorCheckMinimumInterval = frequentBackgroundVisitorCheckMinimumInterval(for: applicationState)
        let backgroundTask = beginLocationUploadBackgroundTaskIfNeeded(for: applicationState)
        self.serverUpdateStatus = .updating
        defer {
            backgroundTask?.end()
        }

        let result = await locationUpdateDeliveryCoordinator.submit(
            serverURL: serverURL,
            payload: payload,
            enableHistory: settings.saveLocationHistoryOnServer,
            retentionTime: settings.locationDataRetentionTime,
            deliveryDelay: deliveryDelay,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval
        )

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
        guard let apiError = error as? MiataruAPIClient.APIError else {
            let nsError = error as NSError
            return "\(nsError.domain)#\(nsError.code)"
        }

        switch apiError {
        case .invalidURL:
            return "invalidURL"
        case .invalidResponse(let response):
            if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                return "invalidResponse#\(statusCode)"
            }
            return "invalidResponse"
        case .encodingError(let underlyingError):
            let nsError = underlyingError as NSError
            return "encodingError#\(nsError.domain)#\(nsError.code)"
        case .decodingError(let underlyingError):
            let nsError = underlyingError as NSError
            return "decodingError#\(nsError.domain)#\(nsError.code)"
        case .requestFailed(let underlyingError):
            let nsError = underlyingError as NSError
            return "requestFailed#\(nsError.domain)#\(nsError.code)"
        case .serverError(let statusCode, _):
            return "serverError#\(statusCode)"
        }
    }

    @MainActor
    private func beginLocationUploadBackgroundTaskIfNeeded(for applicationState: UIApplication.State) -> LocationBackgroundTaskToken? {
        guard applicationState != .active else { return nil }
        return LocationBackgroundTaskToken(name: "MiataruLocationUpdate")
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

    // MARK: - 24h diagnostics reset
    private func maybeResetBackgroundMetricsIfNeeded(now: Date = Date()) {
        let lastReset = userDefaults.object(forKey: backgroundMetricsLastResetKey) as? Date
        guard let lastReset else {
            userDefaults.set(now, forKey: backgroundMetricsLastResetKey)
            return
        }

        guard Self.shouldResetLocationUpdateMetrics(now: now, lastReset: lastReset) else {
            return
        }

        backgroundUpdateCount = 0
        locationUpdateModeCounts = .zero
        persistLocationUpdateModeCounts()
        userDefaults.set(0, forKey: backgroundUpdateCountKey)
        userDefaults.set(now, forKey: backgroundMetricsLastResetKey)
    }

    private func recordLocationUpdateMetric(mode: LocationUpdateCounterMode, now: Date = Date()) {
        maybeResetBackgroundMetricsIfNeeded(now: now)
        locationUpdateModeCounts.increment(mode)
        if mode != .foregroundLive {
            lastBackgroundUpdate = now
            backgroundUpdateCount = locationUpdateModeCounts.backgroundTotal
            userDefaults.set(backgroundUpdateCount, forKey: backgroundUpdateCountKey)
            userDefaults.set(now, forKey: lastBackgroundUpdateKey)
        }
        persistLocationUpdateModeCounts()
    }

    private func persistLocationUpdateModeCounts() {
        userDefaults.set(locationUpdateModeCounts.foregroundLive, forKey: foregroundLiveUpdateCountKey)
        userDefaults.set(locationUpdateModeCounts.significantChange, forKey: significantChangeUpdateCountKey)
        userDefaults.set(locationUpdateModeCounts.smartFrequent, forKey: smartFrequentUpdateCountKey)
        userDefaults.set(locationUpdateModeCounts.manualFrequent, forKey: manualFrequentUpdateCountKey)
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
            self.recordSmartFrequentBackgroundFrequentCallbackIfNeeded(updateSource: updateSource)
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
                let didSwitchSmartFrequentBackgroundMode = self.updateSmartFrequentBackgroundRuntime(
                    for: location,
                    updateSource: updateSource,
                    applicationState: applicationState,
                    isStartupBatch: isSmartFrequentStartupBatch
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
           location.speed >= headingMinSpeedThreshold {
            userHeading = smoothHeading(normalizedHeading(location.course))
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
            isHeadingValid = accuracy <= headingAccuracyThreshold
            let headingReferenceLocation = latestRawLocation ?? currentLocation
            if isHeadingValid {
                let rawHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
                let blended = blendedHeading(
                    compass: rawHeading,
                    course: headingReferenceLocation?.course,
                    speed: headingReferenceLocation?.speed
                )
                userHeading = smoothHeading(blended)
            } else if let course = headingReferenceLocation?.course,
                      let speed = headingReferenceLocation?.speed,
                      course >= 0,
                      speed >= headingMinSpeedThreshold {
                // Fallback to smoothed course when compass quality is poor.
                userHeading = smoothHeading(normalizedHeading(course))
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
