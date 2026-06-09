/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationBackgroundForensics.swift
 * miataru
 */

import Foundation
import CoreLocation

enum LocationBackgroundForensics {
    struct State: Codable, Equatable {
        var backgroundTrackingExpectedSince: Date?
        var currentExpectedMode: String?
        var lastModeAssertionAt: Date?
        var lastModeAssertionReason: String?
        var lastServiceAssertionAt: Date?
        var lastBackgroundCallbackAt: Date?
        var lastAcceptedBackgroundLocationAt: Date?
        var lastBackgroundUploadAt: Date?
        var lastForegroundOpenAt: Date?
        var lastRestoreAfterLaunchAt: Date?
        var lastSignificantChangeRearmAt: Date?
        var lastSmartActivationAt: Date?
        var lastSmartDeactivationAt: Date?
        var lastKnownApplicationState: Int?
        var lastKnownSource: String?
        var backgroundServicesAsserted: Bool = false
        var lastBackgroundGapLoggedAt: Date?
        var pendingForegroundRecoveryStartedAt: Date?
        var pendingForegroundRecoveryPreviousMode: String?
        var pendingForegroundRecoveryGapSeconds: Int?
        var pendingForegroundRecoveryLastBackgroundCallbackAt: Date?
        var pendingForegroundRecoveryLastBackgroundUploadAt: Date?
        var pendingForegroundRecoveryBackgroundServicesAsserted: Bool?
        var foregroundBurstCallbackCount: Int = 0
        var foregroundBurstAcceptedCount: Int = 0
        var foregroundBurstUploadCount: Int = 0
        var foregroundRecoveryBurstLoggedAt: Date?

        init(backgroundTrackingExpectedSince: Date? = nil,
             currentExpectedMode: String? = nil,
             lastModeAssertionAt: Date? = nil,
             lastModeAssertionReason: String? = nil,
             lastServiceAssertionAt: Date? = nil,
             lastBackgroundCallbackAt: Date? = nil,
             lastAcceptedBackgroundLocationAt: Date? = nil,
             lastBackgroundUploadAt: Date? = nil,
             lastForegroundOpenAt: Date? = nil,
             lastRestoreAfterLaunchAt: Date? = nil,
             lastSignificantChangeRearmAt: Date? = nil,
             lastSmartActivationAt: Date? = nil,
             lastSmartDeactivationAt: Date? = nil,
             lastKnownApplicationState: Int? = nil,
             lastKnownSource: String? = nil,
             backgroundServicesAsserted: Bool = false,
             lastBackgroundGapLoggedAt: Date? = nil,
             pendingForegroundRecoveryStartedAt: Date? = nil,
             pendingForegroundRecoveryPreviousMode: String? = nil,
             pendingForegroundRecoveryGapSeconds: Int? = nil,
             pendingForegroundRecoveryLastBackgroundCallbackAt: Date? = nil,
             pendingForegroundRecoveryLastBackgroundUploadAt: Date? = nil,
             pendingForegroundRecoveryBackgroundServicesAsserted: Bool? = nil,
             foregroundBurstCallbackCount: Int = 0,
             foregroundBurstAcceptedCount: Int = 0,
             foregroundBurstUploadCount: Int = 0,
             foregroundRecoveryBurstLoggedAt: Date? = nil) {
            self.backgroundTrackingExpectedSince = backgroundTrackingExpectedSince
            self.currentExpectedMode = currentExpectedMode
            self.lastModeAssertionAt = lastModeAssertionAt
            self.lastModeAssertionReason = lastModeAssertionReason
            self.lastServiceAssertionAt = lastServiceAssertionAt
            self.lastBackgroundCallbackAt = lastBackgroundCallbackAt
            self.lastAcceptedBackgroundLocationAt = lastAcceptedBackgroundLocationAt
            self.lastBackgroundUploadAt = lastBackgroundUploadAt
            self.lastForegroundOpenAt = lastForegroundOpenAt
            self.lastRestoreAfterLaunchAt = lastRestoreAfterLaunchAt
            self.lastSignificantChangeRearmAt = lastSignificantChangeRearmAt
            self.lastSmartActivationAt = lastSmartActivationAt
            self.lastSmartDeactivationAt = lastSmartDeactivationAt
            self.lastKnownApplicationState = lastKnownApplicationState
            self.lastKnownSource = lastKnownSource
            self.backgroundServicesAsserted = backgroundServicesAsserted
            self.lastBackgroundGapLoggedAt = lastBackgroundGapLoggedAt
            self.pendingForegroundRecoveryStartedAt = pendingForegroundRecoveryStartedAt
            self.pendingForegroundRecoveryPreviousMode = pendingForegroundRecoveryPreviousMode
            self.pendingForegroundRecoveryGapSeconds = pendingForegroundRecoveryGapSeconds
            self.pendingForegroundRecoveryLastBackgroundCallbackAt = pendingForegroundRecoveryLastBackgroundCallbackAt
            self.pendingForegroundRecoveryLastBackgroundUploadAt = pendingForegroundRecoveryLastBackgroundUploadAt
            self.pendingForegroundRecoveryBackgroundServicesAsserted = pendingForegroundRecoveryBackgroundServicesAsserted
            self.foregroundBurstCallbackCount = foregroundBurstCallbackCount
            self.foregroundBurstAcceptedCount = foregroundBurstAcceptedCount
            self.foregroundBurstUploadCount = foregroundBurstUploadCount
            self.foregroundRecoveryBurstLoggedAt = foregroundRecoveryBurstLoggedAt
        }
    }

    enum GapKind: String, Equatable {
        case suspicious
        case unobservedIdle
    }

    struct GapAssessment: Equatable {
        let kind: GapKind
        let gapSeconds: Int
        let lastObservedAt: Date?
        let referenceAt: Date
        let referenceReason: String
    }

    struct SignificantChangeRearmDecision: Equatable {
        let shouldAttempt: Bool
        let status: LocationSignificantChangeRearmStatus
    }

    static let frequentBackgroundGapThreshold: TimeInterval = 10 * 60
    static let foregroundRecoveryBurstWindow: TimeInterval = 30

    static func significantChangeRearmDecision(buildIdentifier: String,
                                               alreadyRearmedBuildIdentifier: String?,
                                               reason: String,
                                               trackAndReportLocation: Bool,
                                               authorizationStatus: CLAuthorizationStatus,
                                               deviceKeyAuthBlocked: Bool,
                                               now: Date = Date()) -> SignificantChangeRearmDecision {
        let buildNotRearmed = alreadyRearmedBuildIdentifier != buildIdentifier
        let checks = [
            LocationDiagnosticsLogStore.check(
                "trackingEnabled",
                trackAndReportLocation,
                detail: trackAndReportLocation ? "Location tracking is enabled." : "Location tracking is disabled."
            ),
            LocationDiagnosticsLogStore.check(
                "authorizedAlways",
                authorizationStatus == .authorizedAlways,
                detail: "Authorization status: \(authorizationStatus.rawValue)."
            ),
            LocationDiagnosticsLogStore.check(
                "deviceKeyNotBlocked",
                !deviceKeyAuthBlocked,
                detail: deviceKeyAuthBlocked ? "DeviceKey authentication is blocked." : "DeviceKey authentication is not blocked."
            ),
            LocationDiagnosticsLogStore.check(
                "buildNotRearmed",
                buildNotRearmed,
                detail: buildNotRearmed ? "Build has not been re-armed yet." : "Build was already re-armed."
            )
        ]

        let skipReason: String?
        if !trackAndReportLocation {
            skipReason = "location tracking disabled"
        } else if authorizationStatus != .authorizedAlways {
            skipReason = "Always authorization missing"
        } else if deviceKeyAuthBlocked {
            skipReason = "DeviceKey auth blocked"
        } else if !buildNotRearmed {
            skipReason = "already re-armed for this build"
        } else {
            skipReason = nil
        }

        let status = LocationSignificantChangeRearmStatus(
            timestamp: now,
            buildIdentifier: buildIdentifier,
            result: skipReason == nil ? .attempted : .skipped,
            reason: skipReason ?? reason,
            checks: checks
        )
        return SignificantChangeRearmDecision(
            shouldAttempt: skipReason == nil,
            status: status
        )
    }

    static func gapAssessment(state: State,
                              now: Date,
                              frequentThreshold: TimeInterval = frequentBackgroundGapThreshold) -> GapAssessment? {
        guard let expectedSince = state.backgroundTrackingExpectedSince,
              let expectedMode = state.currentExpectedMode else {
            return nil
        }

        let lastObservedAt = [state.lastBackgroundCallbackAt, state.lastBackgroundUploadAt]
            .compactMap { $0 }
            .max()
        let referenceDate: Date
        let referenceReason: String
        if let lastObservedAt,
           lastObservedAt > expectedSince {
            referenceDate = lastObservedAt
            referenceReason = "lastObservedBackgroundActivityAt"
        } else {
            referenceDate = expectedSince
            referenceReason = "backgroundTrackingExpectedSince"
        }
        let gapSeconds = Int(now.timeIntervalSince(referenceDate).rounded(.down))
        guard gapSeconds >= Int(frequentThreshold) else {
            return nil
        }

        if expectedMode.localizedCaseInsensitiveContains("frequent") {
            return GapAssessment(
                kind: .suspicious,
                gapSeconds: gapSeconds,
                lastObservedAt: lastObservedAt,
                referenceAt: referenceDate,
                referenceReason: referenceReason
            )
        }

        return GapAssessment(
            kind: .unobservedIdle,
            gapSeconds: gapSeconds,
            lastObservedAt: lastObservedAt,
            referenceAt: referenceDate,
            referenceReason: referenceReason
        )
    }

    static func shouldLogForegroundRecoveryBurst(foregroundOpenedAt: Date?,
                                                 recoveryAlreadyLoggedAt: Date?,
                                                 now: Date,
                                                 acceptedCount: Int,
                                                 uploadCount: Int,
                                                 window: TimeInterval = foregroundRecoveryBurstWindow) -> Bool {
        guard recoveryAlreadyLoggedAt == nil,
              let foregroundOpenedAt,
              now.timeIntervalSince(foregroundOpenedAt) >= 0,
              now.timeIntervalSince(foregroundOpenedAt) <= window else {
            return false
        }
        return acceptedCount > 0 || uploadCount > 0
    }
}
