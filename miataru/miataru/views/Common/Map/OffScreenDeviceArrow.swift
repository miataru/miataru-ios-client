/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * OffScreenDeviceArrow.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MapKit
import Foundation

/// OffScreenDeviceArrow renders an arrow label at the screen edge pointing towards a device
/// that is currently outside the visible map region.
///
/// Algorithm overview (rotation-aware and smooth at edge transitions):
/// - Convert the device `CLLocationCoordinate2D` to an approximate screen point using
///   the current `MKCoordinateRegion` (simple linear mapping).
/// - Rotate that screen point around the `screenCenter` by the current `mapHeading` so
///   that the geometry matches the visual rotation of the map content.
/// - Cast a ray from `screenCenter` to the rotated device point and compute intersections
///   with all four screen edges. Pick the nearest valid intersection; this prevents abrupt
///   edge flips compared to angle-sector based edge selection.
/// - Snap to a corner when close (corner-snapping) to avoid jitter exactly at edge changes.
/// - Distribute multiple arrows symmetrically around the intersection point to keep motion
///   visually stable when rotating.
/// - Compute the arrow rotation to point from the edge position towards the (rotated)
///   device point.

struct OffScreenDeviceArrow: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    let deviceName: String
    let deviceColor: Color
    let screenCenter: CGPoint
    let deviceCoordinate: CLLocationCoordinate2D
    let mapRegion: MKCoordinateRegion
    let screenSize: CGSize
    /// Distance between the map center and the device in kilometers. Supplied by the caller.
    let distanceInKM: Double
    /// Whether the map is rotated. Kept for backwards compatibility; ignored for rendering while debugging.
    let isMapRotated: Bool
    /// Current map heading in degrees (clockwise). Used to rotate the device point around `screenCenter`.
    let mapHeading: Double
    let arrowIndex: Int // New parameter for positioning
    let totalArrows: Int // New parameter for positioning
    let behavior: ArrowBehavior // Determines what happens when tapped
    let isMapMoving: Bool // Whether the map is currently moving/animating
    let onTap: () -> Void // Callback when arrow is tapped
    
    @State private var isVisible = false
    @State private var isPressed = false // Track press state for visual feedback
    @State private var hasInitiallyAppeared = false // Track if arrow has made initial appearance

    // MARK: - Centralized visual/geometry constants (C)
    /// Margin used to decide if a device is considered "outside" (visibility hysteresis).
    private let visibilityMargin: CGFloat = 20
    /// Inset from the screen edge used for intersection and placement.
    private let edgeInsetPortrait: CGFloat = 42
    private let edgeInsetLandscape: CGFloat = 42
    /// Reduced in landscape to keep arrows closer to the top edge on short heights.
    private var edgeInset: CGFloat {
        // Landscape if width > height
        return (screenSize.width > screenSize.height) ? edgeInsetLandscape : edgeInsetPortrait
    }
    /// Distance threshold for snapping to corners to avoid edge-flip jitter.
    private let cornerSnapThreshold: CGFloat = 24
    /// Spacing between multiple arrows on the same edge or at corners.
    private let arrowSpacing: CGFloat = 80

    /// Segment length (in points) used to visualize distance.
    private let segmentLength: CGFloat = 3
    /// Spacing (in points) between arrow segments for clear separation.
    private let segmentSpacing: CGFloat = 1
    /// Maximum number of distance segments to display.
    private let maxArrowSegments: Int = 10
    /// Number of arrow segments representing the distance.
    /// Shows 1 segment per 50 km (capped by `maxArrowSegments`).
    private var arrowSegments: Int {
        let segments = Int(distanceInKM / 50.0)
        return min(segments, maxArrowSegments)
    }

    // Computed property to determine the best text color for contrast
    private var textColor: Color {
        // Convert device color to UIColor to check brightness
        let uiColor = UIColor(deviceColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate perceived brightness using standard formula
        let brightness = (0.299 * red + 0.587 * green + 0.114 * blue)
        
        // Use white text for dark backgrounds, black text for light backgrounds
        return brightness > 0.5 ? .black : .white
    }
    
    var body: some View {
        // Renders the arrow when the device is outside the visible bounds.
        // Map rotation is considered via `mapHeading` inside the geometry functions.
        if let arrowPosition = calculateArrowPosition() {
            // Reference to avoid unused warning while we transition away from this flag
            let _ = isMapRotated
            VStack(spacing: 4) {
                // Arrow pointing to device with distance-indicating segments
                SegmentedArrow(segments: arrowSegments,
                               color: deviceColor,
                               segmentLength: segmentLength,
                               segmentSpacing: segmentSpacing)
                    .rotationEffect(.degrees(arrowPosition.rotation))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                // Device name background
                Text(deviceName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(deviceColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .position(arrowPosition.position)
            .opacity(calculateOpacity())
            .scaleEffect(isPressed ? 0.9 : 1.0) // Visual feedback when pressed
            .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: isVisible)
            .animation(animationsAllowed ? .easeInOut(duration: 0.1) : nil, value: isPressed)
            .animation(animationsAllowed ? .easeInOut(duration: 0.2) : nil, value: mapHeading) // Animate with heading changes
            .animation(animationsAllowed ? .easeInOut(duration: 0.5) : nil, value: isMapMoving) // Fade in/out based on map movement
            .animation(animationsAllowed ? .easeInOut(duration: 3.0) : nil, value: hasInitiallyAppeared) // Slow fade out after initial appearance
            .onTapGesture {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                // Call the onTap callback
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                if animationsAllowed {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = pressing
                    }
                } else {
                    isPressed = pressing
                }
            }, perform: {})
            .onAppear {
                if animationsAllowed {
                    withAnimation(.easeInOut(duration: 0.3).delay(0.1)) {
                        isVisible = true
                    }
                } else {
                    isVisible = true
                }
                // After initial appearance, wait a moment then fade out if map is not moving
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !isMapMoving && isVisible {
                        if animationsAllowed {
                            withAnimation(.easeInOut(duration: 3.0)) {
                                hasInitiallyAppeared = true
                            }
                        } else {
                            hasInitiallyAppeared = true
                        }
                    }
                }
            }
            .onChange(of: isMapMoving) { oldValue, newValue in
                // When map starts moving, reset the initial appearance flag to show full opacity
                if newValue && hasInitiallyAppeared {
                    if animationsAllowed {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hasInitiallyAppeared = false
                        }
                    } else {
                        hasInitiallyAppeared = false
                    }
                }
                // When map stops moving, trigger fade out after a delay
                if !newValue && isVisible && !hasInitiallyAppeared {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if !isMapMoving && isVisible {
                            if animationsAllowed {
                                withAnimation(.easeInOut(duration: 3.0)) {
                                    hasInitiallyAppeared = true
                                }
                            } else {
                                hasInitiallyAppeared = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Calculates the opacity based on visibility, map movement, and initial appearance state.
    private func calculateOpacity() -> Double {
        guard isVisible else { return 0.0 }
        
        // If map is moving, always show at full opacity
        if isMapMoving {
            return 1.0
        }
        
        // If map is not moving:
        // - Show at full opacity initially (before hasInitiallyAppeared is true)
        // - Fade to 15% opacity after initial appearance
        return hasInitiallyAppeared ? 0.15 : 1.0
    }
    
    /// Calculates the final on-screen arrow position and its rotation angle.
    ///
    /// Steps:
    /// 1. Convert device coordinate to an unrotated screen point using the region.
    /// 2. Rotate that point by `mapHeading` around `screenCenter`.
    /// 3. If outside the margin, intersect the center→device ray with all edges and
    ///    choose the nearest intersection (with corner snapping).
    /// 4. Compute the rotation so the arrow points towards the (rotated) device point.
    private func calculateArrowPosition() -> (position: CGPoint, rotation: Double)? {
        // (A) Guard against invalid/degenerate region spans at the call site if desired:
        // If you'd prefer to skip rendering entirely while the region is invalid, early-return nil here.
        // Keeping the robust projection inside coordinateToScreenPoint avoids flicker.
        
        // Convert device coordinate to screen position
        let deviceScreenPointUnrotated = coordinateToScreenPoint(deviceCoordinate)
        // Rotate the device point around the screen center by the current map heading (invert sign for correct direction)
        let deviceScreenPoint = rotate(point: deviceScreenPointUnrotated, around: screenCenter, degrees: -mapHeading)
        
        // Debug: Print screen coordinates
        debugLog("📍 Device \(deviceName) screen position (rotated by heading \(mapHeading)): \(deviceScreenPoint), screen size: \(screenSize)")

        // Check if device is outside screen bounds using visibility hysteresis
        let isOutsideScreen =
            deviceScreenPoint.x < visibilityMargin ||
            deviceScreenPoint.x > screenSize.width - visibilityMargin ||
            deviceScreenPoint.y < visibilityMargin ||
            deviceScreenPoint.y > screenSize.height - visibilityMargin
        
        debugLog("🔍 Device \(deviceName) is outside screen: \(isOutsideScreen) (visibilityMargin: \(visibilityMargin))")
        
        guard isOutsideScreen else {
            debugLog("❌ Device \(deviceName) is inside screen bounds, no arrow needed")
            return nil
        }
        
        // Calculate arrow position on screen edge with intelligent spacing
        let arrowPosition = calculateIntelligentEdgePosition(deviceScreenPoint: deviceScreenPoint)
        
        // Calculate rotation angle to point towards device
        let rotation = calculateRotationAngle(from: arrowPosition, to: deviceScreenPoint)
        
        debugLog("✅ Showing arrow for \(deviceName) at position: \(arrowPosition) with rotation: \(rotation)")
        
        return (position: arrowPosition, rotation: rotation)
    }
    
    /// Computes the best edge position to place the arrow, using nearest-ray-intersection
    /// with corner-snapping and symmetric spacing for multiple arrows.
    private func calculateIntelligentEdgePosition(deviceScreenPoint: CGPoint) -> CGPoint {
        let center = screenCenter
        let devicePoint = deviceScreenPoint
        
        // Compute intersection with all edges and choose the closest valid one.
        var candidates: [(point: CGPoint, edge: Edge)] = []
        if let p = intersectionPoint(for: .left, from: center, towards: devicePoint, margin: edgeInset) { candidates.append((p, .left)) }
        if let p = intersectionPoint(for: .right, from: center, towards: devicePoint, margin: edgeInset) { candidates.append((p, .right)) }
        if let p = intersectionPoint(for: .top, from: center, towards: devicePoint, margin: edgeInset) { candidates.append((p, .top)) }
        if let p = intersectionPoint(for: .bottom, from: center, towards: devicePoint, margin: edgeInset) { candidates.append((p, .bottom)) }
        
        if let best = candidates.min(by: { $0.point.distance(to: center) < $1.point.distance(to: center) }) {
            // Corner snap: if near a corner, snap to the exact corner to avoid edge flip jitter
            let (cornerPoint, cornerDistance) = nearestCorner(to: best.point, margin: edgeInset)
            if cornerDistance < cornerSnapThreshold {
                // (D) Corner-cluster distribution: alternate arrows along both adjacent edges
                return applyCornerClusterSpacing(at: cornerPoint)
            }
            return applyIntelligentSpacing(to: best.point, edge: best.edge)
        }
        
        // Fallback: clamp device point to the nearest edge
        let clampedX = max(edgeInset, min(screenSize.width - edgeInset, devicePoint.x))
        let clampedY = max(edgeInset, min(screenSize.height - edgeInset, devicePoint.y))
        let dxLeft = abs(clampedX - edgeInset)
        let dxRight = abs(clampedX - (screenSize.width - edgeInset))
        let dyTop = abs(clampedY - edgeInset)
        let dyBottom = abs(clampedY - (screenSize.height - edgeInset))
        let minDist = min(dxLeft, dxRight, dyTop, dyBottom)
        if minDist == dxLeft { return applyIntelligentSpacing(to: CGPoint(x: edgeInset, y: clampedY), edge: .left) }
        if minDist == dxRight { return applyIntelligentSpacing(to: CGPoint(x: screenSize.width - edgeInset, y: clampedY), edge: .right) }
        if minDist == dyTop { return applyIntelligentSpacing(to: CGPoint(x: clampedX, y: edgeInset), edge: .top) }
        return applyIntelligentSpacing(to: CGPoint(x: clampedX, y: screenSize.height - edgeInset), edge: .bottom)
    }

    /// Intersects the ray from `center` to `devicePoint` with the given screen `edge`,
    /// considering the `margin` inset. Returns `nil` if the intersection lies outside
    /// the valid edge segment or behind the ray origin.
    private func intersectionPoint(for edge: Edge, from center: CGPoint, towards devicePoint: CGPoint, margin: CGFloat) -> CGPoint? {
        let dx = devicePoint.x - center.x
        let dy = devicePoint.y - center.y
        
        // Guard against zero direction vector
        guard dx != 0 || dy != 0 else { return nil }
        
        switch edge {
        case .left:
            guard dx != 0 else { return nil }
            let t = (margin - center.x) / dx
            guard t > 0 else { return nil }
            let y = center.y + t * dy
            guard y >= margin && y <= screenSize.height - margin else { return nil }
            return CGPoint(x: margin, y: y)
        case .right:
            guard dx != 0 else { return nil }
            let t = ((screenSize.width - margin) - center.x) / dx
            guard t > 0 else { return nil }
            let y = center.y + t * dy
            guard y >= margin && y <= screenSize.height - margin else { return nil }
            return CGPoint(x: screenSize.width - margin, y: y)
        case .top:
            guard dy != 0 else { return nil }
            let t = (margin - center.y) / dy
            guard t > 0 else { return nil }
            let x = center.x + t * dx
            guard x >= margin && x <= screenSize.width - margin else { return nil }
            return CGPoint(x: x, y: margin)
        case .bottom:
            guard dy != 0 else { return nil }
            let t = ((screenSize.height - margin) - center.y) / dy
            guard t > 0 else { return nil }
            let x = center.x + t * dx
            guard x >= margin && x <= screenSize.width - margin else { return nil }
            return CGPoint(x: x, y: screenSize.height - margin)
        }
    }
    
    private func determineEdge(for position: CGPoint) -> Edge {
        // NOTE: not used currently but kept for potential styling/logic per edge.
        if abs(position.x - edgeInset) < 10 {
            return .left
        } else if abs(position.x - (screenSize.width - edgeInset)) < 10 {
            return .right
        } else if abs(position.y - edgeInset) < 10 {
            return .top
        } else {
            return .bottom
        }
    }
    
    /// Applies symmetric spacing around the base edge intersection to prevent arrow overlap
    /// and to keep motion stable when rotating.
    private func applyIntelligentSpacing(to basePosition: CGPoint, edge: Edge) -> CGPoint {
        // Symmetric distribution around the base intersection point to keep motion smooth
        let offset = calculateSymmetricOffset(index: arrowIndex, total: totalArrows, spacing: arrowSpacing)
        switch edge {
        case .left, .right:
            let adjustedY = max(edgeInset, min(screenSize.height - edgeInset, basePosition.y + offset))
            return CGPoint(x: basePosition.x, y: adjustedY)
        case .top, .bottom:
            let adjustedX = max(edgeInset, min(screenSize.width - edgeInset, basePosition.x + offset))
            return CGPoint(x: adjustedX, y: basePosition.y)
        }
    }

    /// (D) Corner-cluster distribution: when snapping to a corner, distribute multiple arrows
    /// alternating along both adjacent edges (e.g., at top-left: along .top and .left).
    /// This reduces pile-ups exactly at the corner during rotation.
    private func applyCornerClusterSpacing(at cornerPoint: CGPoint) -> CGPoint {
        // Identify which corner this is.
        let topLeft = CGPoint(x: edgeInset, y: edgeInset)
        let topRight = CGPoint(x: screenSize.width - edgeInset, y: edgeInset)
        let bottomLeft = CGPoint(x: edgeInset, y: screenSize.height - edgeInset)
        let bottomRight = CGPoint(x: screenSize.width - edgeInset, y: screenSize.height - edgeInset)
        
        // Choose primary/secondary edges for alternating distribution.
        // Even indices go along the "primary" edge, odd along the "secondary".
        let isEven = (arrowIndex % 2 == 0)
        let offset = calculateSymmetricOffset(index: arrowIndex / 2, // group per edge
                                              total: (totalArrows + 1) / 2,
                                              spacing: arrowSpacing)

        switch cornerPoint {
        case topLeft:
            if isEven {
                // along .top → +x
                let x = max(edgeInset, min(screenSize.width - edgeInset, cornerPoint.x + offset))
                return CGPoint(x: x, y: edgeInset)
            } else {
                // along .left → +y
                let y = max(edgeInset, min(screenSize.height - edgeInset, cornerPoint.y + offset))
                return CGPoint(x: edgeInset, y: y)
            }
        case topRight:
            if isEven {
                // along .top → -x
                let x = max(edgeInset, min(screenSize.width - edgeInset, cornerPoint.x - offset))
                return CGPoint(x: x, y: edgeInset)
            } else {
                // along .right → +y
                let y = max(edgeInset, min(screenSize.height - edgeInset, cornerPoint.y + offset))
                return CGPoint(x: screenSize.width - edgeInset, y: y)
            }
        case bottomLeft:
            if isEven {
                // along .bottom → -x
                let x = max(edgeInset, min(screenSize.width - edgeInset, cornerPoint.x + offset))
                return CGPoint(x: x, y: screenSize.height - edgeInset)
            } else {
                // along .left → -y
                let y = max(edgeInset, min(screenSize.height - edgeInset, cornerPoint.y - offset))
                return CGPoint(x: edgeInset, y: y)
            }
        case bottomRight:
            if isEven {
                // along .bottom → +x (to the left from corner)
                let x = max(edgeInset, min(screenSize.width - edgeInset, cornerPoint.x - offset))
                return CGPoint(x: x, y: screenSize.height - edgeInset)
            } else {
                // along .right → -y
                let y = max(edgeInset, min(screenSize.height - edgeInset, cornerPoint.y - offset))
                return CGPoint(x: screenSize.width - edgeInset, y: y)
            }
        default:
            // Should not happen; fall back to the corner point itself.
            return cornerPoint
        }
    }
    
    /// Distributes `total` arrows symmetrically around the center index to avoid drift
    /// during rotation and to keep layout visually balanced.
    private func calculateSymmetricOffset(index: Int, total: Int, spacing: CGFloat) -> CGFloat {
        // Distribute arrows symmetrically around the intersection point
        if total <= 1 { return 0 }
        let centerIndex = (CGFloat(total - 1)) / 2.0
        return (CGFloat(index) - centerIndex) * spacing
    }
    
    /// Approximates the device position in screen coordinates using a linear mapping
    /// from `MKCoordinateRegion` to the current `screenSize`. This is sufficient for
    /// computing edge arrows; precise projection is not required here.
    ///
    /// (A) Robust projection: epsilon floors for deltas, optional longitude unwrap at the dateline,
    /// and clamping of ratios to keep numerics stable when the device is far outside the region.
    private func coordinateToScreenPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        // Epsilon in degrees to prevent division by near-zero spans (≈ stability only).
        let eps: CLLocationDegrees = 1e-9

        let latDelta = max(mapRegion.span.latitudeDelta, eps)
        let lonDelta = max(mapRegion.span.longitudeDelta, eps)

        // Optional: unwrap longitude difference across the dateline so that long diffs prefer the short arc.
        let dLon = deltaLongitude(coordinate.longitude, mapRegion.center.longitude)
        let dLat = coordinate.latitude - mapRegion.center.latitude
        
        let latRatioRaw = CGFloat(dLat / latDelta)
        let lonRatioRaw = CGFloat(dLon / lonDelta)

        // Proportionally scale ratios so the largest magnitude fits within the screen bounds.
        let maxScreens: CGFloat = 4
        let maxRatio = max(abs(latRatioRaw), abs(lonRatioRaw))
        let scale = (maxRatio > maxScreens) ? (maxScreens / maxRatio) : 1
        let latRatio = latRatioRaw * scale
        let lonRatio = lonRatioRaw * scale

        let screenX = screenCenter.x + lonRatio * screenSize.width
        let screenY = screenCenter.y - latRatio * screenSize.height // Inverted Y axis
        
        // Debug: Print coordinate conversion details
        debugLog("🌍 Device \(deviceName) coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        debugLog("🗺️ Map region center: \(mapRegion.center.latitude), \(mapRegion.center.longitude)")
        debugLog("📏 Map span: \(mapRegion.span.latitudeDelta), \(mapRegion.span.longitudeDelta)")
        debugLog("📊 Ratios (raw/scaled): lat=\(latRatioRaw)→\(latRatio), lon=\(lonRatioRaw)→\(lonRatio)")
        debugLog("🖥️ Screen center: \(screenCenter), screen size: \(screenSize)")
        debugLog("🎯 Calculated screen position: \(screenX), \(screenY)")
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    /// Returns the rotation angle (in degrees) for the arrow so that it visually points
    /// from the arrow's position towards the (rotated) device point. The base arrow asset
    /// points up, therefore a +90° adjustment is applied.
    private func calculateRotationAngle(from arrowPosition: CGPoint, to devicePoint: CGPoint) -> Double {
        let dx = devicePoint.x - arrowPosition.x
        let dy = devicePoint.y - arrowPosition.y
        let angle = atan2(dy, dx) * 180 / .pi
        return angle + 90 // Adjust for arrow pointing up by default
    }

    /// Rotates a point around a center by the given degrees (clockwise), returning
    /// the rotated screen coordinate.
    private func rotate(point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let cosA = cos(radians)
        let sinA = sin(radians)
        let rotatedX = translatedX * cosA - translatedY * sinA
        let rotatedY = translatedX * sinA + translatedY * cosA
        return CGPoint(x: rotatedX + center.x, y: rotatedY + center.y)
    }

    /// Finds the nearest screen corner (respecting the margin inset) to a given point,
    /// returning the corner coordinate and the distance. Used for corner-snapping to
    /// avoid jitter when transitioning between edges.
    private func nearestCorner(to point: CGPoint, margin: CGFloat) -> (CGPoint, CGFloat) {
        let topLeft = CGPoint(x: margin, y: margin)
        let topRight = CGPoint(x: screenSize.width - margin, y: margin)
        let bottomLeft = CGPoint(x: margin, y: screenSize.height - margin)
        let bottomRight = CGPoint(x: screenSize.width - margin, y: screenSize.height - margin)
        let corners = [topLeft, topRight, bottomLeft, bottomRight]
        var bestCorner = topLeft
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for c in corners {
            let d = point.distance(to: c)
            if d < bestDistance {
                bestDistance = d
                bestCorner = c
            }
        }
        return (bestCorner, bestDistance)
    }

    /// Compute shortest-arc longitude difference, handling the ±180° dateline wrap.
    private func deltaLongitude(_ lon: CLLocationDegrees, _ center: CLLocationDegrees) -> CLLocationDegrees {
        var d = lon - center
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }
}

/// A simple vertically segmented arrow pointing up.
struct SegmentedArrow: View {
    let segments: Int
    let color: Color
    let segmentLength: CGFloat
    let segmentSpacing: CGFloat

    private let shaftWidth: CGFloat = 2
    private let headHeight: CGFloat = 8
    private let headWidth: CGFloat = 12

    var body: some View {
        VStack(spacing: segmentSpacing) {
            ArrowHead()
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: shaftWidth,
                        lineCap: .round,
                        lineJoin: .miter,
                        miterLimit: 10
                    )
                )
                .frame(width: headWidth, height: headHeight)

            if segments < 3 {
                // Show a continuous shaft with the footprint of 3 segments (including spacing)
                let totalHeight = (3 * segmentLength) + (2 * segmentSpacing)
                Capsule(style: .circular)
                    .fill(color)
                    .frame(width: shaftWidth, height: totalHeight)
            } else {
                ForEach(0..<segments, id: \.self) { _ in
                    Capsule(style: .circular)
                        .fill(color)
                        .frame(width: shaftWidth, height: segmentLength)
                }
            }
        }
    }
}

/// Open arrowhead composed of a single polyline for a sharp, mitered tip.
struct ArrowHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        path.move(to: left)
        path.addLine(to: tip)
        path.addLine(to: right)
        return path
    }
}

enum Edge {
    case left, right, top, bottom
}

enum ArrowBehavior {
    case navigateToDevice // Navigate to device detail view
    case jumpToLocation   // Jump to location on current map
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
}

private extension Comparable {
    /// Clamp a comparable value into the closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .frame(width: 300, height: 400)
        
        OffScreenDeviceArrow(
            deviceName: "iPhone 13",
            deviceColor: .red,
            screenCenter: CGPoint(x: 150, y: 200),
            deviceCoordinate: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),
            mapRegion: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ),
            screenSize: CGSize(width: 300, height: 400),
            distanceInKM: 5,
            isMapRotated: false,
            mapHeading: 45,
            arrowIndex: 0,
            totalArrows: 3, // try >1 to see corner-cluster distribution
            behavior: .jumpToLocation,
            isMapMoving: true,
            onTap: {
                debugLog("Preview: Tapped on iPhone 13 arrow")
            }
        )
    }
}
