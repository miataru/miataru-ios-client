//
//  AnimatedPolylineRenderer.swift
//  AnimatedPolylineKit
//
//  Draws the animated polyline when MapKit asks. Reads overlay.configuration and
//  overlay.progress (driven by the app or AnimatedPolylineAnimationDriver) to draw
//  the full route and the moving highlight patch. Does not drive time—only draws.
//

import MapKit
import SwiftUI
import UIKit

/// Renders an AnimatedPolylineOverlay: full route line plus a moving gradient patch along the path.
public final class AnimatedPolylineRenderer: MKOverlayRenderer {
    private var animatedOverlay: AnimatedPolylineOverlay? {
        overlay as? AnimatedPolylineOverlay
    }
    /// Stored so we can unregister in deinit; registry is used when progress is set off main thread.
    private var overlayID: ObjectIdentifier?

    public override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
        if let animated = overlay as? AnimatedPolylineOverlay {
            animated.renderer = self
            let id = ObjectIdentifier(animated)
            overlayID = id
            AnimatedPolylineOverlayRegistry.register(overlayID: id, renderer: self)
        }
    }

    deinit {
        if let id = overlayID {
            AnimatedPolylineOverlayRegistry.unregister(overlayID: id)
        }
    }

    /// MapKit calls this when the overlay needs drawing. We draw the full route then the moving patch.
    public override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = animatedOverlay, overlay.coordinates.count >= 2 else { return }

        let config = overlay.configuration
        let progress = overlay.progress
        let direction = config.direction
        let patchLength = config.patchLength
        let halfPatch = patchLength / 2

        // Patch is a short segment centered at progress (or 1 - progress for endToStart), moving along the path
        let patchCenter: Double
        switch direction {
        case .startToEnd:
            patchCenter = progress
        case .endToStart:
            patchCenter = 1 - progress
        }
        let patchStart = min(max(0, patchCenter - halfPatch), 1)
        let patchEnd = min(max(0, patchCenter + halfPatch), 1)

        let coords = overlay.coordinates
        var points: [CGPoint] = []
        for coord in coords {
            let mapPoint = MKMapPoint(coord)
            let point = self.point(for: mapPoint)
            points.append(point)
        }

        // Cumulative path length (normalized 0...1 at each vertex) so we can map progress to segment positions
        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 1..<points.count {
            let d = hypot(points[i].x - points[i-1].x, points[i].y - points[i-1].y)
            total += d
            lengths.append(total)
        }
        guard total > 0 else { return }
        let normLengths = lengths.map { $0 / total }

        let underlyingColor = UIColor(config.underlyingColor)
        let whiteBandFraction = CGFloat(config.patchWhiteBandFraction)
        let highlightBlend = CGFloat(config.patchHighlightBlend)

        let lineWidth = config.lineWidth / zoomScale
        context.setLineWidth(lineWidth)
        context.setLineCap(cgLineCap(config.lineCap))
        context.setLineJoin(cgLineJoin(config.lineJoin))

        // 1. Draw full polyline underneath (entire route in underlying color)
        context.saveGState()
        context.setStrokeColor(underlyingColor.cgColor)
        addFullPath(points: points, in: context)
        context.strokePath()
        context.restoreGState()

        // 2. Draw moving patch: short segment with route → highlight (blend toward white) → route gradient on top
        if patchEnd > patchStart {
            context.saveGState()
            drawPatchRouteWhiteRoute(
                points: points,
                normLengths: normLengths,
                from: patchStart,
                to: patchEnd,
                routeColor: underlyingColor,
                whiteBandFraction: whiteBandFraction,
                highlightBlend: highlightBlend,
                in: context,
                lineWidth: lineWidth
            )
            context.restoreGState()
        }
    }

    /// Strokes the full route path (used for the underlying line).
    private func addFullPath(points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.move(to: points[0])
        for i in 1..<points.count {
            context.addLine(to: points[i])
        }
    }

    /// Adds a path segment from normalized position t0 to t1 (used for clipping path to a range).
    private func drawPathSegment(
        points: [CGPoint],
        normLengths: [CGFloat],
        from t0: Double,
        to t1: Double,
        in context: CGContext
    ) {
        guard points.count >= 2, normLengths.count == points.count else { return }
        let t0c = CGFloat(t0)
        let t1c = CGFloat(t1)
        var started = false
        var lastPoint: CGPoint?
        for i in 0..<points.count {
            let norm = normLengths[i]
            if norm < t0c { continue }
            if norm > t1c {
                // Clip final segment to t1
                if i > 0, let last = lastPoint {
                    let segStart = normLengths[i - 1]
                    let segEnd = norm
                    if segStart < t1c && t1c < segEnd {
                        let f = (t1c - segStart) / (segEnd - segStart)
                        let x = last.x + (points[i].x - last.x) * f
                        let y = last.y + (points[i].y - last.y) * f
                        context.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                break
            }
            if !started {
                if i > 0 && normLengths[i - 1] < t0c {
                    let segStart = normLengths[i - 1]
                    let segEnd = norm
                    let f = (t0c - segStart) / (segEnd - segStart)
                    let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                    let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                    context.move(to: CGPoint(x: x, y: y))
                } else {
                    context.move(to: points[i])
                }
                started = true
            } else {
                context.addLine(to: points[i])
            }
            lastPoint = points[i]
        }
    }

    /// Draws the patch segment with a three-stop gradient: route color → highlight (blend toward white) → route color.
    private func drawPatchRouteWhiteRoute(
        points: [CGPoint],
        normLengths: [CGFloat],
        from t0: Double,
        to t1: Double,
        routeColor: UIColor,
        whiteBandFraction: CGFloat,
        highlightBlend: CGFloat,
        in context: CGContext,
        lineWidth: CGFloat
    ) {
        guard points.count >= 2, normLengths.count == points.count, t1 > t0 else { return }
        let t0c = CGFloat(t0)
        let t1c = CGFloat(t1)
        let range = t1c - t0c
        let halfTransition = (1 - whiteBandFraction) / 2
        let transitionStart = halfTransition
        let transitionEnd = halfTransition + whiteBandFraction
        let routeRGBA = rgbaComponents(from: routeColor)
        // Highlight color = route color blended toward white by highlightBlend (from config)
        let lightRouteRGBA: [CGFloat] = [
            routeRGBA[0] * (1 - highlightBlend) + highlightBlend,
            routeRGBA[1] * (1 - highlightBlend) + highlightBlend,
            routeRGBA[2] * (1 - highlightBlend) + highlightBlend,
            routeRGBA[3]
        ]

        // Build (point, normalized position within patch) for gradient along the segment
        var segmentPoints: [(CGPoint, CGFloat)] = []
        for i in 0..<points.count {
            let norm = normLengths[i]
            if norm < t0c { continue }
            if norm > t1c {
                if i > 0 {
                    let segStart = normLengths[i - 1]
                    let segEnd = norm
                    if segStart < t1c {
                        let f = (t1c - segStart) / (segEnd - segStart)
                        let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                        let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                        segmentPoints.append((CGPoint(x: x, y: y), 1))
                    }
                }
                break
            }
            if i > 0 && normLengths[i - 1] < t0c {
                let segStart = normLengths[i - 1]
                let segEnd = norm
                let f = (t0c - segStart) / (segEnd - segStart)
                let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                segmentPoints.append((CGPoint(x: x, y: y), 0))
            }
            let pos = (norm - t0c) / range
            segmentPoints.append((points[i], pos))
        }
        if segmentPoints.isEmpty { return }

        /// Returns RGBA for position t in [0,1] along the patch: route → highlight (middle) → route.
        func colorForPatchPosition(_ t: CGFloat) -> [CGFloat] {
            if t <= transitionStart {
                let f = transitionStart > 0 ? t / transitionStart : 1
                return [
                    routeRGBA[0] + (lightRouteRGBA[0] - routeRGBA[0]) * f,
                    routeRGBA[1] + (lightRouteRGBA[1] - routeRGBA[1]) * f,
                    routeRGBA[2] + (lightRouteRGBA[2] - routeRGBA[2]) * f,
                    routeRGBA[3] + (lightRouteRGBA[3] - routeRGBA[3]) * f
                ]
            }
            if t >= transitionEnd {
                let f = (1 - transitionEnd) > 0 ? (t - transitionEnd) / (1 - transitionEnd) : 1
                return [
                    lightRouteRGBA[0] + (routeRGBA[0] - lightRouteRGBA[0]) * f,
                    lightRouteRGBA[1] + (routeRGBA[1] - lightRouteRGBA[1]) * f,
                    lightRouteRGBA[2] + (routeRGBA[2] - lightRouteRGBA[2]) * f,
                    lightRouteRGBA[3] + (routeRGBA[3] - lightRouteRGBA[3]) * f
                ]
            }
            return lightRouteRGBA
        }

        context.setLineWidth(lineWidth)
        // Stroke each segment with the color at its midpoint for a smooth gradient along the patch
        for i in 1..<segmentPoints.count {
            let (p, pos) = segmentPoints[i]
            let (prevP, prevPos) = segmentPoints[i - 1]
            let t = (pos + prevPos) / 2
            let components = colorForPatchPosition(t)
            let color = CGColor(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: components
            ) ?? routeColor.cgColor
            context.setStrokeColor(color)
            context.move(to: prevP)
            context.addLine(to: p)
            context.strokePath()
        }
    }

    private func drawGradientSegment(
        points: [CGPoint],
        normLengths: [CGFloat],
        from t0: Double,
        to t1: Double,
        startColor: UIColor,
        endColor: UIColor,
        direction: AnimatedPolylineDirection,
        in context: CGContext,
        lineWidth: CGFloat
    ) {
        guard points.count >= 2, normLengths.count == points.count, t1 > t0 else { return }
        let t0c = CGFloat(t0)
        let t1c = CGFloat(t1)

        // Build list of (point, normalized position) for the gradient segment
        var segmentPoints: [(CGPoint, CGFloat)] = []
        for i in 0..<points.count {
            let norm = normLengths[i]
            if norm < t0c { continue }
            if norm > t1c {
                if i > 0 {
                    let segStart = normLengths[i - 1]
                    let segEnd = norm
                    if segStart < t1c {
                        let f = (t1c - segStart) / (segEnd - segStart)
                        let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                        let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                        let pos = (t1c - t0c) / (t1c - t0c)
                        segmentPoints.append((CGPoint(x: x, y: y), pos))
                    }
                }
                break
            }
            if i > 0 && normLengths[i - 1] < t0c {
                let segStart = normLengths[i - 1]
                let segEnd = norm
                let f = (t0c - segStart) / (segEnd - segStart)
                let x = points[i - 1].x + (points[i].x - points[i - 1].x) * f
                let y = points[i - 1].y + (points[i].y - points[i - 1].y) * f
                let pos = 0 as CGFloat
                segmentPoints.append((CGPoint(x: x, y: y), pos))
            }
            let pos = (norm - t0c) / (t1c - t0c)
            segmentPoints.append((points[i], pos))
        }

        if segmentPoints.isEmpty { return }

        context.setLineWidth(lineWidth)
        let startRGBA = rgbaComponents(from: startColor)
        let endRGBA = rgbaComponents(from: endColor)
        for i in 1..<segmentPoints.count {
            let (p, pos) = segmentPoints[i]
            let (prevP, prevPos) = segmentPoints[i - 1]
            let t = Double((pos + prevPos) / 2)
            let components: [CGFloat] = [
                startRGBA[0] + (endRGBA[0] - startRGBA[0]) * CGFloat(t),
                startRGBA[1] + (endRGBA[1] - startRGBA[1]) * CGFloat(t),
                startRGBA[2] + (endRGBA[2] - startRGBA[2]) * CGFloat(t),
                startRGBA[3] + (endRGBA[3] - startRGBA[3]) * CGFloat(t)
            ]
            let color = CGColor(
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                components: components
            ) ?? startColor.cgColor
            context.setStrokeColor(color)
            context.move(to: prevP)
            context.addLine(to: p)
            context.strokePath()
        }
    }

    private func rgbaComponents(from color: UIColor) -> [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b, a]
    }

    private func cgLineCap(_ cap: AnimatedPolylineLineCap) -> CGLineCap {
        switch cap {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    private func cgLineJoin(_ join: AnimatedPolylineLineJoin) -> CGLineJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
