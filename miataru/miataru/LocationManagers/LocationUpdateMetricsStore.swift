/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateMetricsStore.swift
 * miataru
 */

import Foundation

struct LocationUpdateMetricsSnapshot: Equatable {
    let backgroundUpdateCount: Int
    let modeCounts: LocationUpdateMetricsStore.ModeCounts
    let lastBackgroundUpdate: Date?
}

final class LocationUpdateMetricsStore {
    enum CounterMode: String, CaseIterable, Equatable {
        case foregroundLive
        case significantChange
        case smartFrequent
        case manualFrequent
    }

    struct ModeCounts: Equatable {
        var foregroundLive: Int = 0
        var significantChange: Int = 0
        var smartFrequent: Int = 0
        var manualFrequent: Int = 0

        mutating func increment(_ mode: CounterMode) {
            switch mode {
            case .foregroundLive:
                foregroundLive += 1
            case .significantChange:
                significantChange += 1
            case .smartFrequent:
                smartFrequent += 1
            case .manualFrequent:
                manualFrequent += 1
            }
        }

        var backgroundTotal: Int {
            significantChange + smartFrequent + manualFrequent
        }

        static let zero = ModeCounts()
    }

    private let defaults: UserDefaults
    private let backgroundUpdateCountKey = "miataru_backgroundUpdateCount"
    private let foregroundLiveUpdateCountKey = "miataru_locationUpdateCountForegroundLive"
    private let significantChangeUpdateCountKey = "miataru_locationUpdateCountSignificantChange"
    private let smartFrequentUpdateCountKey = "miataru_locationUpdateCountSmartFrequent"
    private let manualFrequentUpdateCountKey = "miataru_locationUpdateCountManualFrequent"
    private let lastBackgroundUpdateKey = "miataru_lastBackgroundUpdate"
    private let backgroundMetricsLastResetKey = "miataru_backgroundMetricsLastReset"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> LocationUpdateMetricsSnapshot {
        LocationUpdateMetricsSnapshot(
            backgroundUpdateCount: defaults.object(forKey: backgroundUpdateCountKey) != nil ? defaults.integer(forKey: backgroundUpdateCountKey) : 0,
            modeCounts: ModeCounts(
                foregroundLive: defaults.integer(forKey: foregroundLiveUpdateCountKey),
                significantChange: defaults.integer(forKey: significantChangeUpdateCountKey),
                smartFrequent: defaults.integer(forKey: smartFrequentUpdateCountKey),
                manualFrequent: defaults.integer(forKey: manualFrequentUpdateCountKey)
            ),
            lastBackgroundUpdate: defaults.object(forKey: lastBackgroundUpdateKey) as? Date
        )
    }

    @discardableResult
    func resetIfNeeded(now: Date = Date()) -> LocationUpdateMetricsSnapshot? {
        guard let lastReset = defaults.object(forKey: backgroundMetricsLastResetKey) as? Date else {
            defaults.set(now, forKey: backgroundMetricsLastResetKey)
            return nil
        }

        guard Self.shouldReset(now: now, lastReset: lastReset) else {
            return nil
        }

        defaults.set(0, forKey: backgroundUpdateCountKey)
        defaults.set(now, forKey: backgroundMetricsLastResetKey)
        persist(.zero)
        return LocationUpdateMetricsSnapshot(
            backgroundUpdateCount: 0,
            modeCounts: .zero,
            lastBackgroundUpdate: defaults.object(forKey: lastBackgroundUpdateKey) as? Date
        )
    }

    @discardableResult
    func record(mode: CounterMode, now: Date = Date()) -> LocationUpdateMetricsSnapshot {
        _ = resetIfNeeded(now: now)
        var counts = load().modeCounts
        counts.increment(mode)

        var lastBackgroundUpdate = defaults.object(forKey: lastBackgroundUpdateKey) as? Date
        var backgroundUpdateCount = defaults.object(forKey: backgroundUpdateCountKey) != nil ? defaults.integer(forKey: backgroundUpdateCountKey) : 0
        if mode != .foregroundLive {
            lastBackgroundUpdate = now
            backgroundUpdateCount = counts.backgroundTotal
            defaults.set(backgroundUpdateCount, forKey: backgroundUpdateCountKey)
            defaults.set(now, forKey: lastBackgroundUpdateKey)
        }
        persist(counts)

        return LocationUpdateMetricsSnapshot(
            backgroundUpdateCount: backgroundUpdateCount,
            modeCounts: counts,
            lastBackgroundUpdate: lastBackgroundUpdate
        )
    }

    static func shouldReset(now: Date,
                            lastReset: Date?,
                            interval: TimeInterval = 24 * 60 * 60) -> Bool {
        guard let lastReset else { return false }
        return now.timeIntervalSince(lastReset) >= interval
    }

    private func persist(_ counts: ModeCounts) {
        defaults.set(counts.foregroundLive, forKey: foregroundLiveUpdateCountKey)
        defaults.set(counts.significantChange, forKey: significantChangeUpdateCountKey)
        defaults.set(counts.smartFrequent, forKey: smartFrequentUpdateCountKey)
        defaults.set(counts.manualFrequent, forKey: manualFrequentUpdateCountKey)
    }
}
