/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationManager+Types.swift
 * miataru
 */

import Foundation
import CoreLocation

extension LocationManager {
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
    static let maximumSmartFrequentBackgroundStateAccuracy: CLLocationAccuracy = SmartFrequentBackgroundPolicy.maximumUsableLocationAccuracy
    static let smartFrequentBackgroundProbeWatchdogInterval = smartFrequentBackgroundRuntimeWatchdogInterval
    static let maximumSmartFrequentBackgroundProbeRecoveryAttempts = maximumSmartFrequentBackgroundRuntimeRecoveryAttempts
    static let frequentBackgroundAccuracyRecoveryDuration: TimeInterval = LocationTrackingPolicy.frequentBackgroundAccuracyRecoveryDuration

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
    typealias FrequentBackgroundAccuracyRecoveryEvaluation = LocationTrackingPolicy.AccuracyRecoveryEvaluation
    typealias TrackingMode = LocationTrackingPolicy.TrackingMode
    typealias SmartFrequentRuntimePhase = SmartFrequentBackgroundPolicy.RuntimePhase
    typealias SmartFrequentActivationEvidenceKind = SmartFrequentBackgroundPolicy.ActivationEvidenceKind
    typealias LocationSampleProcessingDecision = LocationSamplePolicy.ProcessingDecision
    typealias SmartFrequentBackgroundWatchdogAction = SmartFrequentBackgroundPolicy.WatchdogAction
    typealias SmartFrequentBackgroundInactivityTimerAction = SmartFrequentBackgroundPolicy.InactivityTimerAction
    typealias SmartFrequentBackgroundRestartRecoveryAction = SmartFrequentBackgroundPolicy.RestartRecoveryAction
    typealias SmartFrequentActivationEvidence = SmartFrequentBackgroundPolicy.ActivationEvidence
    typealias TrackingApplicationStateContext = LocationTrackingPolicy.ApplicationStateContext
    typealias TrackingReconcileAction = LocationTrackingPolicy.ReconcileAction
    typealias PrimaryLocationServiceCommand = LocationTrackingPolicy.PrimaryLocationServiceCommand
    typealias SecondaryLocationServiceCommand = LocationTrackingPolicy.SecondaryLocationServiceCommand
    typealias LocationServiceCommandPlan = LocationTrackingPolicy.ServiceCommandPlan
    typealias SignificantChangeRearmDecision = LocationBackgroundForensics.SignificantChangeRearmDecision
    typealias LocationSubmissionDeduplicationKey = LocationSamplePolicy.SubmissionDeduplicationKey

}
