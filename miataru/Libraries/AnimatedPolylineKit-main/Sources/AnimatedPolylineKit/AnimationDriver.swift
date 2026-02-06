//
//  AnimationDriver.swift
//  AnimatedPolylineKit
//
//  The animation driver turns time into progress [0, 1] and publishes it. The app
//  assigns that progress to overlay.progress so the renderer can draw the moving patch.
//

import Combine
import QuartzCore
import SwiftUI

/// Drives animation progress from 0 to 1 with configurable duration and easing,
/// and optionally loops. Use with an AnimatedPolylineOverlay to animate the gradient.
/// Does not draw anything; only produces progress that you bind to overlay.progress.
public final class AnimatedPolylineAnimationDriver: NSObject, ObservableObject {
    /// Current progress in [0, 1]. Assign this to overlay.progress each frame or on update.
    @Published public private(set) var progress: Double = 0

    private let configuration: AnimatedPolylineConfiguration
    private let loop: Bool
    /// Time when the current cycle started; used with CADisplayLink timestamp to compute elapsed.
    private var startTime: CFTimeInterval?
    /// Fires once per frame on the main run loop so progress updates are display-synced.
    private var displayLink: CADisplayLink?

    deinit {
        stop()
    }

    /// - Parameters:
    ///   - configuration: Used for duration and start/end easing.
    ///   - loop: If true, animation repeats from 0 after reaching 1.
    public init(configuration: AnimatedPolylineConfiguration, loop: Bool = true) {
        self.configuration = configuration
        self.loop = loop
    }

    /// Starts the animation. Progress updates will be published and can be bound to overlay.progress.
    public func start() {
        guard displayLink == nil else { return }
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stops the animation.
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        startTime = nil
    }

    /// Resets progress to 0 and optionally restarts.
    public func reset(andRestart: Bool = false) {
        progress = 0
        startTime = CACurrentMediaTime()
        if andRestart {
            start()
        }
    }

    /// Called once per frame by the display link. Converts elapsed time into eased progress.
    @objc private func tick(_ link: CADisplayLink) {
        guard let start = startTime else { return }
        let elapsed = link.timestamp - start
        let duration = configuration.duration
        if duration <= 0 {
            progress = 1
            if !loop { stop() }
            return
        }
        // Raw progress in [0, 1] for the current cycle
        var t = elapsed / duration
        if t >= 1 {
            if loop {
                // Keep fractional part and reanchor startTime so the next cycle continues smoothly
                t = t.truncatingRemainder(dividingBy: 1)
                startTime = link.timestamp - t * duration
            } else {
                progress = 1
                stop()
                return
            }
        }
        // Blend start easing (e.g. easeIn) and end easing (e.g. easeOut) over the cycle:
        // more start-like at the beginning, more end-like at the end.
        let easeStart = configuration.startEasing.apply(to: t)
        let easeEnd = configuration.endEasing.apply(to: t)
        let blended = easeStart * (1 - t) + easeEnd * t
        progress = blended
    }
}

/// Applies easing to a raw time value in [0, 1]. Use when driving progress manually (e.g. with Timer or SwiftUI animation).
public enum AnimatedPolylineEasingHelper {
    /// Returns eased progress in [0, 1] for raw time `t` in [0, 1], using start easing for the first half and end easing for the second half.
    public static func progress(
        t: Double,
        startEasing: AnimatedPolylineEasing,
        endEasing: AnimatedPolylineEasing
    ) -> Double {
        let easedStart = startEasing.apply(to: t)
        let easedEnd = endEasing.apply(to: t)
        return easedStart * (1 - t) + easedEnd * t
    }
}
