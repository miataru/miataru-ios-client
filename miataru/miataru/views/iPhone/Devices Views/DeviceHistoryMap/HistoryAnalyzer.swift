/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryAnalyzer.swift
 * miataru
 */

import Foundation

enum HistoryAnalyzer {
    static let defaultBucketCount = 320
    static let maxReasonableSpeedMetersPerSecond = 90.0
    static let maxUsableHorizontalAccuracy = 100.0

    static func analyze(
        samples: [HistoryMetricSample],
        bucketCount requestedBucketCount: Int = defaultBucketCount
    ) -> HistoryAnalysis {
        HistoryAnalysisSource(samples: samples).analyze(bucketCount: requestedBucketCount)
    }
}

struct HistoryAnalysisSource: Sendable {
    let timeRange: ClosedRange<Double>?

    private let samples: [PreparedHistoryMetricSample]
    private let timestamps: [Double]
    private let distancePrefixSums: [Double]

    init(samples inputSamples: [HistoryMetricSample]) {
        let sorted = inputSamples
            .filter(Self.isValidCoordinateSample)
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.id < rhs.id
                }
                return lhs.timestamp < rhs.timestamp
            }

        var preparedSamples: [PreparedHistoryMetricSample] = []
        preparedSamples.reserveCapacity(sorted.count)

        var previous: HistoryMetricSample?
        for sample in sorted {
            let gpsSpeed = Self.usableSpeedMetersPerSecond(from: sample)
            let derivedSpeed = Self.derivedSpeedMetersPerSecond(from: previous, to: sample)
            let segmentDistance = Self.segmentDistanceMeters(from: previous, to: sample)
            preparedSamples.append(
                PreparedHistoryMetricSample(
                    timestamp: sample.timestamp,
                    timestampSeconds: sample.timestamp.timeIntervalSince1970,
                    altitude: Self.usableAltitude(sample),
                    speedKmh: (gpsSpeed ?? derivedSpeed).map { $0 * 3.6 },
                    segmentDistanceMeters: segmentDistance
                )
            )
            previous = sample
        }

        self.samples = preparedSamples
        self.timestamps = preparedSamples.map(\.timestampSeconds)

        var distancePrefixSums = Array(repeating: 0.0, count: preparedSamples.count + 1)
        for (index, sample) in preparedSamples.enumerated() {
            distancePrefixSums[index + 1] = distancePrefixSums[index] + (sample.segmentDistanceMeters ?? 0)
        }
        self.distancePrefixSums = distancePrefixSums

        if let first = preparedSamples.first?.timestampSeconds,
           let last = preparedSamples.last?.timestampSeconds {
            self.timeRange = first...last
        } else {
            self.timeRange = nil
        }
    }

    func analyze(
        in requestedRange: ClosedRange<Double>? = nil,
        bucketCount requestedBucketCount: Int = HistoryAnalyzer.defaultBucketCount
    ) -> HistoryAnalysis {
        guard let rangeIndexes = indexes(in: requestedRange) else {
            return Self.emptyAnalysis
        }

        let startIndex = rangeIndexes.lowerBound
        let endIndex = rangeIndexes.upperBound
        let startDate = samples[startIndex].timestamp
        let endDate = samples[endIndex].timestamp

        let bucketCount = Self.targetBucketCount(
            requested: requestedBucketCount,
            startDate: startDate,
            endDate: endDate
        )

        var speedSums = Array(repeating: 0.0, count: bucketCount)
        var speedCounts = Array(repeating: 0, count: bucketCount)
        var speedMaxima = Array<Double?>(repeating: nil, count: bucketCount)
        var altitudeSums = Array(repeating: 0.0, count: bucketCount)
        var altitudeCounts = Array(repeating: 0, count: bucketCount)
        var altitudeMinima = Array<Double?>(repeating: nil, count: bucketCount)
        var altitudeMaxima = Array<Double?>(repeating: nil, count: bucketCount)
        var sampleCounts = Array(repeating: 0, count: bucketCount)

        var maxSpeedKmh: Double?
        var minAltitudeMeters: Double?
        var maxAltitudeMeters: Double?

        for index in startIndex...endIndex {
            let sample = samples[index]
            let bucketIndex = Self.bucketIndex(for: sample.timestamp, startDate: startDate, endDate: endDate, bucketCount: bucketCount)
            sampleCounts[bucketIndex] += 1

            if let speedKmh = sample.speedKmh {
                maxSpeedKmh = max(maxSpeedKmh ?? speedKmh, speedKmh)
                speedSums[bucketIndex] += speedKmh
                speedCounts[bucketIndex] += 1
                speedMaxima[bucketIndex] = max(speedMaxima[bucketIndex] ?? speedKmh, speedKmh)
            }

            if let altitude = sample.altitude {
                minAltitudeMeters = min(minAltitudeMeters ?? altitude, altitude)
                maxAltitudeMeters = max(maxAltitudeMeters ?? altitude, altitude)
                altitudeSums[bucketIndex] += altitude
                altitudeCounts[bucketIndex] += 1
                altitudeMinima[bucketIndex] = min(altitudeMinima[bucketIndex] ?? altitude, altitude)
                altitudeMaxima[bucketIndex] = max(altitudeMaxima[bucketIndex] ?? altitude, altitude)
            }
        }

        var buckets: [HistoryMetricBucket] = []
        buckets.reserveCapacity(bucketCount)
        for index in 0..<bucketCount {
            let averageSpeedKmh: Double? = speedCounts[index] > 0
                ? speedSums[index] / Double(speedCounts[index])
                : nil
            let averageAltitudeMeters: Double? = altitudeCounts[index] > 0
                ? altitudeSums[index] / Double(altitudeCounts[index])
                : nil

            buckets.append(
                HistoryMetricBucket(
                    id: index,
                    startDate: Self.bucketStartDate(index: index, startDate: startDate, endDate: endDate, bucketCount: bucketCount),
                    endDate: Self.bucketEndDate(index: index, startDate: startDate, endDate: endDate, bucketCount: bucketCount),
                    averageSpeedKmh: averageSpeedKmh,
                    maxSpeedKmh: speedMaxima[index],
                    averageAltitudeMeters: averageAltitudeMeters,
                    minAltitudeMeters: altitudeMinima[index],
                    maxAltitudeMeters: altitudeMaxima[index],
                    sampleCount: sampleCounts[index]
                )
            )
        }

        return HistoryAnalysis(
            buckets: buckets,
            startDate: startDate,
            endDate: endDate,
            totalDistanceMeters: totalDistanceMeters(from: startIndex, through: endIndex),
            maxSpeedKmh: maxSpeedKmh,
            minAltitudeMeters: minAltitudeMeters,
            maxAltitudeMeters: maxAltitudeMeters,
            validSpeedBucketCount: buckets.filter { $0.averageSpeedKmh != nil }.count,
            validAltitudeBucketCount: buckets.filter { $0.averageAltitudeMeters != nil }.count
        )
    }

    private static var emptyAnalysis: HistoryAnalysis {
        HistoryAnalysis(
            buckets: [],
            startDate: nil,
            endDate: nil,
            totalDistanceMeters: nil,
            maxSpeedKmh: nil,
            minAltitudeMeters: nil,
            maxAltitudeMeters: nil,
            validSpeedBucketCount: 0,
            validAltitudeBucketCount: 0
        )
    }

    private func indexes(in requestedRange: ClosedRange<Double>?) -> ClosedRange<Int>? {
        guard !timestamps.isEmpty else { return nil }
        let range = requestedRange ?? (timestamps[0]...timestamps[timestamps.count - 1])
        guard range.lowerBound <= range.upperBound else { return nil }

        let startIndex = lowerBound(for: range.lowerBound)
        let endIndex = upperBound(for: range.upperBound)
        guard startIndex < timestamps.count, endIndex >= 0, startIndex <= endIndex else { return nil }
        return startIndex...endIndex
    }

    private func totalDistanceMeters(from startIndex: Int, through endIndex: Int) -> Double? {
        guard endIndex > startIndex,
              distancePrefixSums.indices.contains(endIndex + 1),
              distancePrefixSums.indices.contains(startIndex + 1) else {
            return nil
        }

        let total = distancePrefixSums[endIndex + 1] - distancePrefixSums[startIndex + 1]
        return total > 0 ? total : nil
    }

    private func lowerBound(for value: Double) -> Int {
        var low = 0
        var high = timestamps.count
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    private func upperBound(for value: Double) -> Int {
        var low = 0
        var high = timestamps.count
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] > value {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low - 1
    }

    private static func targetBucketCount(requested: Int, startDate: Date, endDate: Date) -> Int {
        guard endDate > startDate else { return 1 }
        return min(320, max(1, requested))
    }

    private static func usableSpeedMetersPerSecond(from sample: HistoryMetricSample) -> Double? {
        guard hasUsableHorizontalAccuracy(sample),
              let speed = sample.speedMetersPerSecond,
              speed.isFinite,
              speed >= 0,
              speed <= HistoryAnalyzer.maxReasonableSpeedMetersPerSecond else {
            return nil
        }
        return speed
    }

    private static func segmentDistanceMeters(from previous: HistoryMetricSample?, to sample: HistoryMetricSample) -> Double? {
        guard let previous,
              derivedSpeedMetersPerSecond(from: previous, to: sample) != nil else {
            return nil
        }

        let distance = haversineDistanceMeters(from: previous, to: sample)
        guard distance.isFinite, distance >= 0 else { return nil }
        return distance
    }

    private static func derivedSpeedMetersPerSecond(from previous: HistoryMetricSample?, to sample: HistoryMetricSample) -> Double? {
        guard let previous,
              hasUsableHorizontalAccuracy(previous),
              hasUsableHorizontalAccuracy(sample) else {
            return nil
        }

        let elapsed = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard elapsed > 0, elapsed.isFinite else { return nil }

        let distance = haversineDistanceMeters(from: previous, to: sample)
        guard distance.isFinite, distance >= 0 else { return nil }

        let speed = distance / elapsed
        guard speed.isFinite,
              speed >= 0,
              speed <= HistoryAnalyzer.maxReasonableSpeedMetersPerSecond else {
            return nil
        }

        return speed
    }

    private static func hasUsableHorizontalAccuracy(_ sample: HistoryMetricSample) -> Bool {
        guard let horizontalAccuracy = sample.horizontalAccuracy else { return true }
        return horizontalAccuracy.isFinite &&
            horizontalAccuracy >= 0 &&
            horizontalAccuracy <= HistoryAnalyzer.maxUsableHorizontalAccuracy
    }

    private static func usableAltitude(_ sample: HistoryMetricSample) -> Double? {
        guard let altitude = sample.altitude, altitude.isFinite else { return nil }
        return altitude
    }

    private static func isValidCoordinateSample(_ sample: HistoryMetricSample) -> Bool {
        sample.timestamp.timeIntervalSince1970.isFinite &&
            sample.latitude.isFinite &&
            sample.longitude.isFinite &&
            (-90...90).contains(sample.latitude) &&
            (-180...180).contains(sample.longitude)
    }

    private static func bucketIndex(for date: Date, startDate: Date, endDate: Date, bucketCount: Int) -> Int {
        guard bucketCount > 1, endDate > startDate else { return 0 }
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0, total.isFinite else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        let progress = min(max(elapsed / total, 0), 1)
        return min(max(Int(floor(progress * Double(bucketCount))), 0), bucketCount - 1)
    }

    private static func bucketStartDate(index: Int, startDate: Date, endDate: Date, bucketCount: Int) -> Date {
        guard bucketCount > 1, endDate > startDate else { return startDate }
        let duration = endDate.timeIntervalSince(startDate) / Double(bucketCount)
        return startDate.addingTimeInterval(duration * Double(index))
    }

    private static func bucketEndDate(index: Int, startDate: Date, endDate: Date, bucketCount: Int) -> Date {
        guard bucketCount > 1, endDate > startDate else { return endDate }
        if index == bucketCount - 1 { return endDate }
        let duration = endDate.timeIntervalSince(startDate) / Double(bucketCount)
        return startDate.addingTimeInterval(duration * Double(index + 1))
    }

    private static func haversineDistanceMeters(from first: HistoryMetricSample, to second: HistoryMetricSample) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let firstLatitude = first.latitude * .pi / 180
        let secondLatitude = second.latitude * .pi / 180
        let latitudeDelta = (second.latitude - first.latitude) * .pi / 180
        let longitudeDelta = (second.longitude - first.longitude) * .pi / 180

        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
            cos(firstLatitude) * cos(secondLatitude) *
            sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}

private struct PreparedHistoryMetricSample: Sendable {
    let timestamp: Date
    let timestampSeconds: Double
    let altitude: Double?
    let speedKmh: Double?
    let segmentDistanceMeters: Double?
}
