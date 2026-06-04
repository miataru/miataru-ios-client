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
    @Published private(set) var smartFrequentBackgroundLastActivationReason: String?
    @Published private(set) var smartFrequentBackgroundLastRelevantMovementAt: Date?
    @Published private(set) var smartFrequentBackgroundNextInactivityTimeoutAt: Date?
    
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
    private var cancellables = Set<AnyCancellable>()
    private let settings = SettingsManager.shared
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
    private var lastSmoothedHeading: Double?
    private let headingSmoothingAlpha: Double = 0.25
    private let headingAccuracyThreshold: Double = 35
    private let headingMinSpeedThreshold: Double = 1.0
    
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

    enum TrackingApplicationStateContext: Equatable {
        case current
        case forceForeground
        case forceBackground
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

    private enum LocationUpdateSource: String {
        case primary
        case frequentBackground
        case unknown
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
        // Update authorization status (in case it changed while app was in background)
        let currentStatus = locationManager.authorizationStatus
        self.authorizationStatus = currentStatus
        
        // If permission is denied/restricted but toggle is on, update it
        if (currentStatus == .denied || currentStatus == .restricted) && settings.trackAndReportLocation {
            debugLog("Permission still denied/restricted after returning from Settings, setting trackAndReportLocation to false")
            settings.trackAndReportLocation = false
        }
        
        // Re-check permission escalation / first-time prompt if needed
        handleFrequentBackgroundLocationExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()
        ensureAuthorizationIfNeeded()
        if !isTracking,
           settings.trackAndReportLocation,
           !settings.deviceKeyAuthBlocked {
            startTracking()
        } else if isTracking {
            applyTrackingMode(reason: "app did become active")
        }
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

    static func shouldActivateSmartFrequentBackgroundUpdates(speedKmh: Double?,
                                                             thresholdKmh: Int) -> Bool {
        guard let speedKmh, speedKmh.isFinite else {
            return false
        }
        return speedKmh >= Double(SmartFrequentBackgroundSpeedThreshold.normalized(thresholdKmh))
    }

    static func canActivateSmartFrequentBackgroundUpdates(now: Date,
                                                          locationTimestamp: Date,
                                                          previousLocationUpdateAt: Date?,
                                                          inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0 else { return false }
        guard now.timeIntervalSince(locationTimestamp) < inactivityWindow else {
            return false
        }
        if let previousLocationUpdateAt,
           now.timeIntervalSince(previousLocationUpdateAt) >= inactivityWindow {
            return false
        }
        return true
    }

    static func shouldDeactivateSmartFrequentBackgroundUpdates(now: Date,
                                                               lastLocationUpdateAt: Date?,
                                                               lastRelevantMovementAt: Date?,
                                                               inactivityWindow: TimeInterval) -> Bool {
        guard inactivityWindow > 0 else { return true }
        if let lastLocationUpdateAt {
            if now.timeIntervalSince(lastLocationUpdateAt) >= inactivityWindow {
                return true
            }
        }
        if let lastRelevantMovementAt {
            if now.timeIntervalSince(lastRelevantMovementAt) >= inactivityWindow {
                return true
            }
        }
        return false
    }

    static func nextSmartFrequentBackgroundInactivityTimeout(lastLocationUpdateAt: Date?,
                                                             lastRelevantMovementAt: Date?,
                                                             inactivityWindow: TimeInterval) -> Date? {
        let candidates = [lastLocationUpdateAt, lastRelevantMovementAt]
            .compactMap { $0?.addingTimeInterval(inactivityWindow) }
        return candidates.min()
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
    func startTracking() {
        debugLog("startTracking called")
        if settings.deviceKeyAuthBlocked {
            debugLog("startTracking blocked due to DeviceKey auth failure")
            isTracking = false
            stopAllLocationServices()
            return
        }
        ensureAuthorizationIfNeeded()
        isTracking = true
        handleFrequentBackgroundLocationExpirationIfNeeded()
        applyTrackingMode(reason: "start tracking")
    }

    func restoreTrackingAfterLaunch(reason: String, applicationStateContext: TrackingApplicationStateContext = .current) {
        debugLog("[LocationManager] Restoring tracking after launch: \(reason)")
        authorizationStatus = locationManager.authorizationStatus
        handleFrequentBackgroundLocationExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()

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
        debugLog("[LocationManager] restoreTrackingAfterLaunch reason=\(reason), status=\(authorizationStatus.rawValue), frequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), context=\(applicationStateContext)")
        applyTrackingMode(reason: "restore tracking after launch: \(reason)", applicationStateContext: applicationStateContext)
        refreshPendingLocationUpdateCount()
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

        if status == .denied || status == .restricted {
            if settings.trackAndReportLocation {
                debugLog("Location permission denied/restricted, setting trackAndReportLocation to false")
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
        debugLog("[LocationManager] applyTrackingMode reason=\(reason), context=\(applicationStateContext), state=\(state.rawValue), status=\(status.rawValue), isTracking=\(isTracking), navigationSessions=\(navigationLocationSessionIDs.count), manualFrequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), smartEnabled=\(settings.smartFrequentBackgroundLocationUpdatesEnabled), smartRuntimeActive=\(smartFrequentBackgroundRuntimeActive), effectiveFrequent=\(effectiveFrequentBackgroundUpdatesEnabled), expiresAt=\(String(describing: settings.frequentBackgroundLocationUpdatesExpiresAt)), primaryRecoveryAnchorActive=\(isSignificantChangeRecoveryAnchorActive), mode=\(mode), commandPlan=\(commandPlan)")
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
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        locationManager.stopUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        stopFrequentBackgroundStandardUpdates()
        stopHeadingUpdates()
        stopForegroundLocationTimer()
    }

    private func startFrequentBackgroundLocationUpdates(configuration: BackgroundUpdateConfiguration) {
        debugLog("Starting frequent background updates with distanceFilter=\(configuration.distanceFilter)m")
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

    private func shouldSuppressAfterCleaningUpStaleFrequentBackgroundCallbackIfNeeded(
        updateSource: LocationUpdateSource,
        didSwitchFrequentBackgroundMode: Bool,
        applicationState: UIApplication.State
    ) -> Bool {
        guard Self.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: effectiveFrequentBackgroundUpdatesEnabled,
            didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
            updateSourceIsFrequentBackground: updateSource == .frequentBackground
        ) else { return false }

        let shouldSuppressCallback = Self.shouldSuppressStaleFrequentBackgroundCallback(
            allowNextStaleCallback: shouldAllowNextStaleFrequentBackgroundCallback
        )
        shouldAllowNextStaleFrequentBackgroundCallback = false

        let handling = shouldSuppressCallback ? "suppressing repeated stale location" : "location remains eligible for upload"
        debugLog("[LocationManager] Cleaning up stale frequent background callback while frequent mode is disabled; \(handling)")
        stopFrequentBackgroundStandardUpdates()
        stopFrequentBackgroundActivitySession(reason: "stale frequent background callback")

        if isTracking, applicationState != .active {
            applyTrackingMode(reason: "stale frequent background callback cleanup", applicationStateContext: .forceBackground)
        }
        return shouldSuppressCallback
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
        let speedKmh = Self.smartFrequentBackgroundSpeedKmh(
            for: location,
            previousLocation: smartFrequentBackgroundSpeedReferenceLocation,
            detectionMode: settings.smartFrequentBackgroundSpeedDetectionModeSelection
        )
        updateSmartFrequentBackgroundSpeedReference(with: location)

        guard !smartFrequentBackgroundRuntimeActive else {
            if didUpdateMovement {
                scheduleSmartFrequentBackgroundInactivityTimer(now: now)
            }
            return didDeactivateForInactivity
        }

        guard updateSource == .primary,
              Self.canActivateSmartFrequentBackgroundUpdates(
                now: now,
                locationTimestamp: location.timestamp,
                previousLocationUpdateAt: previousLocationUpdateAt,
                inactivityWindow: settings.smartFrequentBackgroundInactivityWindowSelection.timeInterval
              ),
              Self.shouldActivateSmartFrequentBackgroundUpdates(
                speedKmh: speedKmh,
                thresholdKmh: settings.smartFrequentBackgroundSpeedThresholdKmh
              ),
              !isBatteryAtOrBelowFrequentBackgroundThreshold() else {
            return didDeactivateForInactivity
        }

        activateSmartFrequentBackgroundRuntime(
            location: location,
            speedKmh: speedKmh,
            now: now
        )
        return true
    }

    private func activateSmartFrequentBackgroundRuntime(location: CLLocation,
                                                        speedKmh: Double?,
                                                        now: Date) {
        smartFrequentBackgroundRuntimeActive = true
        lastSmartFrequentBackgroundLocationUpdateAt = now
        smartFrequentBackgroundLastRelevantMovementAt = now
        smartFrequentBackgroundMovementAnchor = location
        if let speedKmh {
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
        debugLog("[LocationManager] Smart frequent background runtime activated speedKmh=\(String(describing: speedKmh))")
        notifySmartFrequentBackgroundModeChangeIfEnabled(isActive: true)
    }

    @discardableResult
    private func deactivateSmartFrequentBackgroundRuntime(reason: String) -> Bool {
        let wasActive = smartFrequentBackgroundRuntimeActive
        smartFrequentBackgroundRuntimeActive = false
        lastSmartFrequentBackgroundLocationUpdateAt = nil
        smartFrequentBackgroundMovementAnchor = nil
        smartFrequentBackgroundNextInactivityTimeoutAt = nil
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
        if wasActive {
            debugLog("[LocationManager] Smart frequent background runtime deactivated: \(reason)")
        }
        return wasActive
    }

    private func resetSmartFrequentBackgroundRuntime() {
        smartFrequentBackgroundRuntimeActive = false
        smartFrequentBackgroundLastActivationReason = nil
        smartFrequentBackgroundLastRelevantMovementAt = nil
        smartFrequentBackgroundNextInactivityTimeoutAt = nil
        lastSmartFrequentBackgroundLocationUpdateAt = nil
        smartFrequentBackgroundMovementAnchor = nil
        smartFrequentBackgroundSpeedReferenceLocation = nil
        smartFrequentBackgroundInactivityTimer?.invalidate()
        smartFrequentBackgroundInactivityTimer = nil
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

        let didDeactivate = deactivateSmartFrequentBackgroundRuntime(reason: "smart frequent inactivity timeout")
        if didDeactivate {
            notifySmartFrequentBackgroundModeChangeIfEnabled(isActive: false)
        }
        return didDeactivate
    }

    @discardableResult
    private func refreshSmartFrequentBackgroundMovementState(for location: CLLocation,
                                                             now: Date) -> Bool {
        guard smartFrequentBackgroundRuntimeActive else { return false }
        lastSmartFrequentBackgroundLocationUpdateAt = now

        guard let anchor = smartFrequentBackgroundMovementAnchor else {
            smartFrequentBackgroundMovementAnchor = location
            smartFrequentBackgroundLastRelevantMovementAt = now
            return true
        }

        let distance = location.distance(from: anchor)
        guard distance.isFinite,
              distance >= CLLocationDistance(settings.frequentBackgroundLocationDistanceFilter) else {
            return false
        }

        smartFrequentBackgroundMovementAnchor = location
        smartFrequentBackgroundLastRelevantMovementAt = now
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
    private func sendLocationToServer(_ location: CLLocation) {
        if settings.deviceKeyAuthBlocked {
            self.serverUpdateStatus = .failed(
                NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
            )
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
        let applicationState = UIApplication.shared.applicationState
        let deliveryDelay = frequentBackgroundLocationDeliveryDelay(for: applicationState)
        let visitorCheckMinimumInterval = frequentBackgroundVisitorCheckMinimumInterval(for: applicationState)
        let backgroundTask = beginLocationUploadBackgroundTaskIfNeeded(for: applicationState)
        self.serverUpdateStatus = .updating
        Task {
            defer {
                if let backgroundTask {
                    Task { @MainActor in
                        backgroundTask.end()
                    }
                }
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
            case .failed(let error):
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
        handleFrequentBackgroundLocationExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()
        guard isTracking else { return }
        // Check daily reset on foreground entry so UI reflects a new day immediately
        maybeResetBackgroundMetricsIfNeeded()
        applyTrackingMode(reason: "app did enter foreground", applicationStateContext: .forceForeground)
    }

    func appDidEnterBackground() {
        debugLog("[LocationManager] App did enter background")
        handleFrequentBackgroundLocationExpirationIfNeeded()
        refreshFrequentBackgroundTrackingReminder()
        guard isTracking else { return }
        applyTrackingMode(reason: "app did enter background", applicationStateContext: .forceBackground)
    }

    private func stopAllLocationServices() {
        debugLog("[LocationManager] Stopping all location services")
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
            guard let location = locations.last else { return }
            let applicationState = UIApplication.shared.applicationState
            let updateSource = self.locationUpdateSource(for: manager)
            let updateCounterMode = Self.locationUpdateCounterMode(
                applicationState: applicationState,
                manualFrequentEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
                smartEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
                smartRuntimeActive: smartFrequentBackgroundRuntimeActive
            )
            debugLog("[LocationManager] didUpdateLocations source=\(updateSource.rawValue), count=\(locations.count), state=\(applicationState.rawValue), manualFrequentEnabled=\(settings.frequentBackgroundLocationUpdatesEnabled), smartEnabled=\(settings.smartFrequentBackgroundLocationUpdatesEnabled), smartRuntimeActive=\(smartFrequentBackgroundRuntimeActive)")
            let didExpireFrequentBackgroundUpdates = self.handleFrequentBackgroundLocationExpirationIfNeeded()
            let didDisableFrequentBackgroundUpdatesForBattery = self.disableFrequentBackgroundLocationUpdatesIfBatteryIsLow()
            let didSwitchSmartFrequentBackgroundMode = self.updateSmartFrequentBackgroundRuntime(
                for: location,
                updateSource: updateSource,
                applicationState: applicationState
            )
            let didSwitchFrequentBackgroundMode = didExpireFrequentBackgroundUpdates || didDisableFrequentBackgroundUpdatesForBattery || didSwitchSmartFrequentBackgroundMode
            if self.shouldSuppressAfterCleaningUpStaleFrequentBackgroundCallbackIfNeeded(
                updateSource: updateSource,
                didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode,
                applicationState: applicationState
            ) {
                return
            }
            self.reassertStandardSignificantChangeAfterPrimaryCallbackIfNeeded(
                applicationState: applicationState,
                updateSource: updateSource,
                didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
            )
            self.latestRawLocation = location
            self.recordLocationUpdateMetric(mode: updateCounterMode)
            let mode = self.locationUpdateLogModeText(for: updateCounterMode)
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

            if (userHeading == nil || !isHeadingValid),
               location.course >= 0,
               location.speed >= headingMinSpeedThreshold {
                userHeading = smoothHeading(normalizedHeading(location.course))
            }
            
            guard shouldAcceptUpdate else {
                if didSwitchFrequentBackgroundMode, applicationState != .active {
                    self.applyTrackingMode(reason: Self.frequentBackgroundModeSwitchReason(
                        didExpire: didExpireFrequentBackgroundUpdates,
                        didDisableForBattery: didDisableFrequentBackgroundUpdatesForBattery
                    ))
                } else {
                    self.reassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeIfNeeded(
                        applicationState: applicationState,
                        updateSource: updateSource,
                        didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
                    )
                }
                return
            }
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
            if Self.shouldSubmitLocationForUpload(location, lastSubmittedKey: self.lastSubmittedLocationDeduplicationKey) {
                self.lastSubmittedLocationDeduplicationKey = Self.locationSubmissionDeduplicationKey(for: location)
                self.sendLocationToServer(location)
            } else {
                debugLog("[LocationManager] Skipping duplicate location upload from parallel location services")
            }
            self.addUpdateLogEntry(mode: mode)
            if didSwitchFrequentBackgroundMode, applicationState != .active {
                self.applyTrackingMode(reason: Self.frequentBackgroundModeSwitchReason(
                    didExpire: didExpireFrequentBackgroundUpdates,
                    didDisableForBattery: didDisableFrequentBackgroundUpdatesForBattery
                ))
            } else {
                self.reassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeIfNeeded(
                    applicationState: applicationState,
                    updateSource: updateSource,
                    didSwitchFrequentBackgroundMode: didSwitchFrequentBackgroundMode
                )
            }
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

            // If permission is denied or restricted, update the setting to reflect the actual state
            if status == .denied || status == .restricted {
                if settings.trackAndReportLocation {
                    debugLog("Location permission denied/restricted, setting trackAndReportLocation to false")
                    settings.trackAndReportLocation = false
                }
            }
            if status == .authorizedWhenInUse,
               settings.trackAndReportLocation {
                self.requestAlwaysAuthorizationIfPossible(reason: "authorization changed")
            }
            self.applyTrackingMode(reason: "authorization changed")
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
