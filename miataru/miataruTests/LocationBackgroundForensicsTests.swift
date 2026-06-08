import CoreLocation
import Testing
import UIKit
@testable import miataru

@Suite("Location background forensics tests")
struct LocationBackgroundForensicsTests {
    @Test("Background forensic gap assessment distinguishes frequent gaps from significant-change idle")
    func backgroundForensicGapAssessmentDistinguishesFrequentGapsFromSignificantChangeIdle() {
        let expectedSince = Date(timeIntervalSince1970: 10_000)
        let now = expectedSince.addingTimeInterval(LocationBackgroundForensics.frequentBackgroundGapThreshold + 30)

        let frequentState = LocationBackgroundForensics.State(
            backgroundTrackingExpectedSince: expectedSince,
            currentExpectedMode: "backgroundFrequent(distanceFilter: 10.0, desiredAccuracy: 10.0)"
        )
        let frequentAssessment = LocationBackgroundForensics.gapAssessment(
            state: frequentState,
            now: now
        )
        #expect(frequentAssessment?.kind == .suspicious)
        #expect(frequentAssessment?.gapSeconds == Int(LocationBackgroundForensics.frequentBackgroundGapThreshold + 30))

        var observedFrequentState = frequentState
        observedFrequentState.lastBackgroundCallbackAt = now.addingTimeInterval(-60)
        #expect(LocationBackgroundForensics.gapAssessment(state: observedFrequentState, now: now) == nil)

        let significantState = LocationBackgroundForensics.State(
            backgroundTrackingExpectedSince: expectedSince,
            currentExpectedMode: "backgroundSignificantChange"
        )
        #expect(LocationBackgroundForensics.gapAssessment(state: significantState, now: now)?.kind == .unobservedIdle)
    }

    @Test("Foreground recovery burst policy only logs inside recovery window with activity")
    func foregroundRecoveryBurstPolicyOnlyLogsInsideRecoveryWindowWithActivity() {
        let openedAt = Date(timeIntervalSince1970: 20_000)
        #expect(LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: openedAt,
            recoveryAlreadyLoggedAt: nil,
            now: openedAt.addingTimeInterval(5),
            acceptedCount: 1,
            uploadCount: 0
        ))
        #expect(!LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: openedAt,
            recoveryAlreadyLoggedAt: nil,
            now: openedAt.addingTimeInterval(5),
            acceptedCount: 0,
            uploadCount: 0
        ))
        #expect(!LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: openedAt,
            recoveryAlreadyLoggedAt: nil,
            now: openedAt.addingTimeInterval(LocationBackgroundForensics.foregroundRecoveryBurstWindow + 1),
            acceptedCount: 1,
            uploadCount: 0
        ))
        #expect(!LocationBackgroundForensics.shouldLogForegroundRecoveryBurst(
            foregroundOpenedAt: openedAt,
            recoveryAlreadyLoggedAt: openedAt.addingTimeInterval(1),
            now: openedAt.addingTimeInterval(5),
            acceptedCount: 1,
            uploadCount: 0
        ))
    }

    @Test("Significant-change rearm policy attempts only for eligible fresh builds")
    func significantChangeRearmPolicyAttemptsOnlyForEligibleFreshBuilds() {
        let now = Date(timeIntervalSince1970: 20_000)
        let allowed = LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: "2.0-100",
            alreadyRearmedBuildIdentifier: nil,
            reason: "fresh app/update launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            now: now
        )
        #expect(allowed.shouldAttempt)
        #expect(allowed.status.result == .attempted)
        #expect(allowed.status.reason == "fresh app/update launch")
        #expect(allowed.status.checks.allSatisfy { $0.passed })

        let repeated = LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: "2.0-100",
            alreadyRearmedBuildIdentifier: "2.0-100",
            reason: "fresh app/update launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            now: now
        )
        #expect(!repeated.shouldAttempt)
        #expect(repeated.status.result == .skipped)
        #expect(repeated.status.reason == "already re-armed for this build")
        #expect(repeated.status.checks.first(where: { $0.name == "buildNotRearmed" })?.passed == false)

        let missingAlways = LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: "2.0-101",
            alreadyRearmedBuildIdentifier: nil,
            reason: "fresh app/update launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedWhenInUse,
            deviceKeyAuthBlocked: false,
            now: now
        )
        #expect(!missingAlways.shouldAttempt)
        #expect(missingAlways.status.reason == "Always authorization missing")
        #expect(missingAlways.status.checks.first(where: { $0.name == "authorizedAlways" })?.passed == false)

        let disabledTracking = LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: "2.0-101",
            alreadyRearmedBuildIdentifier: nil,
            reason: "fresh app/update launch",
            trackAndReportLocation: false,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            now: now
        )
        #expect(!disabledTracking.shouldAttempt)
        #expect(disabledTracking.status.reason == "location tracking disabled")

        let blockedDeviceKey = LocationBackgroundForensics.significantChangeRearmDecision(
            buildIdentifier: "2.0-101",
            alreadyRearmedBuildIdentifier: nil,
            reason: "fresh app/update launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: true,
            now: now
        )
        #expect(!blockedDeviceKey.shouldAttempt)
        #expect(blockedDeviceKey.status.reason == "DeviceKey auth blocked")
    }
}
