import CoreLocation
import Foundation
import Testing
import UIKit
@testable import miataru

@Suite("Location background forensics tests")
struct LocationBackgroundForensicsTests {
    private func makeRecorderFixture() throws -> (LocationBackgroundForensicsRecorder, LocationDiagnosticsLogStore, UserDefaults, String, URL) {
        let suiteName = "LocationBackgroundForensicsRecorderTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("location-forensics-recorder-\(UUID().uuidString).json")
        let diagnosticsLog = LocationDiagnosticsLogStore(userDefaults: defaults, fileURL: fileURL, maxEntries: 50)
        let recorder = LocationBackgroundForensicsRecorder(userDefaults: defaults, diagnosticsLog: diagnosticsLog)
        return (recorder, diagnosticsLog, defaults, suiteName, fileURL)
    }

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

    @Test("Recorder persists rearm status and build marker")
    func recorderPersistsRearmStatusAndBuildMarker() throws {
        let (recorder, diagnosticsLog, defaults, suiteName, fileURL) = try makeRecorderFixture()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let now = Date(timeIntervalSince1970: 30_000)
        let decision = recorder.significantChangeRearmDecision(
            buildIdentifier: "3.0-1",
            reason: "fresh launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            now: now
        )
        #expect(decision.shouldAttempt)

        recorder.recordSignificantChangeRearmStatus(decision.status)
        recorder.markSignificantChangeRearmed(buildIdentifier: "3.0-1")

        let reloadedRecorder = LocationBackgroundForensicsRecorder(userDefaults: defaults, diagnosticsLog: diagnosticsLog)
        #expect(reloadedRecorder.lastSignificantChangeRearmStatus == decision.status)
        #expect(reloadedRecorder.state.lastSignificantChangeRearmAt == now)

        let repeatedDecision = reloadedRecorder.significantChangeRearmDecision(
            buildIdentifier: "3.0-1",
            reason: "fresh launch",
            trackAndReportLocation: true,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false,
            now: now.addingTimeInterval(1)
        )
        #expect(!repeatedDecision.shouldAttempt)
        #expect(repeatedDecision.status.reason == "already re-armed for this build")
    }

    @Test("Recorder logs foreground recovery burst after background gap")
    func recorderLogsForegroundRecoveryBurstAfterBackgroundGap() throws {
        let (recorder, diagnosticsLog, defaults, suiteName, fileURL) = try makeRecorderFixture()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let startedAt = Date(timeIntervalSince1970: 40_000)
        let openedAt = startedAt.addingTimeInterval(LocationBackgroundForensics.frequentBackgroundGapThreshold + 1)
        let frequentMode = LocationTrackingPolicy.TrackingMode.backgroundFrequent(
            distanceFilter: 10,
            desiredAccuracy: kCLLocationAccuracyNearestTenMeters
        )

        recorder.recordModeResolution(
            mode: frequentMode,
            applicationState: .background,
            reason: "background tracking",
            now: startedAt
        )
        recorder.recordServiceAssertion(mode: frequentMode, now: startedAt)
        recorder.recordForegroundOpen(trigger: "app did enter foreground", now: openedAt)
        recorder.recordLocationCallback(
            applicationState: .active,
            sourceRawValue: "primary",
            isPrimarySource: true,
            timestamp: openedAt.addingTimeInterval(1)
        )
        recorder.recordAcceptedLocation(
            applicationState: .active,
            isPrimarySource: true,
            timestamp: openedAt.addingTimeInterval(2)
        )

        #expect(recorder.state.pendingForegroundRecoveryStartedAt == openedAt)
        #expect(recorder.state.foregroundBurstCallbackCount == 1)
        #expect(recorder.state.foregroundBurstAcceptedCount == 1)
        #expect(recorder.state.foregroundRecoveryBurstLoggedAt == openedAt.addingTimeInterval(2))
        #expect(diagnosticsLog.entries.contains { $0.event == "backgroundTrackingGap" })
        #expect(diagnosticsLog.entries.contains { $0.event == "foregroundRecoveryBurst" })
    }
}
