import CoreLocation
import Testing
import UIKit
@testable import miataru

@Suite("Location tracking policy tests")
struct LocationTrackingPolicyTests {
    @Test("Background location configuration preserves significant-change default")
    func backgroundLocationConfigurationPreservesSignificantChangeDefault() {
        let defaultConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 25
        )
        #expect(defaultConfiguration.usesSignificantChangeMonitoring)
        #expect(defaultConfiguration.distanceFilter == kCLDistanceFilterNone)

        let hundredMeterConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 100
        )
        #expect(!hundredMeterConfiguration.usesSignificantChangeMonitoring)
        #expect(hundredMeterConfiguration.distanceFilter == 100)
        #expect(hundredMeterConfiguration.desiredAccuracy == kCLLocationAccuracyHundredMeters)

        let frequentConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50
        )
        #expect(!frequentConfiguration.usesSignificantChangeMonitoring)
        #expect(frequentConfiguration.distanceFilter == 50)
        #expect(frequentConfiguration.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)

        let normalizedConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 10
        )
        #expect(!normalizedConfiguration.usesSignificantChangeMonitoring)
        #expect(normalizedConfiguration.distanceFilter == 10)
        #expect(normalizedConfiguration.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)

        let fallbackConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 3
        )
        #expect(fallbackConfiguration.distanceFilter == CLLocationDistance(SettingsDefaultValues.frequentBackgroundLocationDistanceFilter))
        #expect(SettingsDefaultValues.locationDiagnosticsLoggingEnabled == false)
        #expect(SettingsDefaultValues.registrations[SettingsKeys.locationDiagnosticsLoggingEnabled] as? Bool == false)
    }

    @Test("Frequent background accuracy recovery temporarily uses precise configuration for 100m mode")
    func frequentBackgroundAccuracyRecoveryUsesPreciseConfigurationForHundredMeterMode() {
        let recoveryConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 100,
            accuracyRecoveryActive: true
        )
        #expect(!recoveryConfiguration.usesSignificantChangeMonitoring)
        #expect(recoveryConfiguration.distanceFilter == 10)
        #expect(recoveryConfiguration.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)

        let nonTriggerConfiguration = LocationTrackingPolicy.backgroundUpdateConfiguration(
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            accuracyRecoveryActive: true
        )
        #expect(nonTriggerConfiguration.distanceFilter == 50)
        #expect(nonTriggerConfiguration.desiredAccuracy == kCLLocationAccuracyNearestTenMeters)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: false,
            accuracyRecoveryActive: true
        ) == .backgroundFrequent(distanceFilter: 10, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))
    }

    @Test("Frequent background accuracy quality gates uploads and current location updates")
    func frequentBackgroundAccuracyQualityGatesUploadsAndCurrentLocationUpdates() {
        #expect(LocationTrackingPolicy.maximumAcceptedFrequentBackgroundAccuracy(distanceFilterMeters: 100) == 100)
        #expect(LocationTrackingPolicy.maximumAcceptedFrequentBackgroundAccuracy(distanceFilterMeters: 25) == 50)
        #expect(LocationTrackingPolicy.maximumAcceptedFrequentBackgroundAccuracy(distanceFilterMeters: 10) == 50)

        #expect(LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            horizontalAccuracy: 28.6,
            distanceFilterMeters: 100
        ))
        #expect(!LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            horizontalAccuracy: 69.4,
            distanceFilterMeters: 25
        ))
        #expect(!LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            horizontalAccuracy: 1_414,
            distanceFilterMeters: 100
        ))
        #expect(LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .active,
            updateSourceIsFrequentBackground: true,
            horizontalAccuracy: 1_414,
            distanceFilterMeters: 100
        ))
        #expect(LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .background,
            updateSourceIsFrequentBackground: false,
            horizontalAccuracy: 1_414,
            distanceFilterMeters: 100
        ))
        #expect(!LocationTrackingPolicy.isFrequentBackgroundLocationAccuracyAcceptable(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            horizontalAccuracy: -1,
            distanceFilterMeters: 100
        ))
    }

    @Test("Smart frequent accuracy recovery starts stops and cools down")
    func smartFrequentAccuracyRecoveryStartsStopsAndCoolsDown() {
        let now = Date(timeIntervalSince1970: 10_000)
        let immediate = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 1_414,
            currentPoorAccuracyStreak: 0,
            recoveryActive: false,
            recoveryStartedAt: nil,
            lastRecoveryEndedAt: nil,
            now: now
        )
        #expect(immediate.poorAccuracyStreak == 1)
        #expect(immediate.shouldStartRecovery)
        #expect(!immediate.shouldStopRecovery)

        let firstPoor = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 301,
            currentPoorAccuracyStreak: 0,
            recoveryActive: false,
            recoveryStartedAt: nil,
            lastRecoveryEndedAt: nil,
            now: now
        )
        #expect(firstPoor.poorAccuracyStreak == 1)
        #expect(!firstPoor.shouldStartRecovery)

        let secondPoor = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 301,
            currentPoorAccuracyStreak: firstPoor.poorAccuracyStreak,
            recoveryActive: false,
            recoveryStartedAt: nil,
            lastRecoveryEndedAt: nil,
            now: now.addingTimeInterval(1)
        )
        #expect(secondPoor.poorAccuracyStreak == 2)
        #expect(secondPoor.shouldStartRecovery)

        let manualMode = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 1_414,
            currentPoorAccuracyStreak: 0,
            recoveryActive: false,
            recoveryStartedAt: nil,
            lastRecoveryEndedAt: nil,
            now: now
        )
        #expect(!manualMode.shouldStartRecovery)

        let cooldown = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 1_414,
            currentPoorAccuracyStreak: 0,
            recoveryActive: false,
            recoveryStartedAt: nil,
            lastRecoveryEndedAt: now.addingTimeInterval(-60),
            now: now
        )
        #expect(!cooldown.shouldStartRecovery)

        let recovered = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 80,
            currentPoorAccuracyStreak: 2,
            recoveryActive: true,
            recoveryStartedAt: now.addingTimeInterval(-30),
            lastRecoveryEndedAt: nil,
            now: now
        )
        #expect(recovered.poorAccuracyStreak == 0)
        #expect(recovered.shouldStopRecovery)

        let timedOut = LocationTrackingPolicy.accuracyRecoveryEvaluation(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            distanceFilterMeters: 100,
            horizontalAccuracy: 800,
            currentPoorAccuracyStreak: 2,
            recoveryActive: true,
            recoveryStartedAt: now.addingTimeInterval(-121),
            lastRecoveryEndedAt: nil,
            now: now
        )
        #expect(timedOut.shouldStopRecovery)
    }

    @Test("Navigation never overrides the existing background tracking policy")
    func navigationNeverOverridesExistingBackgroundTrackingPolicy() {
        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: false,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: true
        ) == .stopped)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .denied,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: true
        ) == .stopped)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .active,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: true
        ) == .foregroundHighAccuracy)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 25,
            hasNavigationLocationSession: true
        ) == .backgroundSignificantChange)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .stopped)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            applicationState: .active,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundFrequent(distanceFilter: 50, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))

        let smartFrequentEnabled = LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true
        )
        #expect(smartFrequentEnabled)
        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: smartFrequentEnabled,
            distanceFilterMeters: 10,
            hasNavigationLocationSession: true
        ) == .backgroundFrequent(distanceFilter: 10, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundSignificantChange)

        #expect(!LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: .backgroundSignificantChange))
    }

    @Test("Ending background navigation restores Significant-Change tracking")
    func endingBackgroundNavigationRestoresSignificantChangeTracking() {
        let modeAfterNavigationEnds = LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: false,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        )

        #expect(modeAfterNavigationEnds == .backgroundSignificantChange)
        #expect(LocationTrackingPolicy.locationServiceCommandPlan(
            for: modeAfterNavigationEnds,
            shouldMaintainRecoveryAnchor: true
        ) == .init(
            primary: [.stopUpdatingLocation, .startMonitoringSignificantLocationChanges],
            secondary: [.stopUpdatingLocation, .stopMonitoringSignificantLocationChanges]
        ))
        #expect(!LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: modeAfterNavigationEnds))
    }

    @Test("Server update pause keeps local tracking but downgrades frequent background mode")
    func trackingPauseDoesNotStopLocalTrackingDecisions() {
        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: true,
            trackingPaused: true
        ) == .applyTrackingMode)

        #expect(LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            trackingPaused: true
        ))

        #expect(LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: true
        ))

        #expect(LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: true
        ))

        #expect(LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: true
        ) == false)

        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: true
        ))

        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: false,
            isTracking: false,
            frequentUpdatesEnabled: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: false
        ))

        #expect(LocationTrackingPolicy.backgroundTrackingDisplayMode(
            applicationState: .background,
            smartEnabled: true,
            manualFrequentEnabled: true,
            smartRuntimeActive: true,
            trackingPaused: true
        ) == .significantChange)

        #expect(!LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true,
            trackingPaused: true
        ))

        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
                manualFrequentEnabled: true,
                smartEnabled: true,
                smartRuntimeActive: true,
                trackingPaused: true
            ),
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundSignificantChange)
    }

    @Test("Tracking policy resumes normal decisions when pause is not active")
    func trackingPolicyResumesNormalDecisionsWhenPauseIsNotActive() {
        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: false,
            trackingPaused: false
        ) == .startTracking)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: true,
            trackingPaused: false
        ) == .applyTrackingMode)

        #expect(LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            trackingPaused: false
        ))

        #expect(LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            trackingPaused: false
        ))
    }

    @Test("Location service command plan keeps primary recovery anchor separate from frequent updates")
    func locationServiceCommandPlanKeepsPrimaryRecoveryAnchorSeparateFromFrequentUpdates() {
        let frequentPlan = LocationTrackingPolicy.locationServiceCommandPlan(
            for: .backgroundFrequent(
                distanceFilter: 50,
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters
            ),
            shouldMaintainRecoveryAnchor: true
        )
        #expect(frequentPlan.primary == [
            .stopUpdatingLocation,
            .startMonitoringSignificantLocationChanges
        ])
        #expect(frequentPlan.secondary == [
            .stopMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: true,
                distanceFilter: 50,
                desiredAccuracy: kCLLocationAccuracyNearestTenMeters
            )
        ])

        let standardPlan = LocationTrackingPolicy.locationServiceCommandPlan(
            for: .backgroundSignificantChange,
            shouldMaintainRecoveryAnchor: true
        )
        #expect(standardPlan.primary == [
            .stopUpdatingLocation,
            .startMonitoringSignificantLocationChanges
        ])
        #expect(standardPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let foregroundPlan = LocationTrackingPolicy.locationServiceCommandPlan(
            for: .foregroundHighAccuracy,
            shouldMaintainRecoveryAnchor: true
        )
        #expect(foregroundPlan.primary == [
            .startMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: false,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyBestForNavigation
            )
        ])
        #expect(foregroundPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let foregroundWhenInUsePlan = LocationTrackingPolicy.locationServiceCommandPlan(
            for: .foregroundHighAccuracy,
            shouldMaintainRecoveryAnchor: false
        )
        #expect(foregroundWhenInUsePlan.primary == [
            .stopMonitoringSignificantLocationChanges,
            .startUpdatingLocation(
                allowsBackground: false,
                distanceFilter: kCLDistanceFilterNone,
                desiredAccuracy: kCLLocationAccuracyBestForNavigation
            )
        ])
        #expect(foregroundWhenInUsePlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])

        let stoppedPlan = LocationTrackingPolicy.locationServiceCommandPlan(
            for: .stopped,
            shouldMaintainRecoveryAnchor: false
        )
        #expect(stoppedPlan.primary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])
        #expect(stoppedPlan.secondary == [
            .stopUpdatingLocation,
            .stopMonitoringSignificantLocationChanges
        ])
    }

    @Test("Primary significant-change callback reasserts frequent background for effective frequent sessions")
    func primarySignificantChangeCallbackReassertsEffectiveFrequentSessions() {
        #expect(LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: .background,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: true,
            updateSourceIsPrimary: true
        ))

        #expect(LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: .background,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: false,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: .active,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: .background,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: true,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertFrequentBackgroundUpdatesAfterPrimarySignificantChangeCallback(
            applicationState: .background,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            frequentBackgroundStandardUpdatesActiveInCurrentProcess: true,
            updateSourceIsPrimary: false
        ))

        #expect(LocationTrackingPolicy.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            updateSourceIsFrequentBackground: true
        ))
        #expect(!LocationTrackingPolicy.shouldSuppressStaleFrequentBackgroundCallback(
            allowNextStaleCallback: true
        ))
        #expect(LocationTrackingPolicy.shouldSuppressStaleFrequentBackgroundCallback(
            allowNextStaleCallback: false
        ))
        #expect(LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .background,
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            shouldMaintainRecoveryAnchor: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .background,
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            shouldMaintainRecoveryAnchor: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .active,
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            shouldMaintainRecoveryAnchor: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .background,
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: true,
            shouldMaintainRecoveryAnchor: true,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .background,
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            shouldMaintainRecoveryAnchor: false,
            updateSourceIsPrimary: true
        ))
        #expect(!LocationTrackingPolicy.shouldReassertStandardSignificantChangeAfterPrimaryCallback(
            applicationState: .background,
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            shouldMaintainRecoveryAnchor: true,
            updateSourceIsPrimary: false
        ))
        #expect(!LocationTrackingPolicy.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: true,
            didSwitchFrequentBackgroundMode: false,
            updateSourceIsFrequentBackground: true
        ))
        #expect(!LocationTrackingPolicy.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: true,
            updateSourceIsFrequentBackground: true
        ))
        #expect(!LocationTrackingPolicy.shouldCleanUpStaleFrequentBackgroundCallback(
            frequentUpdatesEnabled: false,
            didSwitchFrequentBackgroundMode: false,
            updateSourceIsFrequentBackground: false
        ))
    }

    @Test("Background lifecycle context keeps frequent mode active even before UIKit reports background")
    func backgroundLifecycleContextKeepsFrequentModeActiveBeforeUIKitStateCatchesUp() {
        let forcedBackgroundState = LocationTrackingPolicy.effectiveApplicationState(
            currentState: .active,
            context: .forceBackground
        )
        #expect(forcedBackgroundState == .background)
        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: forcedBackgroundState,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .backgroundFrequent(distanceFilter: 50, desiredAccuracy: kCLLocationAccuracyNearestTenMeters))

        let forcedForegroundState = LocationTrackingPolicy.effectiveApplicationState(
            currentState: .background,
            context: .forceForeground
        )
        #expect(forcedForegroundState == .active)
        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: forcedForegroundState,
            frequentUpdatesEnabled: true,
            distanceFilterMeters: 50,
            hasNavigationLocationSession: false
        ) == .foregroundHighAccuracy)
    }

    @Test("Manual frequent mode overrides smart frequent runtime")
    func manualFrequentModeOverridesSmartFrequentRuntime() {
        #expect(LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: false,
            trackingPaused: false
        ))
        #expect(LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true,
            trackingPaused: false
        ))
        #expect(!LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: false,
            trackingPaused: false
        ))
        #expect(!LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true,
            trackingPaused: true
        ))

        #expect(LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(
            for: .backgroundFrequent(
                distanceFilter: 100,
                desiredAccuracy: kCLLocationAccuracyHundredMeters
            )
        ))
        #expect(!LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: .backgroundSignificantChange))
        #expect(!LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: .foregroundHighAccuracy))
        #expect(!LocationTrackingPolicy.shouldShowBackgroundLocationIndicator(for: .stopped))

        #expect(LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: .background,
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true
        ) == .manualFrequent)
        #expect(LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true
        ) == .smartFrequent)
        #expect(LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: .background,
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: false
        ) == .significantChange)
        #expect(LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: .active,
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true
        ) == .foregroundLive)
        #expect(LocationTrackingPolicy.locationUpdateCounterMode(
            applicationState: .background,
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: true,
            trackingPaused: true
        ) == .significantChange)

        let manualEffective = LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: true,
            smartEnabled: true,
            smartRuntimeActive: false
        )
        let smartEffective = LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true
        )
        #expect(LocationTrackingPolicy.frequentBackgroundLocationDeliveryDelay(
            applicationState: .background,
            frequentUpdatesEnabled: manualEffective,
            deliveryMode: .everyFiveMinutes
        ) == 300)
        #expect(LocationTrackingPolicy.frequentBackgroundLocationDeliveryDelay(
            applicationState: .background,
            frequentUpdatesEnabled: smartEffective,
            deliveryMode: .everyFiveMinutes
        ) == 300)
        #expect(LocationTrackingPolicy.frequentBackgroundVisitorCheckMinimumInterval(
            applicationState: .background,
            frequentUpdatesEnabled: manualEffective,
            visitorCheckInterval: .tenMinutes
        ) == 600)
        #expect(LocationTrackingPolicy.frequentBackgroundVisitorCheckMinimumInterval(
            applicationState: .background,
            frequentUpdatesEnabled: smartEffective,
            visitorCheckInterval: .tenMinutes
        ) == 600)
        #expect(LocationTrackingPolicy.frequentBackgroundVisitorChecksEnabled(
            applicationState: .background,
            frequentUpdatesEnabled: smartEffective
        ))
        #expect(!LocationTrackingPolicy.frequentBackgroundVisitorChecksEnabled(
            applicationState: .active,
            frequentUpdatesEnabled: smartEffective
        ))
        #expect(LocationTrackingPolicy.frequentBackgroundLocationDeliveryDelay(
            applicationState: .active,
            frequentUpdatesEnabled: smartEffective,
            deliveryMode: .everyFiveMinutes
        ) == nil)
    }

    @Test("Significant-change recovery anchor is kept only for active Always-authorized tracking")
    func significantChangeRecoveryAnchorRequiresActiveAlwaysAuthorizedTracking() {
        #expect(LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))

        #expect(!LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: false,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: true,
            isTracking: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: false,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: false,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedWhenInUse,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedWhenInUse,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainSignificantChangeRecoveryAnchor(
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: true
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainLocationServiceSession(
            trackAndReportLocation: true,
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: true
        ))
        #expect(!LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: true
        ))
    }

    @Test("Tracking is restored after launch only when the user setting still permits it")
    func trackingRestoreAfterLaunchRequiresEnabledTrackingWithoutAuthBlock() {
        #expect(LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: false,
            deviceKeyAuthBlocked: false
        ))
        #expect(!LocationTrackingPolicy.shouldRestoreTrackingAfterLaunch(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: true
        ))
        #expect(AppDelegate.didLaunchForLocation([.location: true]))
        #expect(!AppDelegate.didLaunchForLocation(nil))
        #expect(AppDelegate.shouldRestoreLocationLaunch([.location: true], didRestore: false))
        #expect(!AppDelegate.shouldRestoreLocationLaunch([.location: true], didRestore: true))
        #expect(!AppDelegate.shouldRestoreLocationLaunch(nil, didRestore: false))
    }

    @Test("Tracking reconcile disables unavailable authorization but keeps When-In-Use intent")
    func trackingReconcileDisablesUnavailableAuthorizationButKeepsWhenInUseIntent() {
        #expect(LocationTrackingPolicy.shouldDisableTrackingPreference(authorizationStatus: .denied))
        #expect(LocationTrackingPolicy.shouldDisableTrackingPreference(authorizationStatus: .restricted))
        #expect(!LocationTrackingPolicy.shouldDisableTrackingPreference(authorizationStatus: .authorizedWhenInUse))
        #expect(!LocationTrackingPolicy.shouldDisableTrackingPreference(authorizationStatus: .authorizedAlways))

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .denied,
            isTracking: true
        ) == .stopAuthorizationUnavailable)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .restricted,
            isTracking: false
        ) == .stopAuthorizationUnavailable)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedWhenInUse,
            isTracking: false
        ) == .startTracking)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: false
        ) == .startTracking)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: true
        ) == .applyTrackingMode)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: false,
            deviceKeyAuthBlocked: false,
            authorizationStatus: .authorizedAlways,
            isTracking: true
        ) == .stopTrackingDisabled)

        #expect(LocationTrackingPolicy.trackingReconcileAction(
            trackAndReportLocation: true,
            deviceKeyAuthBlocked: true,
            authorizationStatus: .authorizedAlways,
            isTracking: true
        ) == .stopDeviceKeyBlocked)
    }

    @Test("Background battery threshold only disables frequent mode when active and known")
    func backgroundBatteryThresholdOnlyDisablesFrequentModeWhenActiveAndKnown() {
        #expect(LocationTrackingPolicy.batteryPercent(from: 0.301) == 30)
        #expect(LocationTrackingPolicy.batteryPercent(from: -1) == nil)

        #expect(LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 30,
            thresholdPercent: 30
        ))
        #expect(LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 29,
            thresholdPercent: 25
        ))
        #expect(!LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 31,
            thresholdPercent: 30
        ))
        #expect(!LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: false,
            batteryPercent: 20,
            thresholdPercent: 30
        ))
        #expect(!LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: nil,
            thresholdPercent: 30
        ))
    }

    @Test("Frequent background one-shot request requires an active delegate-ready frequent service")
    func frequentBackgroundOneShotRequestRequiresActiveDelegateReadyFrequentService() {
        #expect(LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: true,
            frequentBackgroundStandardUpdatesActive: true,
            delegateReady: true
        ))

        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: false,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: true,
            frequentBackgroundStandardUpdatesActive: true,
            delegateReady: true
        ))
        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedWhenInUse,
            frequentUpdatesEnabled: true,
            frequentBackgroundStandardUpdatesActive: true,
            delegateReady: true
        ))
        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: false,
            frequentBackgroundStandardUpdatesActive: true,
            delegateReady: true
        ))
        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: true,
            frequentBackgroundStandardUpdatesActive: false,
            delegateReady: true
        ))
        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: true,
            frequentBackgroundStandardUpdatesActive: true,
            delegateReady: false
        ))
    }

    @Test("Low-battery smart frequent deactivation blocks watchdog one-shot request")
    func lowBatterySmartFrequentDeactivationBlocksWatchdogOneShotRequest() {
        #expect(LocationTrackingPolicy.shouldDisableFrequentBackgroundUpdatesForBattery(
            frequentUpdatesEnabled: true,
            batteryPercent: 30,
            thresholdPercent: 30
        ))

        let effectiveFrequentAfterDeactivation = LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: false
        )
        #expect(!effectiveFrequentAfterDeactivation)
        #expect(!LocationTrackingPolicy.shouldRequestFrequentBackgroundOneShotLocation(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            frequentUpdatesEnabled: effectiveFrequentAfterDeactivation,
            frequentBackgroundStandardUpdatesActive: false,
            delegateReady: false
        ))
    }
}
