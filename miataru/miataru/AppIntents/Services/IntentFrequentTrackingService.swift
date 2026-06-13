/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * IntentFrequentTrackingService.swift
 * miataru
 *
 * Created by Codex on 10.06.26.
 */

import CoreLocation
import Foundation
import UIKit

protocol IntentFrequentTrackingControlling {
    func state() async -> IntentFrequentTrackingState
    func startManualFrequentTracking(now: Date, durationMode: FrequentBackgroundLocationUpdateDuration?) async
    func stopManualFrequentTracking() async
    func reconcileTrackingState(reason: String) async
}

struct IntentFrequentTrackingState: Equatable {
    let locationTrackingEnabled: Bool
    let deviceKeyAuthBlocked: Bool
    let authorizationStatus: CLAuthorizationStatus
    let manualFrequentTrackingEnabled: Bool
    let smartFrequentTrackingEnabled: Bool
    let smartFrequentTrackingRuntimeActive: Bool
    let frequentTrackingExpiresAt: Date?
    let durationMode: FrequentBackgroundLocationUpdateDuration
    let applicationState: UIApplication.State
    let locationTrackingActive: Bool
    let lowBatteryFrequentTrackingDisabled: Bool
}

struct IntentFrequentTrackingStartResult: Equatable {
    let wasAlreadyActive: Bool
    let expiresAt: Date?
    let durationMode: FrequentBackgroundLocationUpdateDuration

    var dialogText: String {
        if let expiresAt {
            let format = NSLocalizedString(
                "intent_start_frequent_tracking_dialog_until_format",
                comment: "Dialog shown when starting frequent tracking with an expiration date. Argument: localized expiration date."
            )
            return String(
                format: format,
                locale: Locale.current,
                Self.localizedExpirationString(from: expiresAt)
            )
        }

        return NSLocalizedString(
            "intent_start_frequent_tracking_dialog_unlimited",
            comment: "Dialog shown when starting frequent tracking with unlimited duration"
        )
    }

    private static func localizedExpirationString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct IntentFrequentTrackingStopResult: Equatable {
    let wasActive: Bool

    var dialogText: String {
        if wasActive {
            return NSLocalizedString(
                "intent_stop_frequent_tracking_dialog_stopped",
                comment: "Dialog shown when frequent tracking has been stopped from an App Intent"
            )
        }

        return NSLocalizedString(
            "intent_stop_frequent_tracking_dialog_already_stopped",
            comment: "Dialog shown when frequent tracking was already stopped"
        )
    }
}

enum IntentFrequentTrackingError: LocalizedError, Equatable {
    case locationTrackingDisabled
    case deviceKeyBlocked
    case alwaysAuthorizationRequired

    var errorDescription: String? {
        switch self {
        case .locationTrackingDisabled:
            return NSLocalizedString(
                "intent_frequent_tracking_error_tracking_disabled",
                comment: "Error shown when frequent tracking is started while normal location tracking is disabled"
            )
        case .deviceKeyBlocked:
            return NSLocalizedString(
                "intent_frequent_tracking_error_device_key_blocked",
                comment: "Error shown when frequent tracking is started while DeviceKey authentication blocks tracking"
            )
        case .alwaysAuthorizationRequired:
            return NSLocalizedString(
                "intent_frequent_tracking_error_always_authorization_required",
                comment: "Error shown when frequent background tracking is started without Always location authorization"
            )
        }
    }
}

final class IntentFrequentTrackingService: @unchecked Sendable {
    static let shared = IntentFrequentTrackingService()

    private let controller: any IntentFrequentTrackingControlling
    private let eventRecorder: any MiataruAutomationEventRecording
    private let nowProvider: () -> Date

    init(
        controller: any IntentFrequentTrackingControlling = MiataruIntentFrequentTrackingController(),
        eventRecorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.eventRecorder = eventRecorder
        self.nowProvider = nowProvider
    }

    func startFrequentTracking(duration: IntentFrequentTrackingDuration? = nil) async throws -> IntentFrequentTrackingStartResult {
        let currentState = await controller.state()
        guard currentState.locationTrackingEnabled else {
            throw IntentFrequentTrackingError.locationTrackingDisabled
        }
        guard !currentState.deviceKeyAuthBlocked else {
            await recordDeviceKeyBlockedOperation("startFrequentTracking")
            throw IntentFrequentTrackingError.deviceKeyBlocked
        }
        guard currentState.authorizationStatus == .authorizedAlways else {
            throw IntentFrequentTrackingError.alwaysAuthorizationRequired
        }

        await controller.startManualFrequentTracking(now: nowProvider(), durationMode: duration?.durationMode)
        await controller.reconcileTrackingState(reason: "start frequent tracking intent")

        let updatedState = await controller.state()
        await eventRecorder.record(
            kind: .frequentTrackingStarted,
            privacyLevel: .publicSummary,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: [
                "durationMode": Self.durationPayloadValue(updatedState.durationMode),
                "expiresAt": updatedState.frequentTrackingExpiresAt.map(Self.isoString) ?? "unlimited",
                "wasAlreadyActive": currentState.manualFrequentTrackingEnabled ? "true" : "false"
            ]
        )
        return IntentFrequentTrackingStartResult(
            wasAlreadyActive: currentState.manualFrequentTrackingEnabled,
            expiresAt: updatedState.frequentTrackingExpiresAt,
            durationMode: updatedState.durationMode
        )
    }

    func trackingStatus() async -> IntentTrackingStatus {
        let state = await controller.state()
        let frequentStatus = Self.frequentTrackingStatus(from: state, now: nowProvider())
        return IntentTrackingStatus(
            trackingEnabled: state.locationTrackingEnabled,
            authorizationStatus: state.authorizationStatus,
            deviceKeyAuthBlocked: state.deviceKeyAuthBlocked,
            effectiveMode: Self.trackingMode(from: state, frequentStatus: frequentStatus),
            frequentTracking: frequentStatus
        )
    }

    func frequentTrackingStatus() async -> IntentFrequentTrackingStatus {
        let state = await controller.state()
        return Self.frequentTrackingStatus(from: state, now: nowProvider())
    }

    func stopFrequentTracking() async -> IntentFrequentTrackingStopResult {
        let currentState = await controller.state()
        await controller.stopManualFrequentTracking()
        await controller.reconcileTrackingState(reason: "stop frequent tracking intent")
        if currentState.manualFrequentTrackingEnabled {
            await eventRecorder.record(
                kind: .frequentTrackingStopped,
                privacyLevel: .publicSummary,
                deviceID: nil,
                deviceDisplayName: nil,
                placeID: nil,
                placeName: nil,
                payload: [
                    "durationMode": Self.durationPayloadValue(currentState.durationMode),
                    "expiresAt": currentState.frequentTrackingExpiresAt.map(Self.isoString) ?? "unlimited"
                ]
            )
        }
        return IntentFrequentTrackingStopResult(wasActive: currentState.manualFrequentTrackingEnabled)
    }

    private func recordDeviceKeyBlockedOperation(_ operation: String) async {
        await eventRecorder.record(
            kind: .deviceKeyBlockedOperation,
            privacyLevel: .securitySensitive,
            deviceID: nil,
            deviceDisplayName: nil,
            placeID: nil,
            placeName: nil,
            payload: ["operation": operation]
        )
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func durationPayloadValue(_ duration: FrequentBackgroundLocationUpdateDuration) -> String {
        switch duration {
        case .oneHour:
            return "oneHour"
        case .twoHours:
            return "twoHours"
        case .threeHours:
            return "threeHours"
        case .fourHours:
            return "fourHours"
        case .twelveHours:
            return "twelveHours"
        case .twentyFourHours:
            return "twentyFourHours"
        case .unlimited:
            return "unlimited"
        }
    }

    static func frequentTrackingStatus(
        from state: IntentFrequentTrackingState,
        now: Date
    ) -> IntentFrequentTrackingStatus {
        let remainingSeconds = state.frequentTrackingExpiresAt.map { max(0, $0.timeIntervalSince(now)) }
        let batteryAllowsFrequentTracking = !state.lowBatteryFrequentTrackingDisabled
        let manualActive = batteryAllowsFrequentTracking && state.manualFrequentTrackingEnabled && (remainingSeconds == nil || (remainingSeconds ?? 0) > 0)
        let smartActive = batteryAllowsFrequentTracking && state.smartFrequentTrackingEnabled && state.smartFrequentTrackingRuntimeActive

        return IntentFrequentTrackingStatus(
            manualEnabled: state.manualFrequentTrackingEnabled,
            smartEnabled: state.smartFrequentTrackingEnabled,
            active: manualActive || smartActive,
            expiresAt: state.frequentTrackingExpiresAt,
            remainingSeconds: remainingSeconds,
            durationMode: state.durationMode,
            blockingReason: frequentTrackingBlockingReason(from: state)
        )
    }

    static func trackingMode(
        from state: IntentFrequentTrackingState,
        frequentStatus: IntentFrequentTrackingStatus
    ) -> IntentTrackingMode {
        guard state.locationTrackingEnabled else { return .stopped }
        guard !state.deviceKeyAuthBlocked else { return .blocked }

        switch state.authorizationStatus {
        case .authorizedAlways:
            break
        case .authorizedWhenInUse:
            return state.applicationState == .active ? .foregroundHighAccuracy : .blocked
        default:
            return .blocked
        }

        guard state.locationTrackingActive else { return .stopped }

        if state.applicationState == .active {
            return .foregroundHighAccuracy
        }
        if frequentStatus.manualEnabled && frequentStatus.active {
            return .manualFrequentActive
        }
        if !state.lowBatteryFrequentTrackingDisabled && state.smartFrequentTrackingEnabled && state.smartFrequentTrackingRuntimeActive {
            return .smartFrequentActive
        }
        if state.smartFrequentTrackingEnabled {
            return .smartWaiting
        }
        return .backgroundSignificantChange
    }

    private static func frequentTrackingBlockingReason(
        from state: IntentFrequentTrackingState
    ) -> IntentFrequentTrackingBlockingReason? {
        guard state.locationTrackingEnabled else { return .trackingDisabled }
        guard !state.deviceKeyAuthBlocked else { return .deviceKeyBlocked }
        guard state.authorizationStatus == .authorizedAlways else { return .alwaysAuthorizationRequired }
        guard !state.lowBatteryFrequentTrackingDisabled else { return .lowBatteryDisabled }
        return nil
    }
}

struct MiataruIntentFrequentTrackingController: IntentFrequentTrackingControlling {
    func state() async -> IntentFrequentTrackingState {
        await MainActor.run {
            let settings = SettingsManager.shared
            let locationManager = LocationManager.shared
            let batteryPercent = LocationManager.batteryPercent(from: UIDevice.current.batteryLevel)
            let lowBatteryFrequentTrackingDisabled = LocationManager.shouldDisableFrequentBackgroundUpdatesForBattery(
                frequentUpdatesEnabled: true,
                batteryPercent: batteryPercent,
                thresholdPercent: settings.frequentBackgroundBatteryAutoDisableLevel
            )
            return IntentFrequentTrackingState(
                locationTrackingEnabled: settings.trackAndReportLocation,
                deviceKeyAuthBlocked: settings.deviceKeyAuthBlocked,
                authorizationStatus: locationManager.authorizationStatusForIntent(),
                manualFrequentTrackingEnabled: settings.frequentBackgroundLocationUpdatesEnabled,
                smartFrequentTrackingEnabled: settings.smartFrequentBackgroundLocationUpdatesEnabled,
                smartFrequentTrackingRuntimeActive: locationManager.smartFrequentBackgroundRuntimeActive,
                frequentTrackingExpiresAt: settings.frequentBackgroundLocationUpdatesExpiresAt,
                durationMode: settings.frequentBackgroundLocationUpdateDurationMode,
                applicationState: UIApplication.shared.applicationState,
                locationTrackingActive: locationManager.isTracking,
                lowBatteryFrequentTrackingDisabled: lowBatteryFrequentTrackingDisabled
            )
        }
    }

    func startManualFrequentTracking(now: Date, durationMode: FrequentBackgroundLocationUpdateDuration?) async {
        await MainActor.run {
            let settings = SettingsManager.shared
            if let durationMode {
                settings.frequentBackgroundLocationUpdateDuration = durationMode.rawValue
            }
            if !settings.frequentBackgroundLocationUpdatesEnabled {
                settings.frequentBackgroundLocationUpdatesEnabled = true
            }
            settings.refreshFrequentBackgroundLocationUpdatesExpiration(now: now)
        }
    }

    func stopManualFrequentTracking() async {
        await MainActor.run {
            let settings = SettingsManager.shared
            if settings.frequentBackgroundLocationUpdatesEnabled {
                settings.frequentBackgroundLocationUpdatesEnabled = false
            } else if settings.frequentBackgroundLocationUpdatesExpiresAt != nil {
                settings.frequentBackgroundLocationUpdatesExpiresAt = nil
            }
        }
    }

    func reconcileTrackingState(reason: String) async {
        await MainActor.run {
            _ = LocationManager.shared.reconcileTrackingStateForIntent(reason: reason)
        }
    }
}
