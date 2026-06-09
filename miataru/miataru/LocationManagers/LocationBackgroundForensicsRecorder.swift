/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationBackgroundForensicsRecorder.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

final class LocationBackgroundForensicsRecorder {
    private static let significantChangeRearmedBuildIdentifierKey = "miataru_significantChangeRearmedBuildIdentifier"
    private static let lastSignificantChangeRearmStatusKey = "miataru_lastSignificantChangeRearmStatus"
    private static let backgroundTrackingForensicStateKey = "miataru_backgroundTrackingForensicState"

    private let userDefaults: UserDefaults
    private let diagnosticsLog: LocationDiagnosticsLogStore

    private(set) var state: LocationBackgroundForensics.State
    private(set) var lastSignificantChangeRearmStatus: LocationSignificantChangeRearmStatus?

    init(userDefaults: UserDefaults = .standard,
         diagnosticsLog: LocationDiagnosticsLogStore = .shared) {
        self.userDefaults = userDefaults
        self.diagnosticsLog = diagnosticsLog
        self.lastSignificantChangeRearmStatus = Self.loadLastSignificantChangeRearmStatus(from: userDefaults)
        self.state = Self.loadBackgroundTrackingForensicState(from: userDefaults)
    }

    func significantChangeRearmDecision(buildIdentifier: String,
                                        reason: String,
                                        trackAndReportLocation: Bool,
                                        authorizationStatus: CLAuthorizationStatus,
                                        deviceKeyAuthBlocked: Bool,
                                        now: Date = Date()) -> LocationBackgroundForensics.SignificantChangeRearmDecision {
        LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: buildIdentifier,
            alreadyRearmedBuildIdentifier: userDefaults.string(forKey: Self.significantChangeRearmedBuildIdentifierKey),
            reason: reason,
            trackAndReportLocation: trackAndReportLocation,
            authorizationStatus: authorizationStatus,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            now: now
        )
    }

    func recordSignificantChangeRearmStatus(_ status: LocationSignificantChangeRearmStatus) {
        lastSignificantChangeRearmStatus = status
        persistLastSignificantChangeRearmStatus(status)
        state.lastSignificantChangeRearmAt = status.timestamp
        persistState()
    }

    func markSignificantChangeRearmed(buildIdentifier: String) {
        userDefaults.set(buildIdentifier, forKey: Self.significantChangeRearmedBuildIdentifierKey)
    }

    func recordRestoreAfterLaunch(trigger: String, now: Date = Date()) {
        state.lastRestoreAfterLaunchAt = now
        evaluateGap(trigger: trigger, now: now)
        persistState()
    }

    func recordModeResolution(mode: LocationTrackingPolicy.TrackingMode,
                              applicationState: UIApplication.State,
                              reason: String,
                              now: Date = Date()) {
        let expectedMode = trackingModeForensicDescription(mode)
        state.currentExpectedMode = expectedMode
        state.lastModeAssertionAt = now
        state.lastModeAssertionReason = reason
        state.lastKnownApplicationState = applicationState.rawValue

        switch mode {
        case .backgroundSignificantChange, .backgroundFrequent:
            if state.backgroundTrackingExpectedSince == nil {
                state.backgroundTrackingExpectedSince = now
            }
        case .foregroundHighAccuracy, .stopped:
            state.backgroundTrackingExpectedSince = nil
        }
        persistState()
    }

    func recordServiceAssertion(mode: LocationTrackingPolicy.TrackingMode, now: Date = Date()) {
        switch mode {
        case .backgroundSignificantChange, .backgroundFrequent:
            state.lastServiceAssertionAt = now
            state.backgroundServicesAsserted = true
        case .foregroundHighAccuracy, .stopped:
            state.backgroundServicesAsserted = false
        }
        persistState()
    }

    func recordForegroundOpen(trigger: String, now: Date = Date()) {
        evaluateGap(trigger: trigger, now: now, prepareForegroundRecovery: true)
        state.lastForegroundOpenAt = now
        persistState()
    }

    func evaluateGap(trigger: String,
                     now: Date = Date(),
                     prepareForegroundRecovery: Bool = false) {
        guard let assessment = LocationBackgroundForensics.gapAssessment(
            state: state,
            now: now
        ) else {
            if prepareForegroundRecovery {
                resetPendingForegroundRecovery()
                persistState()
            }
            return
        }

        if let lastLoggedAt = state.lastBackgroundGapLoggedAt,
           now.timeIntervalSince(lastLoggedAt) < LocationBackgroundForensics.frequentBackgroundGapThreshold {
            if prepareForegroundRecovery {
                preparePendingForegroundRecovery(assessment: assessment, now: now)
            }
            persistState()
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
                    state.backgroundTrackingExpectedSince != nil,
                    detail: "Expected since \(String(describing: state.backgroundTrackingExpectedSince))."
                ),
                LocationDiagnosticsLogStore.check(
                    "gapExceedsThreshold",
                    true,
                    detail: "\(assessment.gapSeconds)s >= \(Int(LocationBackgroundForensics.frequentBackgroundGapThreshold))s."
                )
            ],
            context: forensicGapContext(assessment: assessment)
        )
        state.lastBackgroundGapLoggedAt = now
        if prepareForegroundRecovery {
            preparePendingForegroundRecovery(assessment: assessment, now: now)
        }
        persistState()
    }

    func recordLocationCallback(applicationState: UIApplication.State,
                                sourceRawValue: String,
                                isPrimarySource: Bool,
                                timestamp: Date = Date()) {
        state.lastKnownApplicationState = applicationState.rawValue
        state.lastKnownSource = sourceRawValue
        if applicationState == .active {
            if state.pendingForegroundRecoveryStartedAt != nil,
               isPrimarySource {
                state.foregroundBurstCallbackCount += 1
            }
        } else {
            state.lastBackgroundCallbackAt = timestamp
        }
        persistState()
    }

    func recordAcceptedLocation(applicationState: UIApplication.State,
                                isPrimarySource: Bool,
                                timestamp: Date = Date()) {
        if applicationState == .active {
            if state.pendingForegroundRecoveryStartedAt != nil,
               isPrimarySource {
                state.foregroundBurstAcceptedCount += 1
                maybeLogForegroundRecoveryBurst(now: timestamp)
            }
        } else {
            state.lastAcceptedBackgroundLocationAt = timestamp
        }
        persistState()
    }

    func recordUpload(applicationState: UIApplication.State, timestamp: Date = Date()) {
        if applicationState == .active {
            if state.pendingForegroundRecoveryStartedAt != nil {
                state.foregroundBurstUploadCount += 1
                maybeLogForegroundRecoveryBurst(now: timestamp)
            }
        } else {
            state.lastBackgroundUploadAt = timestamp
        }
        persistState()
    }

    func recordSmartActivation(at timestamp: Date) {
        state.lastSmartActivationAt = timestamp
        persistState()
    }

    func recordSmartDeactivation(at timestamp: Date) {
        state.lastSmartDeactivationAt = timestamp
        persistState()
    }

    private func persistLastSignificantChangeRearmStatus(_ status: LocationSignificantChangeRearmStatus) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(status) {
            userDefaults.set(data, forKey: Self.lastSignificantChangeRearmStatusKey)
        }
    }

    private static func loadLastSignificantChangeRearmStatus(from userDefaults: UserDefaults) -> LocationSignificantChangeRearmStatus? {
        guard let data = userDefaults.data(forKey: lastSignificantChangeRearmStatusKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocationSignificantChangeRearmStatus.self, from: data)
    }

    private func persistState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(state) {
            userDefaults.set(data, forKey: Self.backgroundTrackingForensicStateKey)
        }
    }

    private static func loadBackgroundTrackingForensicState(from userDefaults: UserDefaults) -> LocationBackgroundForensics.State {
        guard let data = userDefaults.data(forKey: backgroundTrackingForensicStateKey) else {
            return LocationBackgroundForensics.State()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(LocationBackgroundForensics.State.self, from: data)) ?? LocationBackgroundForensics.State()
    }

    private func trackingModeForensicDescription(_ mode: LocationTrackingPolicy.TrackingMode) -> String {
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

    private func preparePendingForegroundRecovery(assessment: LocationBackgroundForensics.GapAssessment, now: Date) {
        state.pendingForegroundRecoveryStartedAt = now
        state.pendingForegroundRecoveryPreviousMode = state.currentExpectedMode
        state.pendingForegroundRecoveryGapSeconds = assessment.gapSeconds
        state.pendingForegroundRecoveryLastBackgroundCallbackAt = state.lastBackgroundCallbackAt
        state.pendingForegroundRecoveryLastBackgroundUploadAt = state.lastBackgroundUploadAt
        state.pendingForegroundRecoveryBackgroundServicesAsserted = state.backgroundServicesAsserted
        state.foregroundBurstCallbackCount = 0
        state.foregroundBurstAcceptedCount = 0
        state.foregroundBurstUploadCount = 0
        state.foregroundRecoveryBurstLoggedAt = nil
    }

    private func resetPendingForegroundRecovery() {
        state.pendingForegroundRecoveryStartedAt = nil
        state.pendingForegroundRecoveryPreviousMode = nil
        state.pendingForegroundRecoveryGapSeconds = nil
        state.pendingForegroundRecoveryLastBackgroundCallbackAt = nil
        state.pendingForegroundRecoveryLastBackgroundUploadAt = nil
        state.pendingForegroundRecoveryBackgroundServicesAsserted = nil
        state.foregroundBurstCallbackCount = 0
        state.foregroundBurstAcceptedCount = 0
        state.foregroundBurstUploadCount = 0
        state.foregroundRecoveryBurstLoggedAt = nil
    }

    private func forensicGapContext(assessment: LocationBackgroundForensics.GapAssessment) -> [String: LocationDiagnosticsValue] {
        var context: [String: LocationDiagnosticsValue] = [
            "gapSeconds": .integer(assessment.gapSeconds),
            "currentExpectedMode": .string(state.currentExpectedMode ?? "unknown"),
            "backgroundServicesAsserted": .bool(state.backgroundServicesAsserted),
            "gapReferenceAt": .string(ISO8601DateFormatter().string(from: assessment.referenceAt)),
            "gapReferenceReason": .string(assessment.referenceReason)
        ]
        if let expectedSince = state.backgroundTrackingExpectedSince {
            context["backgroundTrackingExpectedSince"] = .string(ISO8601DateFormatter().string(from: expectedSince))
        }
        if let lastObservedAt = assessment.lastObservedAt {
            context["lastObservedBackgroundActivityAt"] = .string(ISO8601DateFormatter().string(from: lastObservedAt))
        }
        if let lastCallbackAt = state.lastBackgroundCallbackAt {
            context["lastBackgroundCallbackAt"] = .string(ISO8601DateFormatter().string(from: lastCallbackAt))
        }
        if let lastUploadAt = state.lastBackgroundUploadAt {
            context["lastBackgroundUploadAt"] = .string(ISO8601DateFormatter().string(from: lastUploadAt))
        }
        return context
    }

    private func maybeLogForegroundRecoveryBurst(now: Date = Date()) {
        guard LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: state.pendingForegroundRecoveryStartedAt,
            recoveryAlreadyLoggedAt: state.foregroundRecoveryBurstLoggedAt,
            now: now,
            acceptedCount: state.foregroundBurstAcceptedCount,
            uploadCount: state.foregroundBurstUploadCount
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
                    detail: "Foreground activity occurred within \(Int(LocationBackgroundForensics.foregroundRecoveryBurstWindow))s."
                )
            ],
            context: foregroundRecoveryContext()
        )
        state.foregroundRecoveryBurstLoggedAt = now
        persistState()
    }

    private func foregroundRecoveryContext() -> [String: LocationDiagnosticsValue] {
        var context: [String: LocationDiagnosticsValue] = [
            "previousExpectedMode": .string(state.pendingForegroundRecoveryPreviousMode ?? "unknown"),
            "gapSeconds": .integer(state.pendingForegroundRecoveryGapSeconds ?? 0),
            "foregroundCallbackCount": .integer(state.foregroundBurstCallbackCount),
            "foregroundAcceptedCount": .integer(state.foregroundBurstAcceptedCount),
            "foregroundUploadCount": .integer(state.foregroundBurstUploadCount),
            "backgroundServicesAsserted": .bool(state.pendingForegroundRecoveryBackgroundServicesAsserted ?? state.backgroundServicesAsserted)
        ]
        if let startedAt = state.pendingForegroundRecoveryStartedAt {
            context["foregroundOpenedAt"] = .string(ISO8601DateFormatter().string(from: startedAt))
        }
        if let lastCallbackAt = state.pendingForegroundRecoveryLastBackgroundCallbackAt {
            context["lastBackgroundCallbackAt"] = .string(ISO8601DateFormatter().string(from: lastCallbackAt))
        }
        if let lastUploadAt = state.pendingForegroundRecoveryLastBackgroundUploadAt {
            context["lastBackgroundUploadAt"] = .string(ISO8601DateFormatter().string(from: lastUploadAt))
        }
        return context
    }
}
