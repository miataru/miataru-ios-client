/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * RouteRequestCounter.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 11.09.25.
 */

import Foundation
import Combine

/// Centralized manager for counting route requests with a simple calendar‑day reset.
/// Stores state in UserDefaults and exposes a shared observable instance for UI.
final class RouteRequestCounter: ObservableObject {
    static let shared = RouteRequestCounter()

    @Published private(set) var count: Int = 0

    private let userDefaults: UserDefaults
    private let countKey = "miataru_routeRequestCount"
    private let lastResetKey = "miataru_routeRequestLastReset"

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if userDefaults.object(forKey: countKey) != nil {
            count = userDefaults.integer(forKey: countKey)
        }
        checkAndResetIfNeeded()
    }

    /// Ensures that the counter is reset when a new calendar day starts.
    /// Uses the device calendar and compares against the stored last reset day start.
    func checkAndResetIfNeeded(now: Date = Date()) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let lastReset = userDefaults.object(forKey: lastResetKey) as? Date
        if let last = lastReset {
            if last < todayStart {
                reset(to: todayStart)
            }
        } else {
            // Initialize baseline so future day switches work deterministically
            userDefaults.set(todayStart, forKey: lastResetKey)
        }
    }

    /// Attempts to increment the request counter, enforcing an optional daily limit.
    /// Returns true if incremented; false if the limit would be exceeded.
    @discardableResult
    func canRequestAndIncrement(limit: Int? = nil) -> Bool {
        checkAndResetIfNeeded()
        if let limit = limit, count >= limit {
            return false
        }
        count += 1
        userDefaults.set(count, forKey: countKey)
        return true
    }

    /// Resets the counter to zero and updates the stored last reset day start.
    private func reset(to dayStart: Date) {
        count = 0
        userDefaults.set(0, forKey: countKey)
        userDefaults.set(dayStart, forKey: lastResetKey)
    }
}


