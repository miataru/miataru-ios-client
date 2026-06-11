/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryAnalysis.swift
 * miataru
 */

import Foundation
import MiataruAPIClient

struct HistoryMetricSample: Identifiable, Sendable {
    let id: Int
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let horizontalAccuracy: Double?
    let speedMetersPerSecond: Double?
}

struct HistoryMetricBucket: Identifiable, Sendable {
    let id: Int
    let startDate: Date
    let endDate: Date
    let averageSpeedKmh: Double?
    let maxSpeedKmh: Double?
    let averageAltitudeMeters: Double?
    let minAltitudeMeters: Double?
    let maxAltitudeMeters: Double?
    let sampleCount: Int
}

struct HistoryAnalysis: Sendable {
    let buckets: [HistoryMetricBucket]
    let startDate: Date?
    let endDate: Date?
    let totalDistanceMeters: Double?
    let maxSpeedKmh: Double?
    let minAltitudeMeters: Double?
    let maxAltitudeMeters: Double?
    let validSpeedBucketCount: Int
    let validAltitudeBucketCount: Int

    var speedValues: [Double?] {
        buckets.map(\.averageSpeedKmh)
    }

    var altitudeValues: [Double?] {
        buckets.map(\.averageAltitudeMeters)
    }

    func bucketIndex(for date: Date) -> Int? {
        guard let startDate,
              let endDate,
              endDate > startDate,
              !buckets.isEmpty else {
            return buckets.isEmpty ? nil : 0
        }

        let total = endDate.timeIntervalSince(startDate)
        guard total > 0, total.isFinite else { return nil }

        let elapsed = date.timeIntervalSince(startDate)
        let progress = min(max(elapsed / total, 0), 1)
        return Int((progress * Double(buckets.count - 1)).rounded())
    }

    func bucket(at index: Int?) -> HistoryMetricBucket? {
        guard let index, buckets.indices.contains(index) else { return nil }
        return buckets[index]
    }
}

extension HistoryMetricSample {
    static func samples(from entries: [MiataruLocationData]) -> [HistoryMetricSample] {
        entries.enumerated().map { index, entry in
            HistoryMetricSample(
                id: index,
                timestamp: entry.TimestampDate,
                latitude: entry.Latitude,
                longitude: entry.Longitude,
                altitude: entry.Altitude,
                horizontalAccuracy: entry.HorizontalAccuracy,
                speedMetersPerSecond: entry.Speed
            )
        }
    }
}
