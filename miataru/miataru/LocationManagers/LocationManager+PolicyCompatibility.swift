/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationManager+PolicyCompatibility.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

extension LocationManager {
    static func activityTypeFrom(_ value: Int) -> CLActivityType {
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

}
