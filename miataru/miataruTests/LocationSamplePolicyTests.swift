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
}
