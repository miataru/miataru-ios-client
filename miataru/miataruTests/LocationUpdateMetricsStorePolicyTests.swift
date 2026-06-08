import CoreLocation
import Testing
import UIKit
@testable import miataru

@Suite("Location update metrics store policy tests")
struct LocationUpdateMetricsStorePolicyTests {
    @Test("Location update mode counters increment and reset after 24 hours")
    func locationUpdateModeCountersIncrementAndResetAfterTwentyFourHours() {
        var counts = LocationUpdateMetricsStore.ModeCounts()
        counts.increment(.foregroundLive)
        counts.increment(.significantChange)
        counts.increment(.smartFrequent)
        counts.increment(.manualFrequent)

        #expect(counts.foregroundLive == 1)
        #expect(counts.backgroundTotal == 3)

        let lastReset = Date(timeIntervalSince1970: 1_000)
        #expect(!LocationUpdateMetricsStore.shouldReset(
            now: lastReset.addingTimeInterval(86_399),
            lastReset: lastReset
        ))
        #expect(LocationUpdateMetricsStore.shouldReset(
            now: lastReset.addingTimeInterval(86_400),
            lastReset: lastReset
        ))
    }
}
