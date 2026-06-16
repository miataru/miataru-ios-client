/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * CoreLocationServiceController.swift
 * miataru
 */

import CoreLocation
import Foundation

final class CoreLocationServiceController {
    let primaryManager: CLLocationManager
    let frequentBackgroundManager: CLLocationManager

    private(set) var isSignificantChangeRecoveryAnchorActive = false
    private(set) var isFrequentBackgroundStandardUpdatesActive = false

    private var shouldAllowNextStaleFrequentBackgroundCallback = false
    private var locationServiceSession: CLServiceSession?
    private var frequentBackgroundActivitySession: CLBackgroundActivitySession?

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
         frequentBackgroundManager: CLLocationManager = CLLocationManager()) {
        self.primaryManager = primaryManager
        self.frequentBackgroundManager = frequentBackgroundManager
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
        } else {
            primaryManager.stopMonitoringSignificantLocationChanges()
        }
        stopFrequentBackgroundStandardUpdates()
        primaryManager.allowsBackgroundLocationUpdates = false
        debugLog("allowsBackgroundLocationUpdates set to false (foreground)")
        primaryManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        primaryManager.distanceFilter = kCLDistanceFilterNone
        primaryManager.startUpdatingLocation()
    }

    func startSignificantChangeMonitoring() {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.showsBackgroundLocationIndicator = false
        debugLog("allowsBackgroundLocationUpdates set to true (background)")
        primaryManager.stopUpdatingLocation()
        primaryManager.startMonitoringSignificantLocationChanges()
        stopFrequentBackgroundStandardUpdates()
    }

    func startFrequentBackgroundLocationUpdates(configuration: LocationTrackingPolicy.BackgroundUpdateConfiguration,
                                                delegate: CLLocationManagerDelegate,
                                                activityType: CLActivityType) {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.stopUpdatingLocation()
        primaryManager.startMonitoringSignificantLocationChanges()

        frequentBackgroundManager.delegate = delegate
        frequentBackgroundManager.allowsBackgroundLocationUpdates = true
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = false
        frequentBackgroundManager.showsBackgroundLocationIndicator = true
        frequentBackgroundManager.activityType = activityType
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundManager.desiredAccuracy = configuration.desiredAccuracy
        frequentBackgroundManager.distanceFilter = configuration.distanceFilter
        frequentBackgroundManager.startUpdatingLocation()
        isFrequentBackgroundStandardUpdatesActive = true
        shouldAllowNextStaleFrequentBackgroundCallback = false
    }

    func stopFrequentBackgroundStandardUpdates() {
        if isFrequentBackgroundStandardUpdatesActive {
            shouldAllowNextStaleFrequentBackgroundCallback = true
        }
        frequentBackgroundManager.stopUpdatingLocation()
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
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
        isSignificantChangeRecoveryAnchorActive = true
    }

    func stopSignificantChangeRecoveryAnchor(reason: String) {
        let action = isSignificantChangeRecoveryAnchorActive ? "Stopping" : "Reasserting stopped"
        debugLog("[LocationManager] \(action) primary significant-change recovery anchor (\(reason))")
        primaryManager.stopMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = false
    }

    func allowPrimaryBackgroundLocationUpdates() {
        primaryManager.allowsBackgroundLocationUpdates = true
    }

    func rearmSignificantChangeMonitorAfterFreshLaunch() {
        primaryManager.allowsBackgroundLocationUpdates = true
        primaryManager.stopMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = false
        primaryManager.startMonitoringSignificantLocationChanges()
        isSignificantChangeRecoveryAnchorActive = true
    }

    func stopManagedLocationUpdates() {
        primaryManager.stopUpdatingLocation()
        primaryManager.stopMonitoringSignificantLocationChanges()
        primaryManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.stopUpdatingLocation()
        frequentBackgroundManager.stopMonitoringSignificantLocationChanges()
        frequentBackgroundManager.allowsBackgroundLocationUpdates = false
        frequentBackgroundManager.pausesLocationUpdatesAutomatically = true
        frequentBackgroundManager.showsBackgroundLocationIndicator = false
        frequentBackgroundManager.delegate = nil
        isSignificantChangeRecoveryAnchorActive = false
        isFrequentBackgroundStandardUpdatesActive = false
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

    func stopLocationServiceSession(reason: String) {
        guard let locationServiceSession else { return }
        debugLog("[LocationManager] Stopping Always CLServiceSession (\(reason))")
        locationServiceSession.invalidate()
        self.locationServiceSession = nil
    }

    func stopFrequentBackgroundActivitySession(reason: String) {
        if let activitySession = frequentBackgroundActivitySession {
            debugLog("[LocationManager] Stopping frequent background CLBackgroundActivitySession (\(reason))")
            activitySession.invalidate()
            frequentBackgroundActivitySession = nil
        }
    }

    private func startLocationServiceSessionIfNeeded(reason: String) {
        guard locationServiceSession == nil else { return }
        debugLog("[LocationManager] Starting Always CLServiceSession (\(reason))")
        locationServiceSession = CLServiceSession(authorization: .always)
    }

    private func startFrequentBackgroundActivitySessionIfNeeded(reason: String) {
        if frequentBackgroundActivitySession == nil {
            debugLog("[LocationManager] Starting frequent background CLBackgroundActivitySession (\(reason))")
            frequentBackgroundActivitySession = CLBackgroundActivitySession()
        } else {
            debugLog("[LocationManager] Keeping frequent background activity session active (\(reason))")
        }
    }
}
