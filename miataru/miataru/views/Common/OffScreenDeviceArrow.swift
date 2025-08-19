import SwiftUI
import MapKit

struct OffScreenDeviceArrow: View {
    let deviceName: String
    let deviceColor: Color
    let screenCenter: CGPoint
    let deviceCoordinate: CLLocationCoordinate2D
    let mapRegion: MKCoordinateRegion
    let screenSize: CGSize
    let isMapRotated: Bool
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
        // Hide arrow when map is rotated
        if !isMapRotated, let arrowPosition = calculateArrowPosition() {
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
    
    private func calculateArrowPosition() -> (position: CGPoint, rotation: Double)? {
        // Convert device coordinate to screen position
        let deviceScreenPoint = coordinateToScreenPoint(deviceCoordinate)
        
        // Debug: Print screen coordinates
        let _ = print("📍 Device \(deviceName) screen position: \(deviceScreenPoint), screen size: \(screenSize)")
        

        
        // Check if device is outside screen bounds
        let margin: CGFloat = 50 // Increased margin for better detection
        let isOutsideScreen = deviceScreenPoint.x < margin || 
                             deviceScreenPoint.x > screenSize.width - margin ||
                             deviceScreenPoint.y < margin || 
                             deviceScreenPoint.y > screenSize.height - margin
        
        let _ = print("🔍 Device \(deviceName) is outside screen: \(isOutsideScreen) (margin: \(margin))")
        
        guard isOutsideScreen else { 
            let _ = print("❌ Device \(deviceName) is inside screen bounds, no arrow needed")
            return nil 
        }
        
        // Calculate arrow position on screen edge with intelligent spacing
        let arrowPosition = calculateIntelligentEdgePosition(deviceScreenPoint: deviceScreenPoint)
        
        // Calculate rotation angle to point towards device
        let rotation = calculateRotationAngle(from: arrowPosition, to: deviceScreenPoint)
        
        let _ = print("✅ Showing arrow for \(deviceName) at position: \(arrowPosition) with rotation: \(rotation)")
        
        return (position: arrowPosition, rotation: rotation)
    }
    
    private func calculateIntelligentEdgePosition(deviceScreenPoint: CGPoint) -> CGPoint {
        let margin: CGFloat = 30
        let center = screenCenter
        let devicePoint = deviceScreenPoint
        
        // Vector from center to device
        let dx = devicePoint.x - center.x
        let dy = devicePoint.y - center.y
        
        // Determine edge by angle sectors to ensure top/bottom usage when pointing up/down
        let angleRad = atan2(dy, dx) // -pi..pi (screen y grows downwards)
        let angleDeg = angleRad * 180 / .pi // -180..180
        let chosenEdge: Edge
        if angleDeg >= -135 && angleDeg < -45 {
            chosenEdge = .top
        } else if angleDeg >= 45 && angleDeg < 135 {
            chosenEdge = .bottom
        } else if angleDeg >= -45 && angleDeg < 45 {
            chosenEdge = .right
        } else {
            chosenEdge = .left
        }
        
        if let p = intersectionPoint(for: chosenEdge, from: center, towards: devicePoint, margin: margin) {
            return applyIntelligentSpacing(to: p, edge: chosenEdge)
        }
        
        // Fallback: clamp to edge in chosen orientation
        switch chosenEdge {
        case .top:
            let x = max(margin, min(screenSize.width - margin, devicePoint.x))
            return applyIntelligentSpacing(to: CGPoint(x: x, y: margin), edge: .top)
        case .bottom:
            let x = max(margin, min(screenSize.width - margin, devicePoint.x))
            return applyIntelligentSpacing(to: CGPoint(x: x, y: screenSize.height - margin), edge: .bottom)
        case .left:
            let y = max(margin, min(screenSize.height - margin, devicePoint.y))
            return applyIntelligentSpacing(to: CGPoint(x: margin, y: y), edge: .left)
        case .right:
            let y = max(margin, min(screenSize.height - margin, devicePoint.y))
            return applyIntelligentSpacing(to: CGPoint(x: screenSize.width - margin, y: y), edge: .right)
        }
    }

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
    
    private func applyIntelligentSpacing(to position: CGPoint, edge: Edge) -> CGPoint {
        let arrowSpacing: CGFloat = 80
        let margin: CGFloat = 30
        
        // Calculate offset based on arrow index and total arrows
        let offset = calculateOffset(for: edge, index: arrowIndex, total: totalArrows, spacing: arrowSpacing)
        
        switch edge {
        case .left, .right:
            // Vertical positioning for left/right edges
            let adjustedY = margin + offset
            return CGPoint(x: position.x, y: max(margin, min(screenSize.height - margin, adjustedY)))
            
        case .top, .bottom:
            // Horizontal positioning for top/bottom edges
            let adjustedX = margin + offset
            return CGPoint(x: max(margin, min(screenSize.width - margin, adjustedX)), y: position.y)
        }
    }
    
    private func calculateOffset(for edge: Edge, index: Int, total: Int, spacing: CGFloat) -> CGFloat {
        // Distribute arrows evenly along the edge
        let totalSpacing = CGFloat(total - 1) * spacing
        let startOffset = (edge == .left || edge == .right ? screenSize.height : screenSize.width) - (2 * 30) - totalSpacing
        let startPosition = startOffset / 2
        
        return startPosition + CGFloat(index) * spacing
    }
    
    private func coordinateToScreenPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        // Convert coordinate to screen point using map region
        let latRatio = (coordinate.latitude - mapRegion.center.latitude) / mapRegion.span.latitudeDelta
        let lonRatio = (coordinate.longitude - mapRegion.center.longitude) / mapRegion.span.longitudeDelta
        
        let screenX = screenCenter.x + CGFloat(lonRatio) * screenSize.width
        let screenY = screenCenter.y - CGFloat(latRatio) * screenSize.height // Inverted Y axis
        
        // Debug: Print coordinate conversion details
        let _ = print("🌍 Device \(deviceName) coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        let _ = print("🗺️ Map region center: \(mapRegion.center.latitude), \(mapRegion.center.longitude)")
        let _ = print("📏 Map span: \(mapRegion.span.latitudeDelta), \(mapRegion.span.longitudeDelta)")
        let _ = print("📊 Ratios: lat=\(latRatio), lon=\(lonRatio)")
        let _ = print("🖥️ Screen center: \(screenCenter), screen size: \(screenSize)")
        let _ = print("🎯 Calculated screen position: \(screenX), \(screenY)")
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    private func calculateRotationAngle(from arrowPosition: CGPoint, to devicePoint: CGPoint) -> Double {
        let dx = devicePoint.x - arrowPosition.x
        let dy = devicePoint.y - arrowPosition.y
        let angle = atan2(dy, dx) * 180 / .pi
        return angle + 90 // Adjust for arrow pointing up by default
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
            arrowIndex: 0,
            totalArrows: 1,
            behavior: .jumpToLocation,
            onTap: {
                print("Preview: Tapped on iPhone 13 arrow")
            }
        )
    }
}
