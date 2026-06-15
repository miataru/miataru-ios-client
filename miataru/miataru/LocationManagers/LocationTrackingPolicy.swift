/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationTrackingPolicy.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

enum LocationTrackingPolicy {
    struct BackgroundUpdateConfiguration: Equatable {
        let usesSignificantChangeMonitoring: Bool
        let distanceFilter: CLLocationDistance
        let desiredAccuracy: CLLocationAccuracy
    }

    struct AccuracyRecoveryEvaluation: Equatable {
        let poorAccuracyStreak: Int
        let shouldStartRecovery: Bool
        let shouldStopRecovery: Bool
    }

    enum BackgroundTrackingDisplayMode: Equatable {
        case foregroundLive
        case significantChange
        case smartWaiting
        case smartFrequent
        case manualFrequent
    }

    enum TrackingMode: Equatable {
        case stopped
        case foregroundHighAccuracy
        case backgroundSignificantChange
        case backgroundFrequent(distanceFilter: CLLocationDistance, desiredAccuracy: CLLocationAccuracy)
    }

    enum ApplicationStateContext: Equatable {
        case current
        case forceForeground
        case forceBackground
    }

    enum ReconcileAction: String, Equatable {
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

    struct ServiceCommandPlan: Equatable {
        let primary: [PrimaryLocationServiceCommand]
        let secondary: [SecondaryLocationServiceCommand]
    }

    static func activityType(from value: Int) -> CLActivityType {
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

    static let frequentBackgroundAccuracyRecoveryDistanceFilterMeters = 10
    static let frequentBackgroundAccuracyRecoveryTriggerDistanceFilterMeters = 100
    static let frequentBackgroundAccuracyRecoveryPoorAccuracyThreshold: CLLocationAccuracy = 300
    static let frequentBackgroundAccuracyRecoveryImmediateAccuracyThreshold: CLLocationAccuracy = 1_000
    static let frequentBackgroundAccuracyRecoveryTargetAccuracy: CLLocationAccuracy = 100
    static let frequentBackgroundAccuracyRecoveryDuration: TimeInterval = 120
    static let frequentBackgroundAccuracyRecoveryCooldown: TimeInterval = 10 * 60

    static func backgroundUpdateConfiguration(frequentUpdatesEnabled: Bool,
                                              distanceFilterMeters: Int) -> BackgroundUpdateConfiguration {
        backgroundUpdateConfiguration(
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            distanceFilterMeters: distanceFilterMeters,
            accuracyRecoveryActive: false
        )
    }

    static func backgroundUpdateConfiguration(frequentUpdatesEnabled: Bool,
                                              distanceFilterMeters: Int,
                                              accuracyRecoveryActive: Bool) -> BackgroundUpdateConfiguration {
        guard frequentUpdatesEnabled else {
            return BackgroundUpdateConfiguration(
                usesSignificantChangeMonitoring: true,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyHundredMeters
            )
        }

        let normalizedDistance = FrequentBackgroundLocationDistanceFilter.normalized(distanceFilterMeters)
        if accuracyRecoveryActive,
           normalizedDistance == frequentBackgroundAccuracyRecoveryTriggerDistanceFilterMeters {
            return BackgroundUpdateConfiguration(
                usesSignificantChangeMonitoring: false,
                distanceFilter: CLLocationDistance(frequentBackgroundAccuracyRecoveryDistanceFilterMeters),
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters
            )
        }

        return BackgroundUpdateConfiguration(
            usesSignificantChangeMonitoring: false,
            distanceFilter: CLLocationDistance(normalizedDistance),
            desiredAccuracy: backgroundDesiredAccuracy(for: normalizedDistance)
        )
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
                                          smartRuntimeActive: Bool) -> LocationUpdateMetricsStore.CounterMode {
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

    static func shouldEvaluateSmartFrequentRuntime(applicationState: UIApplication.State) -> Bool {
        applicationState == .background
    }

    static func resolvedTrackingMode(isTracking: Bool,
                                     authorizationStatus: CLAuthorizationStatus,
                                     applicationState: UIApplication.State,
                                     frequentUpdatesEnabled: Bool,
                                     distanceFilterMeters: Int,
                                     hasNavigationLocationSession: Bool) -> TrackingMode {
        resolvedTrackingMode(
            isTracking: isTracking,
            authorizationStatus: authorizationStatus,
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled,
            distanceFilterMeters: distanceFilterMeters,
            hasNavigationLocationSession: hasNavigationLocationSession,
            accuracyRecoveryActive: false
        )
    }

    static func resolvedTrackingMode(isTracking: Bool,
                                     authorizationStatus: CLAuthorizationStatus,
                                     applicationState: UIApplication.State,
                                     frequentUpdatesEnabled: Bool,
                                     distanceFilterMeters: Int,
                                     hasNavigationLocationSession: Bool,
                                     accuracyRecoveryActive: Bool) -> TrackingMode {
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
            distanceFilterMeters: distanceFilterMeters,
            accuracyRecoveryActive: accuracyRecoveryActive
        )
        if configuration.usesSignificantChangeMonitoring {
            return .backgroundSignificantChange
        }
        return .backgroundFrequent(
            distanceFilter: configuration.distanceFilter,
            desiredAccuracy: configuration.desiredAccuracy
        )
    }

    static func effectiveApplicationState(currentState: UIApplication.State,
                                          context: ApplicationStateContext) -> UIApplication.State {
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
        guard frequentBackgroundVisitorChecksEnabled(
            applicationState: applicationState,
            frequentUpdatesEnabled: frequentUpdatesEnabled
        ) else {
            return nil
        }
        return visitorCheckInterval.minimumInterval
    }

    static func frequentBackgroundVisitorChecksEnabled(applicationState: UIApplication.State,
                                                       frequentUpdatesEnabled: Bool) -> Bool {
        applicationState != .active && frequentUpdatesEnabled
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
                                        isTracking: Bool) -> ReconcileAction {
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
                                           shouldMaintainRecoveryAnchor: Bool) -> ServiceCommandPlan {
        let secondaryStopCommands: [SecondaryLocationServiceCommand] = [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ]

        switch mode {
        case .stopped:
            return ServiceCommandPlan(
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
            return ServiceCommandPlan(
                primary: foregroundPrimaryCommands,
                secondary: secondaryStopCommands
            )
        case .backgroundSignificantChange:
            return ServiceCommandPlan(
                primary: [.stopUpdatingLocation, .startMonitoringSignificantLocationChanges],
                secondary: secondaryStopCommands
            )
        case .backgroundFrequent(let distanceFilter, let desiredAccuracy):
            return ServiceCommandPlan(
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

    static func shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
        applicationState: UIApplication.State,
        frequentUpdatesEnabled: Bool,
        didSwitchFrequentBackgroundMode: Bool,
        frequentBackgroundStandardUpdatesActiveInCurrentProcess _: Bool,
        updateSourceIsPrimary: Bool
    ) -> Bool {
        updateSourceIsPrimary &&
        applicationState != .active &&
        frequentUpdatesEnabled &&
        !didSwitchFrequentBackgroundMode
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

    static func maximumAcceptedFrequentBackgroundAccuracy(distanceFilterMeters: Int) -> CLLocationAccuracy {
        max(CLLocationAccuracy(FrequentBackgroundLocationDistanceFilter.normalized(distanceFilterMeters)), 50)
    }

    static func isFrequentBackgroundLocationAccuracyAcceptable(applicationState: UIApplication.State,
                                                              updateSourceIsFrequentBackground: Bool,
                                                              horizontalAccuracy: CLLocationAccuracy,
                                                              distanceFilterMeters: Int) -> Bool {
        guard applicationState != .active,
              updateSourceIsFrequentBackground else {
            return true
        }
        guard horizontalAccuracy.isFinite,
              horizontalAccuracy >= 0 else {
            return false
        }
        return horizontalAccuracy <= maximumAcceptedFrequentBackgroundAccuracy(
            distanceFilterMeters: distanceFilterMeters
        )
    }

    static func isFrequentBackgroundAccuracyRecoveryEligible(applicationState: UIApplication.State,
                                                            manualFrequentEnabled: Bool,
                                                            smartEnabled: Bool,
                                                            smartRuntimeActive: Bool,
                                                            distanceFilterMeters: Int) -> Bool {
        applicationState != .active &&
        !manualFrequentEnabled &&
        smartEnabled &&
        smartRuntimeActive &&
        FrequentBackgroundLocationDistanceFilter.normalized(distanceFilterMeters) == frequentBackgroundAccuracyRecoveryTriggerDistanceFilterMeters
    }

    static func accuracyRecoveryEvaluation(applicationState: UIApplication.State,
                                           manualFrequentEnabled: Bool,
                                           smartEnabled: Bool,
                                           smartRuntimeActive: Bool,
                                           distanceFilterMeters: Int,
                                           horizontalAccuracy: CLLocationAccuracy,
                                           currentPoorAccuracyStreak: Int,
                                           recoveryActive: Bool,
                                           recoveryStartedAt: Date?,
                                           lastRecoveryEndedAt: Date?,
                                           now: Date,
                                           recoveryDuration: TimeInterval = frequentBackgroundAccuracyRecoveryDuration,
                                           cooldown: TimeInterval = frequentBackgroundAccuracyRecoveryCooldown) -> AccuracyRecoveryEvaluation {
        let poorAccuracyStreak: Int
        if horizontalAccuracy.isFinite,
           horizontalAccuracy > frequentBackgroundAccuracyRecoveryPoorAccuracyThreshold {
            poorAccuracyStreak = max(0, currentPoorAccuracyStreak) + 1
        } else {
            poorAccuracyStreak = 0
        }

        let shouldStopForQuality = recoveryActive &&
        horizontalAccuracy.isFinite &&
        horizontalAccuracy >= 0 &&
        horizontalAccuracy <= frequentBackgroundAccuracyRecoveryTargetAccuracy

        let shouldStopForTimeout: Bool
        if recoveryActive,
           let recoveryStartedAt,
           recoveryDuration > 0 {
            shouldStopForTimeout = now.timeIntervalSince(recoveryStartedAt) >= recoveryDuration
        } else {
            shouldStopForTimeout = false
        }

        guard isFrequentBackgroundAccuracyRecoveryEligible(
            applicationState: applicationState,
            manualFrequentEnabled: manualFrequentEnabled,
            smartEnabled: smartEnabled,
            smartRuntimeActive: smartRuntimeActive,
            distanceFilterMeters: distanceFilterMeters
        ) else {
            return AccuracyRecoveryEvaluation(
                poorAccuracyStreak: poorAccuracyStreak,
                shouldStartRecovery: false,
                shouldStopRecovery: shouldStopForQuality || shouldStopForTimeout
            )
        }

        let cooldownElapsed: Bool
        if let lastRecoveryEndedAt,
           cooldown > 0 {
            cooldownElapsed = now.timeIntervalSince(lastRecoveryEndedAt) >= cooldown
        } else {
            cooldownElapsed = true
        }

        let shouldStartRecovery = !recoveryActive &&
        cooldownElapsed &&
        horizontalAccuracy.isFinite &&
        horizontalAccuracy >= 0 &&
        (
            horizontalAccuracy >= frequentBackgroundAccuracyRecoveryImmediateAccuracyThreshold ||
            poorAccuracyStreak >= 2
        )

        return AccuracyRecoveryEvaluation(
            poorAccuracyStreak: poorAccuracyStreak,
            shouldStartRecovery: shouldStartRecovery,
            shouldStopRecovery: shouldStopForQuality || shouldStopForTimeout
        )
    }

    private static func backgroundDesiredAccuracy(for distanceFilterMeters: Int) -> CLLocationAccuracy {
        distanceFilterMeters <= 50 ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyHundredMeters
    }
}
