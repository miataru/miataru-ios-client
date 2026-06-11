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
    @Published private(set) var historyAnalysis: HistoryAnalysis?

    private var timestamps: [Double] = []
    private var cachedRange: ClosedRange<Double>?
    private var cachedVisible: [MiataruLocationData] = []
    private var cachedPolylineRange: ClosedRange<Double>?
    private var cachedPolylineMaxGapMeters = 0.0
    private var cachedPolylineSegments: [[CLLocationCoordinate2D]] = []
    private var hasCachedPolylineSegments = false
    private var cachedDownsampleRange: ClosedRange<Double>?
    private var cachedDownsampleLimit = 0
    private var cachedDownsampledEntries: [MiataruLocationData] = []
    private var hasCachedDownsampledEntries = false
    private var historyAnalysisTask: Task<Void, Never>?
    private var historyAnalysisSourceTask: Task<Void, Never>?
    private var historyAnalysisSource: HistoryAnalysisSource?
    private var historyAnalysisCache: [HistoryAnalysisCacheKey: HistoryAnalysis] = [:]
    private var historyAnalysisCacheOrder: [HistoryAnalysisCacheKey] = []
    private var pendingAnalysisRange: ClosedRange<Double>?
    private var pendingAnalysisBucketCount = HistoryAnalyzer.defaultBucketCount
    private var currentAnalysisKey: HistoryAnalysisCacheKey?
    private var analysisGeneration = 0
    private let maxHistoryAnalysisCacheCount = 12

    // Cache history and derived timestamp array; clear caches when new data arrives
    func setHistory(_ entries: [MiataruLocationData]) {
        analysisGeneration += 1
        let generation = analysisGeneration

        historyAnalysisTask?.cancel()
        historyAnalysisSourceTask?.cancel()

        // Keep history chronologically sorted so range/timeline math stays valid
        let sorted = entries.sorted { $0.TimestampDate.timeIntervalSince1970 < $1.TimestampDate.timeIntervalSince1970 }
        history = sorted
        timestamps = sorted.map { $0.TimestampDate.timeIntervalSince1970 }
        cachedRange = nil
        cachedVisible = []
        cachedPolylineRange = nil
        cachedPolylineMaxGapMeters = 0
        cachedPolylineSegments = []
        hasCachedPolylineSegments = false
        cachedDownsampleRange = nil
        cachedDownsampleLimit = 0
        cachedDownsampledEntries = []
        hasCachedDownsampledEntries = false
        historyAnalysis = nil
        historyAnalysisSource = nil
        historyAnalysisCache = [:]
        historyAnalysisCacheOrder = []
        pendingAnalysisRange = nil
        currentAnalysisKey = nil

        let samples = HistoryMetricSample.samples(from: sorted)
        guard !samples.isEmpty else { return }

        historyAnalysisSourceTask = Task { [weak self] in
            let source = await Task.detached(priority: .utility) {
                HistoryAnalysisSource(samples: samples)
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.analysisGeneration == generation else { return }

            self.historyAnalysisSource = source
            if let pendingAnalysisRange = self.pendingAnalysisRange {
                let bucketCount = self.pendingAnalysisBucketCount
                self.pendingAnalysisRange = nil
                self.scheduleAnalysis(in: pendingAnalysisRange, bucketCount: bucketCount)
            }
        }
    }

    func scheduleAnalysis(in range: ClosedRange<Double>?, bucketCount: Int = HistoryAnalyzer.defaultBucketCount) {
        guard !history.isEmpty else {
            cancelAnalysis()
            return
        }

        guard let source = historyAnalysisSource else {
            pendingAnalysisRange = range
            pendingAnalysisBucketCount = bucketCount
            return
        }

        let effectiveRange = range ?? source.timeRange
        guard let effectiveRange else {
            historyAnalysis = nil
            return
        }

        let key = HistoryAnalysisCacheKey(range: effectiveRange, bucketCount: bucketCount)
        if currentAnalysisKey == key {
            return
        }

        if let cachedAnalysis = historyAnalysisCache[key] {
            historyAnalysisTask?.cancel()
            currentAnalysisKey = key
            historyAnalysis = cachedAnalysis
            markAnalysisCacheKeyAsRecentlyUsed(key)
            return
        }

        historyAnalysisTask?.cancel()
        currentAnalysisKey = key
        let generation = analysisGeneration

        historyAnalysisTask = Task { [weak self] in
            let analysis = await Task.detached(priority: .utility) {
                source.analyze(in: effectiveRange, bucketCount: bucketCount)
            }.value

            guard !Task.isCancelled,
                  let self,
                  self.analysisGeneration == generation,
                  self.currentAnalysisKey == key else { return }

            self.storeAnalysisInCache(analysis, for: key)
            self.historyAnalysis = analysis
        }
    }

    func cancelAnalysis() {
        historyAnalysisTask?.cancel()
        historyAnalysisSourceTask?.cancel()
        historyAnalysisTask = nil
        historyAnalysisSourceTask = nil
        pendingAnalysisRange = nil
        currentAnalysisKey = nil
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

        let indexes = historyIndexRange(in: range)
        guard !indexes.isEmpty else {
            cachedRange = range
            cachedVisible = []
            return []
        }

        let slice = Array(history[indexes])
        cachedRange = range
        cachedVisible = slice
        return slice
    }

    func visibleHistoryCount(in range: ClosedRange<Double>?) -> Int {
        historyIndexRange(in: range).count
    }

    func closest(to timestamp: Double, in range: ClosedRange<Double>?) -> MiataruLocationData? {
        guard !history.isEmpty else { return nil }
        let lowerSearchIndex: Int
        let upperSearchIndex: Int

        if let range {
            lowerSearchIndex = lowerBoundInsertionIndex(for: range.lowerBound)
            upperSearchIndex = upperBoundInsertionIndex(for: range.upperBound) - 1
        } else {
            lowerSearchIndex = 0
            upperSearchIndex = timestamps.count - 1
        }

        guard lowerSearchIndex < timestamps.count,
              upperSearchIndex >= 0,
              lowerSearchIndex <= upperSearchIndex,
              let index = nearestIndex(to: timestamp, lowerBound: lowerSearchIndex, upperBound: upperSearchIndex) else {
            return nil
        }

        return history[index]
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

    func downsampledVisibleHistory(in range: ClosedRange<Double>?, selected: MiataruLocationData?, limit: Int = 150) -> [MiataruLocationData] {
        let visibleCount = visibleHistoryCount(in: range)
        guard visibleCount > limit else {
            return visibleHistory(in: range)
        }

        let baseEntries: [MiataruLocationData]
        if hasCachedDownsampledEntries,
           cachedDownsampleRange == range,
           cachedDownsampleLimit == limit {
            baseEntries = cachedDownsampledEntries
        } else {
            baseEntries = downsample(visibleHistory(in: range), selected: nil, limit: limit)
            cachedDownsampleRange = range
            cachedDownsampleLimit = limit
            cachedDownsampledEntries = baseEntries
            hasCachedDownsampledEntries = true
        }

        guard let selected else { return baseEntries }
        return insertingSelectedEntry(selected, into: baseEntries)
    }

    func polylineSegments(in range: ClosedRange<Double>?, maxGapMeters: Double = 5_000) -> [[CLLocationCoordinate2D]] {
        if hasCachedPolylineSegments,
           cachedPolylineRange == range,
           cachedPolylineMaxGapMeters == maxGapMeters {
            return cachedPolylineSegments
        }

        let segments = polylineSegments(from: visibleHistory(in: range), maxGapMeters: maxGapMeters)
        cachedPolylineRange = range
        cachedPolylineMaxGapMeters = maxGapMeters
        cachedPolylineSegments = segments
        hasCachedPolylineSegments = true
        return segments
    }

    func polylineSegments(from entries: [MiataruLocationData], maxGapMeters: Double = 5_000) -> [[CLLocationCoordinate2D]] {
        guard !entries.isEmpty else { return [] }
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        current.reserveCapacity(entries.count)

        var lastCoordinate: CLLocationCoordinate2D?
        for entry in entries {
            let coord = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)

            if let lastCoordinate,
               distanceMeters(from: lastCoordinate, to: coord) > maxGapMeters,
               !current.isEmpty {
                segments.append(current)
                current = []
            }

            current.append(coord)
            lastCoordinate = coord
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }

    private func distanceMeters(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
            cos(startLatitude) * cos(endLatitude) *
            sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }

    func historyColorRatio(for timestamp: Double) -> Double? {
        guard let first = timestamps.first,
              let last = timestamps.last else {
            return nil
        }

        let total = last - first
        guard total > 0 else { return 0 }
        return min(max((timestamp - first) / total, 0), 1)
    }

    private func historyIndexRange(in range: ClosedRange<Double>?) -> Range<Int> {
        guard !history.isEmpty else { return 0..<0 }
        guard let range else { return history.startIndex..<history.endIndex }
        guard range.lowerBound <= range.upperBound else { return 0..<0 }

        let startIndex = lowerBoundInsertionIndex(for: range.lowerBound)
        let endIndex = upperBoundInsertionIndex(for: range.upperBound)
        guard startIndex < endIndex else { return 0..<0 }
        return startIndex..<endIndex
    }

    private func insertingSelectedEntry(_ selected: MiataruLocationData, into entries: [MiataruLocationData]) -> [MiataruLocationData] {
        guard !entries.contains(where: { isSameHistoryEntry($0, selected) }) else {
            return entries
        }

        var result = entries
        let selectedTimestamp = selected.TimestampDate.timeIntervalSince1970
        if let insertionIndex = result.firstIndex(where: { $0.TimestampDate.timeIntervalSince1970 > selectedTimestamp }) {
            result.insert(selected, at: insertionIndex)
        } else {
            result.append(selected)
        }
        return result
    }

    private func isSameHistoryEntry(_ lhs: MiataruLocationData, _ rhs: MiataruLocationData) -> Bool {
        lhs.Timestamp == rhs.Timestamp &&
            lhs.Latitude == rhs.Latitude &&
            lhs.Longitude == rhs.Longitude
    }

    private func lowerBound(for value: Double) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        let low = lowerBoundInsertionIndex(for: value)
        return low < timestamps.count ? low : timestamps.count - 1
    }

    private func upperBound(for value: Double) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        let index = max(0, upperBoundInsertionIndex(for: value) - 1)
        return index < timestamps.count ? index : timestamps.count - 1
    }

    private func lowerBoundInsertionIndex(for value: Double) -> Int {
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

    private func upperBoundInsertionIndex(for value: Double) -> Int {
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
        return low
    }

    private func nearestIndex(to value: Double, lowerBound: Int, upperBound: Int) -> Int? {
        guard !timestamps.isEmpty,
              lowerBound >= 0,
              upperBound < timestamps.count,
              lowerBound <= upperBound else {
            return nil
        }

        var low = lowerBound
        var high = upperBound
        while low <= high {
            let mid = (low + high) / 2
            if timestamps[mid] == value {
                return mid
            } else if timestamps[mid] < value {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let clampedLow = min(max(low, lowerBound), upperBound)
        let clampedHigh = min(max(high, lowerBound), upperBound)
        let lowDiff = abs(timestamps[clampedLow] - value)
        let highDiff = abs(timestamps[clampedHigh] - value)
        return lowDiff <= highDiff ? clampedLow : clampedHigh
    }

    private func storeAnalysisInCache(_ analysis: HistoryAnalysis, for key: HistoryAnalysisCacheKey) {
        historyAnalysisCache[key] = analysis
        markAnalysisCacheKeyAsRecentlyUsed(key)

        while historyAnalysisCacheOrder.count > maxHistoryAnalysisCacheCount {
            let staleKey = historyAnalysisCacheOrder.removeFirst()
            historyAnalysisCache[staleKey] = nil
        }
    }

    private func markAnalysisCacheKeyAsRecentlyUsed(_ key: HistoryAnalysisCacheKey) {
        historyAnalysisCacheOrder.removeAll { $0 == key }
        historyAnalysisCacheOrder.append(key)
    }
}

private struct HistoryAnalysisCacheKey: Hashable {
    let lowerMilliseconds: Int64
    let upperMilliseconds: Int64
    let bucketCount: Int

    init(range: ClosedRange<Double>, bucketCount: Int) {
        self.lowerMilliseconds = Int64((range.lowerBound * 1_000).rounded())
        self.upperMilliseconds = Int64((range.upperBound * 1_000).rounded())
        self.bucketCount = bucketCount
    }
}
