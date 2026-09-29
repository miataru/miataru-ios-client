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
        #expect(frequentAssessment?.referenceAt == expectedSince)
        #expect(frequentAssessment?.referenceReason == "backgroundTrackingExpectedSince")

        var observedFrequentState = frequentState
        observedFrequentState.lastBackgroundCallbackAt = now.addingTimeInterval(-60)
        #expect(LocationBackgroundForensics.gapAssessment(state: observedFrequentState, now: now) == nil)

        var oldObservedState = frequentState
        oldObservedState.lastBackgroundUploadAt = expectedSince.addingTimeInterval(-120)
        let oldObservedAssessment = LocationBackgroundForensics.gapAssessment(
            state: oldObservedState,
            now: now
        )
        #expect(oldObservedAssessment?.gapSeconds == Int(LocationBackgroundForensics.frequentBackgroundGapThreshold + 30))
        #expect(oldObservedAssessment?.referenceAt == expectedSince)
        #expect(oldObservedAssessment?.referenceReason == "backgroundTrackingExpectedSince")

        var staleButRecentExpectedState = frequentState
        staleButRecentExpectedState.lastBackgroundCallbackAt = expectedSince.addingTimeInterval(30)
        let staleButRecentExpectedAssessment = LocationBackgroundForensics.gapAssessment(
            state: staleButRecentExpectedState,
            now: now.addingTimeInterval(30)
        )
        #expect(staleButRecentExpectedAssessment?.gapSeconds == Int(LocationBackgroundForensics.frequentBackgroundGapThreshold + 30))
        #expect(staleButRecentExpectedAssessment?.referenceAt == staleButRecentExpectedState.lastBackgroundCallbackAt)
        #expect(staleButRecentExpectedAssessment?.referenceReason == "lastObservedBackgroundActivityAt")

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

    @Test("Power diagnostics sample existing tracking events and survive log reload")
    func powerDiagnosticsSamplesExistingEventsWithoutExtraWakeups() throws {
        let suiteName = "LocationPowerDiagnosticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("location-power-diagnostics-\(UUID().uuidString).json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        var batteryMonitoringEnabled = false
        var batteryMonitoringChanges: [Bool] = []
        let batteryMonitoringControl = LocationDiagnosticsBatteryMonitoringControl(
            isEnabled: { batteryMonitoringEnabled },
            setEnabled: {
                batteryMonitoringEnabled = $0
                batteryMonitoringChanges.append($0)
            }
        )
        let diagnosticsLog = LocationDiagnosticsLogStore(
            userDefaults: defaults,
            fileURL: fileURL,
            batteryMonitoringControl: batteryMonitoringControl
        )
        #expect(batteryMonitoringEnabled)
        #expect(batteryMonitoringChanges == [true])
        var reading = LocationDiagnosticsPowerReading(batteryMonitoringEnabled: true, batteryLevel: 0.80, batteryState: .unplugged, lowPowerModeEnabled: false)
        var readingCount = 0
        let recorder = LocationBackgroundForensicsRecorder(
            userDefaults: defaults,
            diagnosticsLog: diagnosticsLog,
            powerReading: {
                readingCount += 1
                return reading
            }
        )
        let startedAt = Date(timeIntervalSince1970: 50_000)
        recorder.recordModeResolution(mode: .backgroundSignificantChange,
                                      applicationState: .background,
                                      reason: "background transition",
                                      now: startedAt)
        recorder.recordLocationCallback(applicationState: .background,
                                        sourceRawValue: "primary",
                                        isPrimarySource: true,
                                        timestamp: startedAt.addingTimeInterval(60))
        recorder.recordAcceptedLocation(applicationState: .background,
                                        isPrimarySource: true,
                                        timestamp: startedAt.addingTimeInterval(61))
        recorder.recordUpload(applicationState: .background, timestamp: startedAt.addingTimeInterval(62))
        #expect(diagnosticsLog.entries.filter { $0.event == "locationPowerSample" }.count == 1)
        #expect(readingCount == 1)

        reading = LocationDiagnosticsPowerReading(batteryMonitoringEnabled: true, batteryLevel: 0.79, batteryState: .unplugged, lowPowerModeEnabled: true)
        recorder.recordLocationCallback(applicationState: .background,
                                        sourceRawValue: "primary",
                                        isPrimarySource: true,
                                        timestamp: startedAt.addingTimeInterval(1_800))
        let intervalSample = try #require(diagnosticsLog.entries.last { $0.event == "locationPowerSample" })
        #expect(intervalSample.reason == "locationCallback")
        #expect(intervalSample.context["batteryPercent"] == .integer(79))
        #expect(intervalSample.context["batteryMonitoringEnabled"] == .bool(true))
        #expect(intervalSample.context["batteryState"] == .string("unplugged"))
        #expect(intervalSample.context["lowPowerModeEnabled"] == .bool(true))
        #expect(intervalSample.context["secondsSincePreviousSample"] == .integer(1_800))
        #expect(intervalSample.context["callbacksSincePreviousSample"] == .integer(2))
        #expect(intervalSample.context["acceptedLocationsSincePreviousSample"] == .integer(1))
        #expect(intervalSample.context["directUploadAcknowledgementsSincePreviousSample"] == .integer(1))
        #expect(!intervalSample.context.keys.contains { $0.localizedCaseInsensitiveContains("latitude") || $0.localizedCaseInsensitiveContains("longitude") })

        recorder.recordForegroundOpen(trigger: "foreground", now: startedAt.addingTimeInterval(1_810))
        recorder.recordModeResolution(mode: .foregroundHighAccuracy,
                                      applicationState: .active,
                                      reason: "foreground transition",
                                      now: startedAt.addingTimeInterval(1_811))
        let powerSamples = diagnosticsLog.entries.filter { $0.event == "locationPowerSample" }
        #expect(powerSamples.count == 4)
        #expect(powerSamples[2].reason == "foregroundOpen")
        #expect(powerSamples[3].context["expectedMode"] == .string("foregroundHighAccuracy"))

        reading = LocationDiagnosticsPowerReading(batteryMonitoringEnabled: true, batteryLevel: 0.78, batteryState: .charging, lowPowerModeEnabled: false)
        recorder.recordLocationCallback(applicationState: .active,
                                        sourceRawValue: "primary",
                                        isPrimarySource: true,
                                        timestamp: startedAt.addingTimeInterval(3_611))
        let chargingSample = try #require(diagnosticsLog.entries.last { $0.event == "locationPowerSample" })
        #expect(chargingSample.context["batteryState"] == .string("charging"))
        #expect(chargingSample.context["batteryPercent"] == .integer(78))

        let reloadedLog = LocationDiagnosticsLogStore(userDefaults: defaults, fileURL: fileURL)
        #expect(reloadedLog.entries.filter { $0.event == "locationPowerSample" }.count == 5)
        let relaunchedRecorder = LocationBackgroundForensicsRecorder(
            userDefaults: defaults,
            diagnosticsLog: reloadedLog,
            powerReading: {
                LocationDiagnosticsPowerReading(batteryMonitoringEnabled: true, batteryLevel: 0.77, batteryState: .unplugged, lowPowerModeEnabled: false)
            }
        )
        relaunchedRecorder.recordRestoreAfterLaunch(trigger: "background location launch",
                                                   now: startedAt.addingTimeInterval(7_200))
        let relaunchSample = try #require(reloadedLog.entries.last { $0.event == "locationPowerSample" })
        #expect(relaunchSample.reason == "restoreAfterLaunch")
        #expect(relaunchSample.context["batteryPercent"] == .integer(77))
        #expect(relaunchSample.context["secondsSincePreviousSample"] == nil)
        diagnosticsLog.setEnabled(false)
        #expect(batteryMonitoringEnabled)
        #expect(batteryMonitoringChanges == [true])
        recorder.recordModeResolution(mode: .stopped,
                                      applicationState: .active,
                                      reason: "tracking stopped",
                                      now: startedAt.addingTimeInterval(1_812))
        #expect(readingCount == 5)
        let export = diagnosticsLog.makeExport(appVersion: "3.6", build: "9")
        #expect(export.loggingEnabledAtExport == false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var previousExport = try #require(JSONSerialization.jsonObject(with: encoder.encode(export)) as? [String: Any])
        previousExport.removeValue(forKey: "loggingEnabledAtExport")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedPreviousExport = try decoder.decode(
            LocationDiagnosticsExport.self,
            from: JSONSerialization.data(withJSONObject: previousExport)
        )
        #expect(decodedPreviousExport.loggingEnabledAtExport == nil)

        batteryMonitoringEnabled = false
        defaults.set(true, forKey: SettingsKeys.locationDiagnosticsLoggingEnabled)
        let relaunchedLogWithMonitoring = LocationDiagnosticsLogStore(
            userDefaults: defaults,
            fileURL: fileURL,
            batteryMonitoringControl: batteryMonitoringControl
        )
        #expect(batteryMonitoringEnabled)
        #expect(batteryMonitoringChanges == [true, true])
        relaunchedLogWithMonitoring.setEnabled(false)
        #expect(batteryMonitoringEnabled)
        #expect(batteryMonitoringChanges == [true, true])
    }

    @Test("Enabling diagnostics starts battery monitoring and records an immediate baseline")
    func enablingDiagnosticsRecordsPowerBaseline() throws {
        let suiteName = "LocationDiagnosticsActivationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("location-diagnostics-activation-\(UUID().uuidString).json")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: fileURL)
        }

        let notificationCenter = NotificationCenter()
        var batteryMonitoringEnabled = false
        let log = LocationDiagnosticsLogStore(
            userDefaults: defaults,
            fileURL: fileURL,
            notificationCenter: notificationCenter,
            batteryMonitoringControl: LocationDiagnosticsBatteryMonitoringControl(
                isEnabled: { batteryMonitoringEnabled },
                setEnabled: { batteryMonitoringEnabled = $0 }
            )
        )
        let recorder = LocationBackgroundForensicsRecorder(
            userDefaults: defaults,
            diagnosticsLog: log,
            powerReading: {
                LocationDiagnosticsPowerReading(
                    batteryMonitoringEnabled: batteryMonitoringEnabled,
                    batteryLevel: 0.65,
                    batteryState: .unplugged,
                    lowPowerModeEnabled: false
                )
            }
        )
        let enabledAt = Date(timeIntervalSince1970: 90_000)
        let observer = notificationCenter.addObserver(
            forName: .locationDiagnosticsDidEnable,
            object: log,
            queue: nil
        ) { _ in
            recorder.recordDiagnosticsEnabled(applicationState: .active, now: enabledAt)
        }
        defer { notificationCenter.removeObserver(observer) }

        log.setEnabled(true)
        #expect(batteryMonitoringEnabled)
        let baseline = try #require(log.entries.last)
        #expect(baseline.event == "locationPowerSample")
        #expect(baseline.reason == "diagnosticsEnabled")
        #expect(baseline.context["batteryPercent"] == .integer(65))
        #expect(baseline.context["batteryMonitoringEnabled"] == .bool(true))
        #expect(baseline.context["callbacksSincePreviousSample"] == .integer(0))

        log.setEnabled(true)
        #expect(log.entries.count == 1)
        log.setEnabled(false)
        log.setEnabled(true)
        #expect(log.entries.count == 2)
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
        let gapEntry = try #require(diagnosticsLog.entries.first { $0.event == "backgroundTrackingGap" })
        #expect(gapEntry.context["gapReferenceReason"] == .string("backgroundTrackingExpectedSince"))
        #expect(gapEntry.context["gapReferenceAt"] == .string(ISO8601DateFormatter().string(from: startedAt)))
        #expect(diagnosticsLog.entries.contains { $0.event == "foregroundRecoveryBurst" })
    }
}
