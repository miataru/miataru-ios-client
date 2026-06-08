/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HeadingSmoother.swift
 * miataru
 */

import Foundation

struct HeadingSmoother {
    static let defaultAccuracyThreshold: Double = 35
    static let defaultMinimumCourseSpeed: Double = 1.0

    private let alpha: Double
    private var lastSmoothedHeading: Double?

    init(alpha: Double = 0.25) {
        self.alpha = alpha
    }

    mutating func reset() {
        lastSmoothedHeading = nil
    }

    mutating func smooth(_ heading: Double) -> Double {
        let normalized = normalizedHeading(heading)
        guard let last = lastSmoothedHeading else {
            lastSmoothedHeading = normalized
            return normalized
        }

        let delta = normalized - last
        let wrappedDelta: Double = {
            if delta > 180 { return delta - 360 }
            if delta < -180 { return delta + 360 }
            return delta
        }()
        let smoothed = normalizedHeading(last + wrappedDelta * alpha)
        lastSmoothedHeading = smoothed
        return smoothed
    }

    mutating func blended(compass: Double,
                          course: Double?,
                          speed: Double?,
                          minimumCourseSpeed: Double = defaultMinimumCourseSpeed) -> Double {
        let normalizedCompass = normalizedHeading(compass)
        guard let course, course >= 0, let speed, speed >= minimumCourseSpeed else {
            return normalizedCompass
        }
        let normalizedCourse = normalizedHeading(course)
        let weight = min(max(speed / 4.0, 0.0), 1.0)
        let delta = normalizedCourse - normalizedCompass
        let wrappedDelta: Double = {
            if delta > 180 { return delta - 360 }
            if delta < -180 { return delta + 360 }
            return delta
        }()
        return normalizedHeading(normalizedCompass + wrappedDelta * weight)
    }

    private func normalizedHeading(_ heading: Double) -> Double {
        let normalized = heading.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
}
