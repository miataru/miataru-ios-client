/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * CoreLocationServiceController.swift
 * miataru
 */

import CoreLocation
import Foundation

protocol CoreLocationOneShotProbeDriving: AnyObject {
    var hasPendingRequest: Bool { get }
    func request(activityType: CLActivityType,
                 didReceive: @escaping (CLLocationManager, [CLLocation]) -> Void,
                 didFail: @escaping (CLLocationManager, Error) -> Void) -> Bool
    func cancel()
    func owns(_ manager: CLLocationManager) -> Bool
}

final class CoreLocationOneShotProbe: NSObject, CoreLocationOneShotProbeDriving, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private let managerFactory: () -> CLLocationManager
    private var locationHandler: ((CLLocationManager, [CLLocation]) -> Void)?
    private var errorHandler: ((CLLocationManager, Error) -> Void)?

    var hasPendingRequest: Bool { manager != nil }

    init(managerFactory: @escaping () -> CLLocationManager = { CLLocationManager() }) {
        self.managerFactory = managerFactory
        super.init()
    }

    func request(activityType: CLActivityType,
                 didReceive: @escaping (CLLocationManager, [CLLocation]) -> Void,
                 didFail: @escaping (CLLocationManager, Error) -> Void) -> Bool {
        guard manager == nil else { return false }
        let manager = managerFactory()
        manager.delegate = self
        manager.activityType = activityType
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = false
        self.locationHandler = didReceive
        self.errorHandler = didFail
        self.manager = manager
        manager.requestLocation()
        return true
    }

    func cancel() {
        guard let manager else { return }
        manager.stopUpdatingLocation()
        manager.delegate = nil
        manager.allowsBackgroundLocationUpdates = false
        self.manager = nil
        locationHandler = nil
        errorHandler = nil
    }

    func owns(_ manager: CLLocationManager) -> Bool { self.manager === manager }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard owns(manager) else { return }
        locationHandler?(manager, locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard owns(manager) else { return }
        errorHandler?(manager, error)
    }
}

protocol CoreLocationServiceSessionHandle: AnyObject {
    func invalidate()
}

private final class CLServiceSessionHandle: CoreLocationServiceSessionHandle {
    private let session: CLServiceSession

    init(session: CLServiceSession) {
        self.session = session
    }

    func invalidate() {
        session.invalidate()
    }
}

private final class CLBackgroundActivitySessionHandle: CoreLocationServiceSessionHandle {
    private let session: CLBackgroundActivitySession

    init(session: CLBackgroundActivitySession) {
        self.session = session
    }

    func invalidate() {
        session.invalidate()
    }
}

struct CoreLocationServiceStateSnapshot: Equatable {
    let primaryStandardUpdatesRequested: Bool
    let primarySignificantChangeMonitoringRequested: Bool
    let primaryDelegateInstalled: Bool
    let primaryAllowsBackgroundLocationUpdates: Bool
    let primaryPausesLocationUpdatesAutomatically: Bool
    let primaryShowsBackgroundLocationIndicator: Bool
    let secondaryStandardUpdatesRequested: Bool
    let secondarySignificantChangeMonitoringRequested: Bool
    let secondaryAllowsBackgroundLocationUpdates: Bool
    let secondaryPausesLocationUpdatesAutomatically: Bool
    let secondaryShowsBackgroundLocationIndicator: Bool
    let secondaryDelegateInstalled: Bool
    let significantChangeRecoveryAnchorActive: Bool
    let locationServiceSessionObjectHeld: Bool
    let locationServiceSessionCurrentID: String?
    let locationServiceSessionLastID: String?
    let locationServiceSessionTransitionCount: Int
    let locationServiceSessionLastAction: String?
    let locationServiceSessionLastReason: String?
    let frequentBackgroundActivitySessionObjectHeld: Bool
    let frequentBackgroundActivitySessionCurrentID: String?
    let frequentBackgroundActivitySessionLastID: String?
    let frequentBackgroundActivitySessionTransitionCount: Int
    let frequentBackgroundActivitySessionLastAction: String?
    let frequentBackgroundActivitySessionLastReason: String?

    func diagnosticContext(
        expectedPrimaryStandardUpdatesRequested: Bool,
        expectedPrimarySignificantChangeMonitoringRequested: Bool,
        expectedPrimaryAllowsBackgroundLocationUpdates: Bool,
        expectedPrimaryShowsBackgroundLocationIndicator: Bool,
        expectedSecondaryStandardUpdatesRequested: Bool,
        expectedSecondarySignificantChangeMonitoringRequested: Bool,
        expectedSecondaryAllowsBackgroundLocationUpdates: Bool,
        expectedSecondaryPausesLocationUpdatesAutomatically: Bool,
        expectedSecondaryShowsBackgroundLocationIndicator: Bool,
        expectedSignificantChangeRecoveryAnchorActive: Bool,
        expectedLocationServiceSessionObjectHeld: Bool,
        expectedFrequentBackgroundActivitySessionObjectHeld: Bool,
        trackingMode: String,
        reason: String
    ) -> [String: LocationDiagnosticsValue] {
        let serviceStateMatchesExpectation =
            primaryStandardUpdatesRequested == expectedPrimaryStandardUpdatesRequested &&
            primarySignificantChangeMonitoringRequested == expectedPrimarySignificantChangeMonitoringRequested &&
            primaryAllowsBackgroundLocationUpdates == expectedPrimaryAllowsBackgroundLocationUpdates &&
            primaryShowsBackgroundLocationIndicator == expectedPrimaryShowsBackgroundLocationIndicator &&
            secondaryStandardUpdatesRequested == expectedSecondaryStandardUpdatesRequested &&
            secondarySignificantChangeMonitoringRequested == expectedSecondarySignificantChangeMonitoringRequested &&
            secondaryAllowsBackgroundLocationUpdates == expectedSecondaryAllowsBackgroundLocationUpdates &&
            // Core Location can normalize this readback while the manager is stopped.
            // It matters to the active service contract, not to whether teardown succeeded.
            (!expectedSecondaryStandardUpdatesRequested ||
             secondaryPausesLocationUpdatesAutomatically == expectedSecondaryPausesLocationUpdatesAutomatically) &&
            secondaryShowsBackgroundLocationIndicator == expectedSecondaryShowsBackgroundLocationIndicator &&
            secondaryDelegateInstalled == expectedSecondaryStandardUpdatesRequested &&
            significantChangeRecoveryAnchorActive == expectedSignificantChangeRecoveryAnchorActive &&
            locationServiceSessionObjectHeld == expectedLocationServiceSessionObjectHeld &&
            frequentBackgroundActivitySessionObjectHeld == expectedFrequentBackgroundActivitySessionObjectHeld

        var context: [String: LocationDiagnosticsValue] = [
            "trackingMode": .string(trackingMode),
            "transitionReason": .string(reason),
            "serviceStateMatchesExpectation": .bool(serviceStateMatchesExpectation),
            "expectedPrimaryStandardUpdatesRequested": .bool(expectedPrimaryStandardUpdatesRequested),
            "expectedPrimarySignificantChangeMonitoringRequested": .bool(expectedPrimarySignificantChangeMonitoringRequested),
            "expectedPrimaryAllowsBackgroundLocationUpdates": .bool(expectedPrimaryAllowsBackgroundLocationUpdates),
            "expectedPrimaryShowsBackgroundLocationIndicator": .bool(expectedPrimaryShowsBackgroundLocationIndicator),
            "expectedSecondaryStandardUpdatesRequested": .bool(expectedSecondaryStandardUpdatesRequested),
            "expectedSecondarySignificantChangeMonitoringRequested": .bool(expectedSecondarySignificantChangeMonitoringRequested),
            "expectedSecondaryAllowsBackgroundLocationUpdates": .bool(expectedSecondaryAllowsBackgroundLocationUpdates),
            "expectedSecondaryPausesLocationUpdatesAutomatically": .bool(expectedSecondaryPausesLocationUpdatesAutomatically),
            "expectedSecondaryShowsBackgroundLocationIndicator": .bool(expectedSecondaryShowsBackgroundLocationIndicator),
            "expectedSignificantChangeRecoveryAnchorActive": .bool(expectedSignificantChangeRecoveryAnchorActive),
            "expectedLocationServiceSessionObjectHeld": .bool(expectedLocationServiceSessionObjectHeld),
            "expectedFrequentBackgroundActivitySessionObjectHeld": .bool(expectedFrequentBackgroundActivitySessionObjectHeld),
            "primaryStandardUpdatesRequested": .bool(primaryStandardUpdatesRequested),
            "primarySignificantChangeMonitoringRequested": .bool(primarySignificantChangeMonitoringRequested),
            "primaryDelegateInstalled": .bool(primaryDelegateInstalled),
            "primaryAllowsBackgroundLocationUpdates": .bool(primaryAllowsBackgroundLocationUpdates),
            "primaryPausesLocationUpdatesAutomatically": .bool(primaryPausesLocationUpdatesAutomatically),
            "primaryShowsBackgroundLocationIndicator": .bool(primaryShowsBackgroundLocationIndicator),
            "secondaryStandardUpdatesRequested": .bool(secondaryStandardUpdatesRequested),
            "secondarySignificantChangeMonitoringRequested": .bool(secondarySignificantChangeMonitoringRequested),
            "secondaryAllowsBackgroundLocationUpdates": .bool(secondaryAllowsBackgroundLocationUpdates),
            "secondaryPausesLocationUpdatesAutomatically": .bool(secondaryPausesLocationUpdatesAutomatically),
            "secondaryShowsBackgroundLocationIndicator": .bool(secondaryShowsBackgroundLocationIndicator),
            "secondaryDelegateInstalled": .bool(secondaryDelegateInstalled),
            "significantChangeRecoveryAnchorActive": .bool(significantChangeRecoveryAnchorActive),
            "locationServiceSessionObjectHeld": .bool(locationServiceSessionObjectHeld),
            "locationServiceSessionTransitionCount": .integer(locationServiceSessionTransitionCount),
            "frequentBackgroundActivitySessionObjectHeld": .bool(frequentBackgroundActivitySessionObjectHeld),
            "frequentBackgroundActivitySessionTransitionCount": .integer(frequentBackgroundActivitySessionTransitionCount)
        ]
        if let locationServiceSessionCurrentID {
            context["locationServiceSessionCurrentID"] = .string(locationServiceSessionCurrentID)
        }
        if let locationServiceSessionLastID {
            context["locationServiceSessionLastID"] = .string(locationServiceSessionLastID)
        }
        if let locationServiceSessionLastAction {
            context["locationServiceSessionLastAction"] = .string(locationServiceSessionLastAction)
        }
        if let locationServiceSessionLastReason {
            context["locationServiceSessionLastReason"] = .string(locationServiceSessionLastReason)
        }
        if let frequentBackgroundActivitySessionCurrentID {
            context["frequentBackgroundActivitySessionCurrentID"] = .string(frequentBackgroundActivitySessionCurrentID)
        }
        if let frequentBackgroundActivitySessionLastID {
            context["frequentBackgroundActivitySessionLastID"] = .string(frequentBackgroundActivitySessionLastID)
        }
        if let frequentBackgroundActivitySessionLastAction {
            context["frequentBackgroundActivitySessionLastAction"] = .string(frequentBackgroundActivitySessionLastAction)
        }
        if let frequentBackgroundActivitySessionLastReason {
            context["frequentBackgroundActivitySessionLastReason"] = .string(frequentBackgroundActivitySessionLastReason)
        }
        return context
    }
}

final class CoreLocationServiceController {
    let primaryManager: CLLocationManager
    let frequentBackgroundManager: CLLocationManager

    private(set) var isSignificantChangeRecoveryAnchorActive = false
    private(set) var isFrequentBackgroundStandardUpdatesActive = false
    private(set) var isPrimaryStandardUpdatesRequested = false
    private(set) var isPrimarySignificantChangeMonitoringRequested = false
    private(set) var isFrequentBackgroundSignificantChangeMonitoringRequested = false

    private var shouldAllowNextStaleFrequentBackgroundCallback = false
    private var locationServiceSession: CoreLocationServiceSessionHandle?
    private var frequentBackgroundActivitySession: CoreLocationServiceSessionHandle?
    private let locationServiceSessionFactory: () -> CoreLocationServiceSessionHandle
    private let frequentBackgroundActivitySessionFactory: () -> CoreLocationServiceSessionHandle
    private let oneShotProbe: CoreLocationOneShotProbeDriving
    private(set) var isOneShotProbePending = false
    private(set) var locationServiceSessionCurrentID: String?
    private(set) var locationServiceSessionLastID: String?
    private(set) var locationServiceSessionTransitionCount = 0
    private(set) var locationServiceSessionLastAction: String?
    private(set) var locationServiceSessionLastReason: String?
    private(set) var frequentBackgroundActivitySessionCurrentID: String?
    private(set) var frequentBackgroundActivitySessionLastID: String?
    private(set) var frequentBackgroundActivitySessionTransitionCount = 0
    private(set) var frequentBackgroundActivitySessionLastAction: String?
    private(set) var frequentBackgroundActivitySessionLastReason: String?

    var frequentBackgroundActivitySessionActive: Bool {
        frequentBackgroundActivitySession != nil
    }

    var frequentBackgroundLocationRequestDelegateReady: Bool {
        guard let delegate = frequentBackgroundManager.delegate else {
            return false
        }

        return delegate.responds(to: #selector(CLLocationManagerDelegate.locationManager(_:didUpdateLocations:))) &&
        delegate.responds(to: #selector(CLLocationManagerDelegate.locationManager(_:didFailWithError:)))
    }

    init(primaryManager: CLLocationManager = CLLocationManager(),
         frequentBackgroundManager: CLLocationManager = CLLocationManager(),
         locationServiceSessionFactory: @escaping () -> CoreLocationServiceSessionHandle = {
             CLServiceSessionHandle(session: CLServiceSession(authorization: .always))
         },
         frequentBackgroundActivitySessionFactory: @escaping () -> CoreLocationServiceSessionHandle = {
             CLBackgroundActivitySessionHandle(session: CLBackgroundActivitySession())
         },
         oneShotProbe: CoreLocationOneShotProbeDriving = CoreLocationOneShotProbe()) {
        self.primaryManager = primaryManager
        self.frequentBackgroundManager = frequentBackgroundManager
        self.locationServiceSessionFactory = locationServiceSessionFactory
        self.frequentBackgroundActivitySessionFactory = frequentBackgroundActivitySessionFactory
        self.oneShotProbe = oneShotProbe
    }

    var serviceStateSnapshot: CoreLocationServiceStateSnapshot {
        CoreLocationServiceStateSnapshot(
            primaryStandardUpdatesRequested: isPrimaryStandardUpdatesRequested,
            primarySignificantChangeMonitoringRequested: isPrimarySignificantChangeMonitoringRequested,
            primaryDelegateInstalled: primaryManager.delegate != nil,
            primaryAllowsBackgroundLocationUpdates: primaryManager.allowsBackgroundLocationUpdates,
            primaryPausesLocationUpdatesAutomatically: primaryManager.pausesLocationUpdatesAutomatically,
            primaryShowsBackgroundLocationIndicator: primaryManager.showsBackgroundLocationIndicator,
            secondaryStandardUpdatesRequested: isFrequentBackgroundStandardUpdatesActive,
            secondarySignificantChangeMonitoringRequested: isFrequentBackgroundSignificantChangeMonitoringRequested,
            secondaryAllowsBackgroundLocationUpdates: frequentBackgroundManager.allowsBackgroundLocationUpdates,
            secondaryPausesLocationUpdatesAutomatically: frequentBackgroundManager.pausesLocationUpdatesAutomatically,
            secondaryShowsBackgroundLocationIndicator: frequentBackgroundManager.showsBackgroundLocationIndicator,
            secondaryDelegateInstalled: frequentBackgroundManager.delegate != nil,
            significantChangeRecoveryAnchorActive: isSignificantChangeRecoveryAnchorActive,
            locationServiceSessionObjectHeld: locationServiceSession != nil,
            locationServiceSessionCurrentID: locationServiceSessionCurrentID,
            locationServiceSessionLastID: locationServiceSessionLastID,
            locationServiceSessionTransitionCount: locationServiceSessionTransitionCount,
            locationServiceSessionLastAction: locationServiceSessionLastAction,
            locationServiceSessionLastReason: locationServiceSessionLastReason,
            frequentBackgroundActivitySessionObjectHeld: frequentBackgroundActivitySession != nil,
            frequentBackgroundActivitySessionCurrentID: frequentBackgroundActivitySessionCurrentID,
            frequentBackgroundActivitySessionLastID: frequentBackgroundActivitySessionLastID,
            frequentBackgroundActivitySessionTransitionCount: frequentBackgroundActivitySessionTransitionCount,
            frequentBackgroundActivitySessionLastAction: frequentBackgroundActivitySessionLastAction,
            frequentBackgroundActivitySessionLastReason: frequentBackgroundActivitySessionLastReason
        )
    }

    func configure(delegate: CLLocationManagerDelegate, activityType: CLActivityType) {
        primaryManager.delegate = delegate
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.pausesLocationUpdatesAutomatically = false
        primaryManager.showsBackgroundLocationIndicator = false
        primaryManager.activityType = activityType

        frequentBackgroundManager.delegate = delegate
        frequentBackgroundManager.allowsBackgroundLocationUpdates = true
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = false
        frequentBackgroundManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.activityType = activityType

        if CLLocationManager.headingAvailable() {
            primaryManager.headingFilter = 1
        }
    }

    func updateActivityType(_ activityType: CLActivityType) {
        primaryManager.activityType = activityType
        frequentBackgroundManager.activityType = activityType
    }

    func syncBackgroundLocationIndicator(shouldShowIndicator: Bool) {
        primaryManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.showsBackgroundLocationIndicator = shouldShowIndicator
    }

    func startHighAccuracyUpdates(shouldMaintainPrimarySignificantChangeMonitor: Bool) {
        if shouldMaintainPrimarySignificantChangeMonitor {
            debugLog("[LocationManager] Keeping primary significant-change monitor active during foreground tracking")
            primaryManager.startMonitoringSignificantLocationChanges()
            isPrimarySignificantChangeMonitoringRequested = true
        } else {
            primaryManager.stopMonitoringSignificantLocationChanges()
            isPrimarySignificantChangeMonitoringRequested = false
        }
        stopFrequentBackgroundStandardUpdates()
        primaryManager.allowsBackgroundLocationUpdates = false
        debugLog("allowsBackgroundLocationUpdates set to false (foreground)")
        primaryManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        primaryManager.distanceFilter = kCLDistanceFilterNone
        primaryManager.startUpdatingLocation()
        isPrimaryStandardUpdatesRequested = true
    }

    func startSignificantChangeMonitoring() {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.showsBackgroundLocationIndicator = false
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        primaryManager.stopUpdatingLocation()
        isPrimaryStandardUpdatesRequested = false
        primaryManager.startMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = true
        stopFrequentBackgroundStandardUpdates()
        isFrequentBackgroundSignificantChangeMonitoringRequested = false
    }

    func startFrequentBackgroundLocationUpdates(configuration: LocationTrackingPolicy.BackgroundUpdateConfiguration,
                                                delegate: CLLocationManagerDelegate,
                                                activityType: CLActivityType) {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.stopUpdatingLocation()
        isPrimaryStandardUpdatesRequested = false
        primaryManager.startMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = true

        frequentBackgroundManager.delegate = delegate
        frequentBackgroundManager.allowsBackgroundLocationUpdates = true
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = false
        frequentBackgroundManager.showsBackgroundLocationIndicator = true
        frequentBackgroundManager.activityType = activityType
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
        isFrequentBackgroundSignificantChangeMonitoringRequested = false
        frequentBackgroundManager.desiredAccuracy = configuration.desiredAccuracy
        frequentBackgroundManager.distanceFilter = configuration.distanceFilter
        frequentBackgroundManager.startUpdatingLocation()
        isFrequentBackgroundStandardUpdatesActive = true
        isPrimaryStandardUpdatesRequested = false
        isFrequentBackgroundSignificantChangeMonitoringRequested = false
        shouldAllowNextStaleFrequentBackgroundCallback = false
    }

    func stopFrequentBackgroundStandardUpdates() {
        if isFrequentBackgroundStandardUpdatesActive {
            shouldAllowNextStaleFrequentBackgroundCallback = true
        }
        frequentBackgroundManager.stopUpdatingLocation()
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
        isFrequentBackgroundSignificantChangeMonitoringRequested = false
        frequentBackgroundManager.allowsBackgroundLocationUpdates = false
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = true
        frequentBackgroundManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.delegate = nil
        isFrequentBackgroundStandardUpdatesActive = false
    }

    func consumeAllowNextStaleFrequentBackgroundCallback() -> Bool {
        let value = shouldAllowNextStaleFrequentBackgroundCallback
        shouldAllowNextStaleFrequentBackgroundCallback = false
        return value
    }

    func syncLocationServiceSession(reason: String, shouldMaintainSession: Bool) {
        if shouldMaintainSession {
            startLocationServiceSessionIfNeeded(reason: reason)
        } else {
            stopLocationServiceSession(reason: reason)
        }
    }

    func syncFrequentBackgroundActivitySession(reason: String, shouldMaintainSession: Bool) {
        if shouldMaintainSession {
            startFrequentBackgroundActivitySessionIfNeeded(reason: reason)
        } else {
            stopFrequentBackgroundActivitySession(reason: reason)
        }
    }

    func startSignificantChangeRecoveryAnchor(reason: String) {
        let action = isSignificantChangeRecoveryAnchorActive ? "Reasserting" : "Starting"
        debugLog("[LocationManager] \(action) primary significant-change recovery anchor (\(reason))")
        primaryManager.startMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = true
        isSignificantChangeRecoveryAnchorActive = true
    }

    func stopSignificantChangeRecoveryAnchor(reason: String) {
        let action = isSignificantChangeRecoveryAnchorActive ? "Stopping" : "Reasserting stopped"
        debugLog("[LocationManager] \(action) primary significant-change recovery anchor (\(reason))")
        primaryManager.stopMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = false
        isSignificantChangeRecoveryAnchorActive = false
    }

    func allowPrimaryBackgroundLocationUpdates() {
        primaryManager.allowsBackgroundLocationUpdates = true
    }

    func rearmSignificantChangeMonitorAfterFreshLaunch() {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.stopMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = false
        isSignificantChangeRecoveryAnchorActive = false
        primaryManager.startMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = true
        isSignificantChangeRecoveryAnchorActive = true
    }

    func startOrReplaceSmartFrequentExitFence(_ region: CLCircularRegion) {
        // Core Location replaces a monitored region with the same identifier.
        // Keep the previous fence registered until the replacement is requested.
        primaryManager.startMonitoring(for: region)
    }

    func stopManagedLocationUpdates() {
        primaryManager.stopUpdatingLocation()
        primaryManager.stopMonitoringSignificantLocationChanges()
        isPrimarySignificantChangeMonitoringRequested = false
        primaryManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.stopUpdatingLocation()
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundManager.allowsBackgroundLocationUpdates = false
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = true
        frequentBackgroundManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.delegate = nil
        primaryManager.allowsBackgroundLocationUpdates = false
        isSignificantChangeRecoveryAnchorActive = false
        isFrequentBackgroundStandardUpdatesActive = false
        isPrimaryStandardUpdatesRequested = false
        isPrimarySignificantChangeMonitoringRequested = false
        isFrequentBackgroundSignificantChangeMonitoringRequested = false
        shouldAllowNextStaleFrequentBackgroundCallback = false
    }

    func startHeadingUpdatesIfAvailable() {
        primaryManager.startUpdatingHeading()
    }

    func stopHeadingUpdates() {
        primaryManager.stopUpdatingHeading()
    }

    func requestPrimaryLocation() {
        primaryManager.requestLocation()
    }

    func requestFrequentBackgroundLocation() {
        frequentBackgroundManager.requestLocation()
    }

    @discardableResult
    func requestIsolatedOneShotLocation(activityType: CLActivityType,
                                        didReceive: @escaping (CLLocationManager, [CLLocation]) -> Void,
                                        didFail: @escaping (CLLocationManager, Error) -> Void) -> Bool {
        guard !isOneShotProbePending else { return false }
        let started = oneShotProbe.request(activityType: activityType, didReceive: didReceive, didFail: didFail)
        isOneShotProbePending = started
        return started
    }

    func isIsolatedOneShotManager(_ manager: CLLocationManager) -> Bool {
        oneShotProbe.owns(manager)
    }

    func cancelIsolatedOneShotLocation() {
        oneShotProbe.cancel()
        isOneShotProbePending = false
    }

    func stopLocationServiceSession(reason: String) {
        guard let locationServiceSession else { return }
        debugLog("[LocationManager] Stopping Always CLServiceSession (\(reason))")
        locationServiceSession.invalidate()
        self.locationServiceSession = nil
        locationServiceSessionLastID = locationServiceSessionCurrentID
        locationServiceSessionCurrentID = nil
        locationServiceSessionTransitionCount += 1
        locationServiceSessionLastAction = "stopped"
        locationServiceSessionLastReason = reason
    }

    func stopFrequentBackgroundActivitySession(reason: String) {
        if let activitySession = frequentBackgroundActivitySession {
            debugLog("[LocationManager] Stopping frequent background CLBackgroundActivitySession (\(reason))")
            activitySession.invalidate()
            frequentBackgroundActivitySession = nil
            frequentBackgroundActivitySessionLastID = frequentBackgroundActivitySessionCurrentID
            frequentBackgroundActivitySessionCurrentID = nil
            frequentBackgroundActivitySessionTransitionCount += 1
            frequentBackgroundActivitySessionLastAction = "stopped"
            frequentBackgroundActivitySessionLastReason = reason
        }
    }

    private func startLocationServiceSessionIfNeeded(reason: String) {
        guard locationServiceSession == nil else { return }
        debugLog("[LocationManager] Starting Always CLServiceSession (\(reason))")
        locationServiceSession = locationServiceSessionFactory()
        let sessionID = UUID().uuidString
        locationServiceSessionCurrentID = sessionID
        locationServiceSessionLastID = sessionID
        locationServiceSessionTransitionCount += 1
        locationServiceSessionLastAction = "started"
        locationServiceSessionLastReason = reason
    }

    private func startFrequentBackgroundActivitySessionIfNeeded(reason: String) {
        if frequentBackgroundActivitySession == nil {
            debugLog("[LocationManager] Starting frequent background CLBackgroundActivitySession (\(reason))")
            frequentBackgroundActivitySession = frequentBackgroundActivitySessionFactory()
            let sessionID = UUID().uuidString
            frequentBackgroundActivitySessionCurrentID = sessionID
            frequentBackgroundActivitySessionLastID = sessionID
            frequentBackgroundActivitySessionTransitionCount += 1
            frequentBackgroundActivitySessionLastAction = "started"
            frequentBackgroundActivitySessionLastReason = reason
        } else {
            debugLog("[LocationManager] Keeping frequent background activity session active (\(reason))")
        }
    }
}
