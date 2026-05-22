import Testing
import Foundation
import CoreGraphics
import MapKit
@testable import miataru

@Suite("MapHelpers logic tests")
struct MapHelpersTests {

    @Test("relativeTimeString returns localized 'now' within threshold")
    func testRelativeTimeStringNow() async throws {
        // Fixed reference time
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let justNow = now.addingTimeInterval(-2) // within default timeConsideredNow = 10s
        let result = relativeTimeString(from: justNow, to: now)
        // Should equal the localized string for the explicit key used in MapHelpers
        let expectedNow = NSLocalizedString("relative_time_now", comment: "Indicates that the location update just happened or is happening right now in a relative time on the map marker.")
        #expect(result == expectedNow)
    }

    @Test("relativeTimeString returns a non-empty string for past times")
    func testRelativeTimeStringPast() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoMinutesAgo = now.addingTimeInterval(-120)
        let result = relativeTimeString(from: twoMinutesAgo, to: now)
        // We can't assert exact wording due to localization; just ensure it's a non-placeholder, non-empty string
        #expect(!result.isEmpty)
        #expect(result != "–")
    }

    @Test("mapSpeedLabelText returns nil for values below default threshold")
    func testMapSpeedLabelBelowThreshold() async throws {
        // 2 m/s ≈ 7.2 km/h, below default minSpeedKmh = 10
        let label = mapSpeedLabelText(speedMetersPerSecond: 2.0)
        #expect(label == nil)
    }

    @Test("mapSpeedLabelText returns formatted value above threshold")
    func testMapSpeedLabelAboveThreshold() async throws {
        // 5 m/s ≈ 18 km/h, above default minSpeedKmh
        let label = mapSpeedLabelText(speedMetersPerSecond: 5.0)
        #expect(label != nil)
        if let label {
            // Locale dependent; assert common unit suffix presence
            let hasUnit = label.contains("km/h") || label.contains("mph")
            #expect(hasUnit)
        }
    }

    @Test("mapLiveSpeedLabelText returns formatted value for fresh locations")
    func testMapLiveSpeedLabelFreshLocation() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = now.addingTimeInterval(-60)
        let label = mapLiveSpeedLabelText(
            speedMetersPerSecond: 5.0,
            locationTimestamp: timestamp,
            now: now
        )

        #expect(label != nil)
        if let label {
            let hasUnit = label.contains("km/h") || label.contains("mph")
            #expect(hasUnit)
        }
    }

    @Test("mapLiveSpeedLabelText still shows speed exactly at five minutes")
    func testMapLiveSpeedLabelFiveMinuteBoundary() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = now.addingTimeInterval(-300)
        let label = mapLiveSpeedLabelText(
            speedMetersPerSecond: 5.0,
            locationTimestamp: timestamp,
            now: now
        )

        #expect(label != nil)
    }

    @Test("mapLiveSpeedLabelText hides speed older than five minutes")
    func testMapLiveSpeedLabelStaleLocation() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = now.addingTimeInterval(-301)
        let label = mapLiveSpeedLabelText(
            speedMetersPerSecond: 5.0,
            locationTimestamp: timestamp,
            now: now
        )

        #expect(label == nil)
    }

    @Test("mapLiveSpeedLabelText treats future timestamps as fresh")
    func testMapLiveSpeedLabelFutureTimestamp() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = now.addingTimeInterval(30)
        let label = mapLiveSpeedLabelText(
            speedMetersPerSecond: 5.0,
            locationTimestamp: timestamp,
            now: now
        )

        #expect(label != nil)
    }

    @Test("history speed formatting stays independent from live freshness")
    func testHistorySpeedFormattingIgnoresLiveFreshness() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let staleTimestamp = now.addingTimeInterval(-301)
        let liveLabel = mapLiveSpeedLabelText(
            speedMetersPerSecond: 0.5,
            locationTimestamp: staleTimestamp,
            now: now,
            minSpeedKmh: 0
        )
        let historyLabel = mapSpeedLabelText(speedMetersPerSecond: 0.5, minSpeedKmh: 0)

        #expect(liveLabel == nil)
        #expect(historyLabel != nil)
    }

    @Test("timezoneOffsetString returns nil for same timezone")
    func testTimezoneOffsetSame() async throws {
        let result = timezoneOffsetString(deviceTimeZone: TimeZone.current)
        #expect(result == nil)
    }

    @Test("timezoneOffsetString returns +2 for TZ two hours ahead")
    func testTimezoneOffsetPositive() async throws {
        // Create a timezone two hours ahead of the current
        let now = Date()
        let currentOffset = TimeZone.current.secondsFromGMT(for: now)
        let twoHours = 2 * 3600
        guard let tz = TimeZone(secondsFromGMT: currentOffset + twoHours) else {
            Issue.record("Failed to construct test timezone")
            return
        }
        let result = timezoneOffsetString(deviceTimeZone: tz)
        #expect(result == "+2")
    }
    
    @Test("spanForZoomLevel produces reasonable deltas and round-trips with currentZoomLevelFromSpan")
    func testZoomSpanRoundTrip() async throws {
        // Test a few representative zoom levels
        for level in [1, 5, 25, 100] {
            let span = spanForZoomLevel(level)
            // Expect positive, finite deltas
            #expect(span.latitudeDelta > 0 && span.longitudeDelta > 0)
            #expect(span.latitudeDelta.isFinite && span.longitudeDelta.isFinite)
            // Round-trip back to a zoom level (approximate)
            let roundTrip = currentZoomLevelFromSpan(span)
            // Allow small rounding differences
            #expect(abs(roundTrip - level) <= 1)
        }
    }

    @Test("map selection proximity follows screen distance at lower zoom")
    func testMapSelectionProximityUsesScreenDistance() async throws {
        let first = CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0)
        let visuallyCloseButMoreThan35mAway = CLLocationCoordinate2D(latitude: 52.0, longitude: 13.002)
        let region = MKCoordinateRegion(
            center: first,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )

        let isNear = areCoordinatesNearForMapSelection(
            first,
            visuallyCloseButMoreThan35mAway,
            in: region,
            screenSize: CGSize(width: 400, height: 800)
        )

        #expect(isNear)
    }

    @Test("map selection proximity still rejects visually distant devices")
    func testMapSelectionProximityRejectsDistantScreenPoints() async throws {
        let first = CLLocationCoordinate2D(latitude: 52.0, longitude: 13.0)
        let distant = CLLocationCoordinate2D(latitude: 52.0, longitude: 13.02)
        let region = MKCoordinateRegion(
            center: first,
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )

        let isNear = areCoordinatesNearForMapSelection(
            first,
            distant,
            in: region,
            screenSize: CGSize(width: 400, height: 800)
        )

        #expect(!isNear)
    }

    @Test("relativeTimeString with future date returns 'now'")
    func testRelativeTimeFutureIsNow() async throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let future = reference.addingTimeInterval(30)
        let result = relativeTimeString(from: future, to: reference)
        let expectedNow = NSLocalizedString("relative_time_now", comment: "Indicates now")
        #expect(result == expectedNow)
    }

    @Test("timezoneOffsetString returns negative offset for behind timezones")
    func testTimezoneOffsetNegative() async throws {
        let now = Date()
        let currentOffset = TimeZone.current.secondsFromGMT(for: now)
        let threeHours = 3 * 3600
        guard let tz = TimeZone(secondsFromGMT: currentOffset - threeHours) else {
            Issue.record("Failed to construct test timezone")
            return
        }
        let result = timezoneOffsetString(deviceTimeZone: tz)
        #expect(result == "-3")
    }

    @Test("mapSpeedLabelText returns non-nil when min threshold is 0 and positive speed")
    func testMapSpeedLabelWithZeroThreshold() async throws {
        let label = mapSpeedLabelText(speedMetersPerSecond: 0.5, minSpeedKmh: 0)
        #expect(label != nil)
        if let label {
            let hasUnit = label.contains("km/h") || label.contains("mph")
            #expect(hasUnit)
        }
    }
}
