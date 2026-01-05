/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_DeviceHistoryMapViewModel.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-12-24.
 */

import Foundation
import MapKit
import MiataruAPIClient

@MainActor
final class DeviceHistoryMapViewModel: ObservableObject {
    @Published private(set) var history: [MiataruLocationData] = []

    private var timestamps: [Double] = []
    private var cachedRange: ClosedRange<Double>?
    private var cachedVisible: [MiataruLocationData] = []

    // Cache history and derived timestamp array; clear caches when new data arrives
    func setHistory(_ entries: [MiataruLocationData]) {
        // Keep history chronologically sorted so range/timeline math stays valid
        let sorted = entries.sorted { $0.TimestampDate.timeIntervalSince1970 < $1.TimestampDate.timeIntervalSince1970 }
        history = sorted
        timestamps = sorted.map { $0.TimestampDate.timeIntervalSince1970 }
        cachedRange = nil
        cachedVisible = []
    }

    // Overall min/max timestamps used to drive the timeline range
    func timelineBounds() -> ClosedRange<Double>? {
        guard let first = timestamps.first, let last = timestamps.last else { return nil }
        return first...last
    }

    func visibleHistory(in range: ClosedRange<Double>?) -> [MiataruLocationData] {
        guard let range else { return history }
        if let cachedRange, cachedRange == range {
            return cachedVisible
        }

        guard let startIndex = lowerBound(for: range.lowerBound),
              let endIndex = upperBound(for: range.upperBound) else {
            cachedRange = range
            cachedVisible = []
            return []
        }

        // If the requested range is inverted or empty, return an empty result
        // to avoid constructing an invalid slice.
        if startIndex > endIndex {
            cachedRange = range
            cachedVisible = []
            return []
        }

        let slice = Array(history[startIndex...endIndex])
        cachedRange = range
        cachedVisible = slice
        return slice
    }

    func closest(to timestamp: Double, in range: ClosedRange<Double>?) -> MiataruLocationData? {
        guard !history.isEmpty else { return nil }
        let searchTimestamps: [Double]
        let searchEntries: [MiataruLocationData]

        if let range {
            let visible = visibleHistory(in: range)
            guard !visible.isEmpty else { return nil }
            searchEntries = visible
            searchTimestamps = visible.map { $0.TimestampDate.timeIntervalSince1970 }
        } else {
            searchEntries = history
            searchTimestamps = timestamps
        }

        guard let index = nearestIndex(to: timestamp, in: searchTimestamps) else { return nil }
        return searchEntries[index]
    }

    /// Downsample entries for annotation display only (not for polyline).
    /// Returns a subset of entries while maintaining chronological order.
    func downsample(_ entries: [MiataruLocationData], selected: MiataruLocationData?, limit: Int = 150) -> [MiataruLocationData] {
        guard !entries.isEmpty else { return [] }
        let strideValue = max(1, entries.count / max(limit, 1))
        var result: [MiataruLocationData] = []
        result.reserveCapacity(min(entries.count, limit + 1))

        for (idx, entry) in entries.enumerated() where idx % strideValue == 0 {
            result.append(entry)
        }

        // Insert selected entry in chronological order to maintain proper sequence
        if let selected, !result.contains(where: { $0.Timestamp == selected.Timestamp && $0.Latitude == selected.Latitude && $0.Longitude == selected.Longitude }) {
            let selectedTimestamp = selected.TimestampDate.timeIntervalSince1970
            // Find insertion point to maintain chronological order
            if let insertionIndex = result.firstIndex(where: { $0.TimestampDate.timeIntervalSince1970 > selectedTimestamp }) {
                result.insert(selected, at: insertionIndex)
            } else {
                result.append(selected)
            }
        }

        return result
    }

    func polylineSegments(from entries: [MiataruLocationData], maxGapMeters: Double = 5_000) -> [[CLLocationCoordinate2D]] {
        guard !entries.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []

        var lastLocation: CLLocation?
        for entry in entries {
            let coord = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

            if let last = lastLocation, location.distance(from: last) > maxGapMeters, !current.isEmpty {
                segments.append(current)
                current = []
            }

            current.append(coord)
            lastLocation = location
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }

    private func lowerBound(for value: Double) -> Int? {
        guard !timestamps.isEmpty else { return nil }
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
        return low < timestamps.count ? low : timestamps.count - 1
    }

    private func upperBound(for value: Double) -> Int? {
        guard !timestamps.isEmpty else { return nil }
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
        let index = max(0, low - 1)
        return index < timestamps.count ? index : timestamps.count - 1
    }

    private func nearestIndex(to value: Double, in array: [Double]) -> Int? {
        guard !array.isEmpty else { return nil }
        var low = 0
        var high = array.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if array[mid] == value {
                return mid
            } else if array[mid] < value {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let clampedLow = min(max(low, 0), array.count - 1)
        let clampedHigh = min(max(high, 0), array.count - 1)
        let lowDiff = abs(array[clampedLow] - value)
        let highDiff = abs(array[clampedHigh] - value)
        return lowDiff <= highDiff ? clampedLow : clampedHigh
    }
}

