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

// Conditional debug logger: compiled out in non-Debug builds
#if DEBUG
@inline(__always)
private func debugLog(_ message: @autoclosure () -> String) {
	print(message())
}
#else
@inline(__always)
private func debugLog(_ message: @autoclosure () -> String) {}
#endif

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
    let deviceName: String
    let deviceColor: Color
    let screenCenter: CGPoint
    let deviceCoordinate: CLLocationCoordinate2D
    let mapRegion: MKCoordinateRegion
    let screenSize: CGSize
    /// Whether the map is rotated. Kept for backwards compatibility; ignored for rendering while debugging.
    let isMapRotated: Bool
    /// Current map heading in degrees (clockwise). Used to rotate the device point around `screenCenter`.
    let mapHeading: Double
    let arrowIndex: Int // New parameter for positioning
    let totalArrows: Int // New parameter for positioning
    let behavior: ArrowBehavior // Determines what happens when tapped
    let onTap: () -> Void // Callback when arrow is tapped
    
    @State private var isVisible = false
    @State private var isPressed = false // Track press state for visual feedback
    
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
                // Arrow pointing to device
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(deviceColor)
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
            .opacity(isVisible ? 1.0 : 0.0)
            .scaleEffect(isPressed ? 0.9 : 1.0) // Visual feedback when pressed
            .animation(.easeInOut(duration: 0.3), value: isVisible)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .animation(.easeInOut(duration: 0.2), value: mapHeading) // Animate with heading changes
            .onTapGesture {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                
                // Call the onTap callback
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).delay(0.1)) {
                    isVisible = true
                }
            }
        }
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
        // Convert device coordinate to screen position
        let deviceScreenPointUnrotated = coordinateToScreenPoint(deviceCoordinate)
        // Rotate the device point around the screen center by the current map heading (invert sign for correct direction)
        let deviceScreenPoint = rotate(point: deviceScreenPointUnrotated, around: screenCenter, degrees: -mapHeading)
        
        // Debug: Print screen coordinates
        debugLog("📍 Device \(deviceName) screen position (rotated by heading \(mapHeading)): \(deviceScreenPoint), screen size: \(screenSize)")
        

        
        // Check if device is outside screen bounds
        let margin: CGFloat = 50 // Increased margin for better detection
        let isOutsideScreen = deviceScreenPoint.x < margin || 
                             deviceScreenPoint.x > screenSize.width - margin ||
                             deviceScreenPoint.y < margin || 
                             deviceScreenPoint.y > screenSize.height - margin
        
        debugLog("🔍 Device \(deviceName) is outside screen: \(isOutsideScreen) (margin: \(margin))")
        
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
        let margin: CGFloat = 30
        let center = screenCenter
        let devicePoint = deviceScreenPoint
        
        // Compute intersection with all edges and choose the closest valid one.
        var candidates: [(point: CGPoint, edge: Edge)] = []
        if let p = intersectionPoint(for: .left, from: center, towards: devicePoint, margin: margin) { candidates.append((p, .left)) }
        if let p = intersectionPoint(for: .right, from: center, towards: devicePoint, margin: margin) { candidates.append((p, .right)) }
        if let p = intersectionPoint(for: .top, from: center, towards: devicePoint, margin: margin) { candidates.append((p, .top)) }
        if let p = intersectionPoint(for: .bottom, from: center, towards: devicePoint, margin: margin) { candidates.append((p, .bottom)) }
        
        if let best = candidates.min(by: { $0.point.distance(to: center) < $1.point.distance(to: center) }) {
            // Corner snap: if near a corner, snap to the exact corner to avoid edge flip jitter
            let (cornerPoint, cornerDistance) = nearestCorner(to: best.point, margin: margin)
            let cornerSnapThreshold: CGFloat = 24
            if cornerDistance < cornerSnapThreshold {
                return cornerPoint
            }
            return applyIntelligentSpacing(to: best.point, edge: best.edge)
        }
        
        // Fallback: clamp device point to the nearest edge
        let clampedX = max(margin, min(screenSize.width - margin, devicePoint.x))
        let clampedY = max(margin, min(screenSize.height - margin, devicePoint.y))
        let dxLeft = abs(clampedX - margin)
        let dxRight = abs(clampedX - (screenSize.width - margin))
        let dyTop = abs(clampedY - margin)
        let dyBottom = abs(clampedY - (screenSize.height - margin))
        let minDist = min(dxLeft, dxRight, dyTop, dyBottom)
        if minDist == dxLeft { return applyIntelligentSpacing(to: CGPoint(x: margin, y: clampedY), edge: .left) }
        if minDist == dxRight { return applyIntelligentSpacing(to: CGPoint(x: screenSize.width - margin, y: clampedY), edge: .right) }
        if minDist == dyTop { return applyIntelligentSpacing(to: CGPoint(x: clampedX, y: margin), edge: .top) }
        return applyIntelligentSpacing(to: CGPoint(x: clampedX, y: screenSize.height - margin), edge: .bottom)
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
        let margin: CGFloat = 30
        
        if abs(position.x - margin) < 10 {
            return .left
        } else if abs(position.x - (screenSize.width - margin)) < 10 {
            return .right
        } else if abs(position.y - margin) < 10 {
            return .top
        } else {
            return .bottom
        }
    }
    
    /// Applies symmetric spacing around the base edge intersection to prevent arrow overlap
    /// and to keep motion stable when rotating.
    private func applyIntelligentSpacing(to basePosition: CGPoint, edge: Edge) -> CGPoint {
        let arrowSpacing: CGFloat = 60
        let margin: CGFloat = 30
        
        // Symmetric distribution around the base intersection point to keep motion smooth
        let offset = calculateSymmetricOffset(index: arrowIndex, total: totalArrows, spacing: arrowSpacing)
        switch edge {
        case .left, .right:
            let adjustedY = max(margin, min(screenSize.height - margin, basePosition.y + offset))
            return CGPoint(x: basePosition.x, y: adjustedY)
        case .top, .bottom:
            let adjustedX = max(margin, min(screenSize.width - margin, basePosition.x + offset))
            return CGPoint(x: adjustedX, y: basePosition.y)
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
    private func coordinateToScreenPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        // Convert coordinate to screen point using map region
        let latRatio = (coordinate.latitude - mapRegion.center.latitude) / mapRegion.span.latitudeDelta
        let lonRatio = (coordinate.longitude - mapRegion.center.longitude) / mapRegion.span.longitudeDelta
        
        let screenX = screenCenter.x + CGFloat(lonRatio) * screenSize.width
        let screenY = screenCenter.y - CGFloat(latRatio) * screenSize.height // Inverted Y axis
        
        // Debug: Print coordinate conversion details
        debugLog("🌍 Device \(deviceName) coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        debugLog("🗺️ Map region center: \(mapRegion.center.latitude), \(mapRegion.center.longitude)")
        debugLog("📏 Map span: \(mapRegion.span.latitudeDelta), \(mapRegion.span.longitudeDelta)")
        debugLog("📊 Ratios: lat=\(latRatio), lon=\(lonRatio)")
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
            isMapRotated: false,
            mapHeading: 45,
            arrowIndex: 0,
            totalArrows: 1,
            behavior: .jumpToLocation,
            onTap: {
                debugLog("Preview: Tapped on iPhone 13 arrow")
            }
        )
    }
}
