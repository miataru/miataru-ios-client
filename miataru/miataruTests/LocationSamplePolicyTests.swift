import CoreLocation
import Testing
import UIKit
@testable import miataru

@Suite("Location sample policy tests")
struct LocationSamplePolicyTests {
    @Test("Frequent background callbacks bypass sensitivity while frequent runtime is effective")
    func frequentBackgroundCallbacksBypassSensitivityWhileFrequentRuntimeIsEffective() {
        #expect(LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            manualFrequentEnabled: true,
            smartRuntimePhase: .waiting
        ))
        #expect(LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            manualFrequentEnabled: false,
            smartRuntimePhase: .probing
        ))
        #expect(LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            manualFrequentEnabled: false,
            smartRuntimePhase: .confirmedActive
        ))
        #expect(!LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .background,
            updateSourceIsFrequentBackground: true,
            manualFrequentEnabled: false,
            smartRuntimePhase: .waiting
        ))
        #expect(!LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .active,
            updateSourceIsFrequentBackground: true,
            manualFrequentEnabled: true,
            smartRuntimePhase: .confirmedActive
        ))
        #expect(!LocationSamplePolicy.shouldBypassLocationSensitivityForFrequentBackgroundUpload(
            applicationState: .background,
            updateSourceIsFrequentBackground: false,
            manualFrequentEnabled: true,
            smartRuntimePhase: .confirmedActive
        ))
    }

    @Test("Duplicate location callbacks are suppressed before upload")
    func duplicateLocationCallbacksAreSuppressedBeforeUpload() throws {
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp
        )
        let sameCallback = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 12,
            horizontalAccuracy: 3,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp
        )
        let laterCallback = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 10,
            horizontalAccuracy: 5,
            verticalAccuracy: 4,
            course: 90,
            speed: 2,
            timestamp: timestamp.addingTimeInterval(1)
        )

        let key = try #require(LocationSamplePolicy.submissionDeduplicationKey(for: location))
        #expect(LocationSamplePolicy.shouldSubmitLocationForUpload(location, lastSubmittedKey: nil))
        #expect(!LocationSamplePolicy.shouldSubmitLocationForUpload(sameCallback, lastSubmittedKey: key))
        #expect(LocationSamplePolicy.shouldSubmitLocationForUpload(laterCallback, lastSubmittedKey: key))
    }

    @Test("Location update batches are processed chronologically and skip invalid coordinates")
    func locationUpdateBatchesAreProcessedChronologically() {
        let first = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.551086, longitude: 9.993682),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let second = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.552086, longitude: 9.993682),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 200)
        )
        let third = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 53.553086, longitude: 9.993682),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 300)
        )
        let invalid = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: .nan, longitude: 9.993682),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 150)
        )

        let ordered = LocationSamplePolicy.processableLocationUpdates(from: [third, invalid, first, second])
        #expect(ordered.map { Int($0.timestamp.timeIntervalSince1970) } == [100, 200, 300])
    }

    @Test("Location samples reject stale future and out-of-order timestamps")
    func locationSamplesRejectStaleFutureAndOutOfOrderTimestamps() {
        let now = Date(timeIntervalSince1970: 20_000)
        func location(timestamp: Date) -> CLLocation {
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 49.8190, longitude: 10.8077),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: -1,
                speed: -1,
                timestamp: timestamp
            )
        }

        let latest = location(timestamp: now.addingTimeInterval(-60))
        #expect(LocationSamplePolicy.processingDecision(
            for: location(timestamp: now.addingTimeInterval(-5 * 60)),
            now: now,
            latestRawLocation: nil,
            currentLocation: nil,
            smartReferenceLocation: nil
        ) == .process)
        #expect(LocationSamplePolicy.processingDecision(
            for: location(timestamp: now.addingTimeInterval(-LocationSamplePolicy.maximumAge - 1)),
            now: now,
            latestRawLocation: nil,
            currentLocation: nil,
            smartReferenceLocation: nil
        ) == .stale)
        #expect(LocationSamplePolicy.processingDecision(
            for: location(timestamp: now.addingTimeInterval(LocationSamplePolicy.maximumFutureSkew + 1)),
            now: now,
            latestRawLocation: nil,
            currentLocation: nil,
            smartReferenceLocation: nil
        ) == .futureDated)
        #expect(LocationSamplePolicy.processingDecision(
            for: location(timestamp: now.addingTimeInterval(-120)),
            now: now,
            latestRawLocation: latest,
            currentLocation: nil,
            smartReferenceLocation: nil
        ) == .outOfOrder)
        #expect(LocationSamplePolicy.processingDecision(
            for: location(timestamp: now.addingTimeInterval(-30)),
            now: now,
            latestRawLocation: latest,
            currentLocation: nil,
            smartReferenceLocation: nil
        ) == .process)
    }

    @Test("Plausible accepted-location movement passes upload cache filtering")
    func plausibleAcceptedLocationMovementPassesUploadCacheFiltering() {
        let previous = sampleLocation(
            latitude: 49.8190,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 1_000)
        )
        let current = sampleLocation(
            latitude: 49.8191,
            longitude: 10.8079,
            timestamp: Date(timeIntervalSince1970: 1_030)
        )

        guard case .accept(let metrics) = LocationSamplePolicy.acceptanceDecision(
            for: current,
            previousAcceptedLocation: previous
        ) else {
            Issue.record("Expected plausible movement to be accepted.")
            return
        }
        #expect(metrics.distanceMeters ?? 0 > 0)
        #expect((metrics.derivedSpeedKmh ?? 0) < LocationSamplePolicy.maximumImplausibleDerivedSpeedKmh)
    }

    @Test("Short untrusted speed spike is rejected before upload cache filtering")
    func shortUntrustedSpeedSpikeIsRejectedBeforeUploadCacheFiltering() {
        let previous = sampleLocation(
            latitude: 49.8190,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 2_000)
        )
        let current = sampleLocation(
            latitude: 49.81955,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 2_001)
        )

        guard case .reject(let reason, let metrics) = LocationSamplePolicy.acceptanceDecision(
            for: current,
            previousAcceptedLocation: previous
        ) else {
            Issue.record("Expected short speed spike to be rejected.")
            return
        }
        #expect(reason == .implausibleSpeed)
        #expect(metrics.derivedSpeedKmh ?? 0 > LocationSamplePolicy.maximumImplausibleDerivedSpeedKmh)
    }

    @Test("Poor horizontal accuracy is rejected before upload cache filtering")
    func poorHorizontalAccuracyIsRejectedBeforeUploadCacheFiltering() {
        let previous = sampleLocation(
            latitude: 49.8190,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 3_000)
        )
        let current = sampleLocation(
            latitude: 49.8191,
            longitude: 10.8078,
            horizontalAccuracy: LocationSamplePolicy.maximumAcceptedHorizontalAccuracy + 1,
            timestamp: Date(timeIntervalSince1970: 3_010)
        )

        guard case .reject(let reason, let metrics) = LocationSamplePolicy.acceptanceDecision(
            for: current,
            previousAcceptedLocation: previous
        ) else {
            Issue.record("Expected coarse accuracy to be rejected.")
            return
        }
        #expect(reason == .accuracyTooPoor)
        #expect(metrics.horizontalAccuracy == LocationSamplePolicy.maximumAcceptedHorizontalAccuracy + 1)
    }

    @Test("Large jump after a long callback gap waits for confirmation")
    func largeJumpAfterLongCallbackGapWaitsForConfirmation() {
        let previous = sampleLocation(
            latitude: 49.8190,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 4_000)
        )
        let current = sampleLocation(
            latitude: 49.8290,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 4_300)
        )

        guard case .deferForConfirmation(let metrics) = LocationSamplePolicy.acceptanceDecision(
            for: current,
            previousAcceptedLocation: previous
        ) else {
            Issue.record("Expected large jump to wait for confirmation.")
            return
        }
        #expect(metrics.distanceMeters ?? 0 >= LocationSamplePolicy.largeJumpDistance)
        #expect(metrics.elapsedSeconds == 300)
    }

    @Test("Second point near a deferred large jump confirms the candidate")
    func secondPointNearDeferredLargeJumpConfirmsTheCandidate() {
        let pending = sampleLocation(
            latitude: 49.8290,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 5_000)
        )
        let confirmation = sampleLocation(
            latitude: 49.8294,
            longitude: 10.8078,
            timestamp: Date(timeIntervalSince1970: 5_030)
        )

        #expect(LocationSamplePolicy.confirmsLargeJump(
            candidate: confirmation,
            pendingCandidate: pending
        ))
    }

    @Test("Return near the previous accepted point discards a deferred large jump")
    func returnNearPreviousAcceptedPointDiscardsDeferredLargeJump() {
        let previous = sampleLocation(
            latitude: 49.8190,
            longitude: 10.8077,
            timestamp: Date(timeIntervalSince1970: 6_000)
        )
        let returned = sampleLocation(
            latitude: 49.8193,
            longitude: 10.8078,
            timestamp: Date(timeIntervalSince1970: 6_030)
        )

        #expect(LocationSamplePolicy.returnsToPreviousAcceptedLocation(
            candidate: returned,
            previousAcceptedLocation: previous
        ))
    }

    private func sampleLocation(latitude: Double,
                                longitude: Double,
                                horizontalAccuracy: CLLocationAccuracy = 5,
                                timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: timestamp
        )
    }
}
