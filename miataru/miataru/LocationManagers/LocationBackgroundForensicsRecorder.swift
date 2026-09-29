/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationBackgroundForensicsRecorder.swift
 * miataru
 */

import Foundation
import CoreLocation
import UIKit

struct LocationDiagnosticsPowerReading {
    let batteryMonitoringEnabled: Bool
    let batteryLevel: Float
    let batteryState: UIDevice.BatteryState
    let lowPowerModeEnabled: Bool

    static func current() -> LocationDiagnosticsPowerReading {
        return LocationDiagnosticsPowerReading(
            batteryMonitoringEnabled: UIDevice.current.isBatteryMonitoringEnabled,
            batteryLevel: UIDevice.current.batteryLevel,
            batteryState: UIDevice.current.batteryState,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}

final class LocationBackgroundForensicsRecorder {
    private static let significantChangeRearmedBuildIdentifierKey = "miataru_significantChangeRearmedBuildIdentifier"
    private static let lastSignificantChangeRearmStatusKey = "miataru_lastSignificantChangeRearmStatus"
    private static let backgroundTrackingForensicStateKey = "miataru_backgroundTrackingForensicState"

    private let userDefaults: UserDefaults
    private let diagnosticsLog: LocationDiagnosticsLogStore
    private let powerReading: () -> LocationDiagnosticsPowerReading

    private static let powerSampleInterval: TimeInterval = 30 * 60
    private var lastPowerSampleAt: Date?
    private var lastPowerSampleMode: String?
    private var callbacksSincePowerSample = 0
    private var acceptedLocationsSincePowerSample = 0
    private var directUploadAcknowledgementsSincePowerSample = 0

    private(set) var state: LocationBackgroundForensics.State
    private(set) var lastSignificantChangeRearmStatus: LocationSignificantChangeRearmStatus?

    init(userDefaults: UserDefaults = .standard,
         diagnosticsLog: LocationDiagnosticsLogStore = .shared,
         powerReading: @escaping () -> LocationDiagnosticsPowerReading = LocationDiagnosticsPowerReading.current) {
        self.userDefaults = userDefaults
        self.diagnosticsLog = diagnosticsLog
        self.powerReading = powerReading
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
        recordPowerSample(reason: "restoreAfterLaunch", now: now, force: true)
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
        recordPowerSample(reason: "modeResolution", applicationState: applicationState, now: now)
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
        recordPowerSample(reason: "foregroundOpen", applicationState: .active, now: now, force: true)
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
            context: forensicGapContext(assessment: assessment),
            persistence: .immediate
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
        if diagnosticsLog.isEnabled {
            callbacksSincePowerSample += 1
            recordPowerSample(reason: "locationCallback", applicationState: applicationState, now: timestamp)
        }
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
        if diagnosticsLog.isEnabled {
            acceptedLocationsSincePowerSample += 1
        }
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
        if diagnosticsLog.isEnabled {
            directUploadAcknowledgementsSincePowerSample += 1
        }
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

    private func recordPowerSample(reason: String,
                                   applicationState: UIApplication.State? = nil,
                                   now: Date,
                                   force: Bool = false) {
        guard diagnosticsLog.isEnabled else { return }

        let mode = state.currentExpectedMode ?? "unknown"
        let modeChanged = mode != lastPowerSampleMode
        let elapsed = lastPowerSampleAt.map { now.timeIntervalSince($0) }
        let intervalDue = elapsed.map { $0 < 0 || $0 >= Self.powerSampleInterval } ?? true
        guard force || modeChanged || intervalDue else {
            return
        }

        let reading = powerReading()
        let batteryPercent: LocationDiagnosticsValue = reading.batteryLevel.isFinite && reading.batteryLevel >= 0
            ? .integer(Int((min(reading.batteryLevel, 1) * 100).rounded()))
            : .string("unknown")
        let batteryState: String
        switch reading.batteryState {
        case .charging: batteryState = "charging"
        case .full: batteryState = "full"
        case .unplugged: batteryState = "unplugged"
        case .unknown: batteryState = "unknown"
        @unknown default: batteryState = "unknown"
        }

        var context: [String: LocationDiagnosticsValue] = [
            "expectedMode": .string(mode),
            "applicationState": .integer((applicationState?.rawValue ?? state.lastKnownApplicationState) ?? -1),
            "batteryMonitoringEnabled": .bool(reading.batteryMonitoringEnabled),
            "batteryPercent": batteryPercent,
            "batteryState": .string(batteryState),
            "lowPowerModeEnabled": .bool(reading.lowPowerModeEnabled),
            "callbacksSincePreviousSample": .integer(callbacksSincePowerSample),
            "acceptedLocationsSincePreviousSample": .integer(acceptedLocationsSincePowerSample),
            "directUploadAcknowledgementsSincePreviousSample": .integer(directUploadAcknowledgementsSincePowerSample)
        ]
        if let elapsed {
            context["secondsSincePreviousSample"] = .integer(Int(elapsed.rounded(.towardZero)))
        }
        diagnosticsLog.append(
            level: .info,
            event: "locationPowerSample",
            summary: "Recorded event-driven tracking and battery state.",
            result: mode,
            reason: reason,
            context: context,
            timestamp: now,
            persistence: .immediate
        )
        lastPowerSampleAt = now
        lastPowerSampleMode = mode
        callbacksSincePowerSample = 0
        acceptedLocationsSincePowerSample = 0
        directUploadAcknowledgementsSincePowerSample = 0
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
            context: foregroundRecoveryContext(),
            persistence: .immediate
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
