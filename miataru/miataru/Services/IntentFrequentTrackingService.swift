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
    func startManualFrequentTracking(now: Date) async
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
    private let nowProvider: () -> Date

    init(
        controller: any IntentFrequentTrackingControlling = MiataruIntentFrequentTrackingController(),
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.controller = controller
        self.nowProvider = nowProvider
    }

    func startFrequentTracking() async throws -> IntentFrequentTrackingStartResult {
        let currentState = await controller.state()
        guard currentState.locationTrackingEnabled else {
            throw IntentFrequentTrackingError.locationTrackingDisabled
        }
        guard !currentState.deviceKeyAuthBlocked else {
            throw IntentFrequentTrackingError.deviceKeyBlocked
        }
        guard currentState.authorizationStatus == .authorizedAlways else {
            throw IntentFrequentTrackingError.alwaysAuthorizationRequired
        }

        await controller.startManualFrequentTracking(now: nowProvider())
        await controller.reconcileTrackingState(reason: "start frequent tracking intent")

        let updatedState = await controller.state()
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
        return IntentFrequentTrackingStopResult(wasActive: currentState.manualFrequentTrackingEnabled)
    }

    static func frequentTrackingStatus(
        from state: IntentFrequentTrackingState,
        now: Date
    ) -> IntentFrequentTrackingStatus {
        let remainingSeconds = state.frequentTrackingExpiresAt.map { max(0, $0.timeIntervalSince(now)) }
        let manualActive = state.manualFrequentTrackingEnabled && (remainingSeconds == nil || (remainingSeconds ?? 0) > 0)
        let smartActive = state.smartFrequentTrackingEnabled && state.smartFrequentTrackingRuntimeActive

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
        if state.smartFrequentTrackingEnabled && state.smartFrequentTrackingRuntimeActive {
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
        return nil
    }
}

struct MiataruIntentFrequentTrackingController: IntentFrequentTrackingControlling {
    func state() async -> IntentFrequentTrackingState {
        await MainActor.run {
            let settings = SettingsManager.shared
            let locationManager = LocationManager.shared
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
                locationTrackingActive: locationManager.isTracking
            )
        }
    }

    func startManualFrequentTracking(now: Date) async {
        await MainActor.run {
            let settings = SettingsManager.shared
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
