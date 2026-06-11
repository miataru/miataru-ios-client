import Foundation
import Testing
@testable import miataru

@Suite("History analyzer")
struct HistoryAnalyzerTests {
    @Test("empty history returns an empty analysis")
    func emptyHistory() {
        let analysis = HistoryAnalyzer.analyze(samples: [])

        #expect(analysis.buckets.isEmpty)
        #expect(analysis.startDate == nil)
        #expect(analysis.totalDistanceMeters == nil)
    }

    @Test("single point creates one bucket without derived distance or speed")
    func singlePoint() throws {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000, altitude: 52)
        ])

        #expect(analysis.buckets.count == 1)
        #expect(analysis.totalDistanceMeters == nil)
        #expect(analysis.maxSpeedKmh == nil)
        #expect(analysis.minAltitudeMeters == 52)
        #expect(analysis.maxAltitudeMeters == 52)
    }

    @Test("same timestamps do not derive speed")
    func sameTimestampsDoNotDeriveSpeed() {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000, latitude: 52.0, longitude: 13.0),
            sample(id: 1, timestamp: 1_000, latitude: 52.001, longitude: 13.0)
        ])

        #expect(analysis.maxSpeedKmh == nil)
        #expect(analysis.totalDistanceMeters == nil)
    }

    @Test("missing speed is derived from distance and time")
    func derivesMissingSpeed() throws {
        let analysis = HistoryAnalyzer.analyze(
            samples: [
                sample(id: 0, timestamp: 1_000, latitude: 52.0, longitude: 13.0),
                sample(id: 1, timestamp: 1_100, latitude: 52.001, longitude: 13.0)
            ],
            bucketCount: 4
        )

        let maxSpeed = try #require(analysis.maxSpeedKmh)
        #expect(maxSpeed > 3)
        #expect(maxSpeed < 5)
        #expect(analysis.totalDistanceMeters != nil)
    }

    @Test("plausible provided speed is preferred")
    func usesProvidedSpeed() throws {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000, speedMetersPerSecond: 12),
            sample(id: 1, timestamp: 1_060, latitude: 52.0001, longitude: 13.0)
        ])

        let maxSpeed = try #require(analysis.maxSpeedKmh)
        #expect(abs(maxSpeed - 43.2) < 0.01)
    }

    @Test("speed outliers are ignored")
    func ignoresSpeedOutliers() {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000, speedMetersPerSecond: 120),
            sample(id: 1, timestamp: 1_001, latitude: 53.0, longitude: 13.0)
        ])

        #expect(analysis.maxSpeedKmh == nil)
        #expect(analysis.totalDistanceMeters == nil)
    }

    @Test("bad horizontal accuracy suppresses speed and distance")
    func badHorizontalAccuracySuppressesSpeed() {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000, horizontalAccuracy: 250, speedMetersPerSecond: 10),
            sample(id: 1, timestamp: 1_100, latitude: 52.001, longitude: 13.0, horizontalAccuracy: 250)
        ])

        #expect(analysis.maxSpeedKmh == nil)
        #expect(analysis.totalDistanceMeters == nil)
    }

    @Test("missing altitude leaves altitude graph empty")
    func missingAltitude() {
        let analysis = HistoryAnalyzer.analyze(samples: [
            sample(id: 0, timestamp: 1_000),
            sample(id: 1, timestamp: 1_060, latitude: 52.0001, longitude: 13.0)
        ])

        #expect(analysis.minAltitudeMeters == nil)
        #expect(analysis.maxAltitudeMeters == nil)
        #expect(analysis.validAltitudeBucketCount == 0)
    }

    @Test("large history is bucketed")
    func largeHistoryIsBucketed() {
        let samples = (0..<10_000).map { index in
            sample(
                id: index,
                timestamp: Double(1_000 + index),
                latitude: 52.0 + Double(index) * 0.000001,
                longitude: 13.0,
                altitude: 40 + Double(index % 20)
            )
        }

        let analysis = HistoryAnalyzer.analyze(samples: samples, bucketCount: 240)

        #expect(analysis.buckets.count == 240)
        #expect(analysis.validSpeedBucketCount > 0)
        #expect(analysis.validAltitudeBucketCount > 0)
        #expect(analysis.totalDistanceMeters != nil)
    }

    private func sample(
        id: Int,
        timestamp: Double,
        latitude: Double = 52.0,
        longitude: Double = 13.0,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = 10,
        speedMetersPerSecond: Double? = nil
    ) -> HistoryMetricSample {
        HistoryMetricSample(
            id: id,
            timestamp: Date(timeIntervalSince1970: timestamp),
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            speedMetersPerSecond: speedMetersPerSecond
        )
    }
}
