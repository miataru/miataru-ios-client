//
//  AnimatedPolylineConfiguration.swift
//  AnimatedPolylineKit
//
//  Defines all visual and animation settings. The app supplies a full configuration;
//  the package does not define default colors, gradients, or animation settings.
//

import SwiftUI

/// Direction of the moving gradient along the polyline.
public enum AnimatedPolylineDirection: Sendable {
    /// Gradient moves from the first coordinate (start marker) toward the last (end marker).
    case startToEnd
    /// Gradient moves from the last coordinate (end marker) toward the first (start marker).
    case endToStart
}

/// Easing curve for the animation progress over time. Used by the animation driver
/// (and optionally AnimatedPolylineEasingHelper) to shape how progress advances.
public enum AnimatedPolylineEasing: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Applies the easing curve to a raw progress value in [0, 1].
    public func apply(to t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return t * (2 - t)
        case .easeInOut:
            if t < 0.5 {
                return 2 * t * t
            }
            return -1 + (4 - 2 * t) * t
        }
    }
}

/// Line cap style for the polyline stroke.
public enum AnimatedPolylineLineCap: Sendable {
    case butt
    case round
    case square
}

/// Line join style for the polyline stroke.
public enum AnimatedPolylineLineJoin: Sendable {
    case miter
    case round
    case bevel
}

/// Configuration for the animated polyline: underlying line color, moving patch (lighter/darker), direction, speed, easing, and line appearance.
/// Shared by the overlay (for drawing) and the animation driver (for duration and easing). All values supplied by the app.
public struct AnimatedPolylineConfiguration: Sendable {
    /// Color of the full polyline drawn underneath (visible along the entire route).
    public var underlyingColor: Color
    /// Length of the moving patch as a fraction of the total path length (e.g. 0.1 = 10%). The patch is a short segment (route color → highlight → route color) that moves along the route.
    public var patchLength: Double
    /// Fraction of the patch length that is the brightest highlight in the middle (e.g. 0.55 = 55%). The rest is transition from route color to highlight on each side.
    public var patchWhiteBandFraction: Double
    /// Blend factor toward white for the patch highlight (0 = route color only, 1 = full white). Used to compute the light tint of the route color in the moving patch.
    public var patchHighlightBlend: Double
    /// Direction the patch moves along the route.
    public var direction: AnimatedPolylineDirection
    /// Duration of one full animation cycle in seconds.
    public var duration: TimeInterval
    /// Easing applied at the start of the animation.
    public var startEasing: AnimatedPolylineEasing
    /// Easing applied at the end of the animation.
    public var endEasing: AnimatedPolylineEasing
    /// Line width in points.
    public var lineWidth: CGFloat
    /// Line cap style.
    public var lineCap: AnimatedPolylineLineCap
    /// Line join style.
    public var lineJoin: AnimatedPolylineLineJoin

    /// - Parameters:
    ///   - underlyingColor: Color of the full polyline (entire route).
    ///   - patchLength: Patch length as fraction of path (clamped to 0.02...1).
    ///   - patchWhiteBandFraction: Fraction of patch that is the bright band (clamped to 0.2...0.9).
    ///   - patchHighlightBlend: Blend toward white for the patch highlight (0...1).
    ///   - direction: Movement direction of the patch.
    ///   - duration: Animation cycle duration in seconds.
    ///   - startEasing: Easing at start of animation.
    ///   - endEasing: Easing at end of animation.
    ///   - lineWidth: Stroke width in points.
    ///   - lineCap: Line cap style.
    ///   - lineJoin: Line join style.
    public init(
        underlyingColor: Color,
        patchLength: Double,
        patchWhiteBandFraction: Double,
        patchHighlightBlend: Double,
        direction: AnimatedPolylineDirection,
        duration: TimeInterval,
        startEasing: AnimatedPolylineEasing,
        endEasing: AnimatedPolylineEasing,
        lineWidth: CGFloat,
        lineCap: AnimatedPolylineLineCap,
        lineJoin: AnimatedPolylineLineJoin
    ) {
        self.underlyingColor = underlyingColor
        // Clamp patch and band so the renderer always has valid fractions
        self.patchLength = min(1, max(0.02, patchLength))
        self.patchWhiteBandFraction = min(0.9, max(0.2, patchWhiteBandFraction))
        self.patchHighlightBlend = min(1, max(0, patchHighlightBlend))
        self.direction = direction
        self.duration = duration
        self.startEasing = startEasing
        self.endEasing = endEasing
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }
}
