import Testing
import Foundation
@testable import miataru

@Suite("MapHelpers additional tests")
struct MapHelpersAdditionalTests {

    @Test("mapSpeedLabelText returns nil for nil or zero/negative speeds")
    func testMapSpeedLabelNilAndZero() async throws {
        #expect(mapSpeedLabelText(speedMetersPerSecond: nil) == nil)
        #expect(mapSpeedLabelText(speedMetersPerSecond: 0) == nil)
        #expect(mapSpeedLabelText(speedMetersPerSecond: -1) == nil)
    }

    @Test("relativeTimeString respects custom timeConsideredNow threshold")
    func testRelativeTimeCustomThreshold() async throws {
        let reference = Date(timeIntervalSince1970: 1_700_000_000)
        let twoSecondsAgo = reference.addingTimeInterval(-2)
        // With a 1s threshold, 2s ago should not be considered "now"
        let result = relativeTimeString(from: twoSecondsAgo, to: reference, unitsStyle: .short, timeConsideredNow: 1)
        let nowString = NSLocalizedString("relative_time_now", comment: "Indicates now")
        #expect(result != nowString)
        #expect(!result.isEmpty)
    }
}
