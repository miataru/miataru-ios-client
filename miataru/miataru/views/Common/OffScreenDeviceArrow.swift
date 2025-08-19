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
    
    @State private var isVisible = false
    
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
            .animation(.easeInOut(duration: 0.3), value: isVisible)
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
        
        // Calculate intersection with screen edges
        let center = screenCenter
        let devicePoint = deviceScreenPoint
        
        // Vector from center to device
        let dx = devicePoint.x - center.x
        let dy = devicePoint.y - center.y
        
        // Calculate intersection with screen edges
        let leftIntersection = CGPoint(x: margin, y: center.y + (dy * (margin - center.x) / dx))
        let rightIntersection = CGPoint(x: screenSize.width - margin, y: center.y + (dy * (screenSize.width - margin - center.x) / dx))
        let topIntersection = CGPoint(x: center.x + (dx * (margin - center.y) / dy), y: margin)
        let bottomIntersection = CGPoint(x: center.x + (dx * (screenSize.height - margin - center.y) / dy), y: screenSize.height - margin)
        
        // Find the closest valid intersection
        var validIntersections: [CGPoint] = []
        
        if leftIntersection.y >= margin && leftIntersection.y <= screenSize.height - margin && dx < 0 {
            validIntersections.append(leftIntersection)
        }
        if rightIntersection.y >= margin && rightIntersection.y <= screenSize.height - margin && dx > 0 {
            validIntersections.append(rightIntersection)
        }
        if topIntersection.x >= margin && topIntersection.x <= screenSize.width - margin && dy < 0 {
            validIntersections.append(topIntersection)
        }
        if bottomIntersection.x >= margin && bottomIntersection.x <= screenSize.width - margin && dy > 0 {
            validIntersections.append(bottomIntersection)
        }
        
        // Return the closest intersection to the device
        if let closest = validIntersections.min(by: { 
            $0.distance(to: devicePoint) < $1.distance(to: devicePoint) 
        }) {
            // Apply intelligent spacing to prevent overlapping
            return applyIntelligentSpacing(to: closest, edge: determineEdge(for: closest))
        }
        
        // Fallback to nearest edge
        let edgeX = devicePoint.x < center.x ? margin : screenSize.width - margin
        let edgeY = devicePoint.y < center.y ? margin : screenSize.height - margin
        
        let fallbackPosition: CGPoint
        if abs(devicePoint.x - center.x) > abs(devicePoint.y - center.y) {
            fallbackPosition = CGPoint(x: edgeX, y: devicePoint.y)
        } else {
            fallbackPosition = CGPoint(x: devicePoint.x, y: edgeY)
        }
        
        return applyIntelligentSpacing(to: fallbackPosition, edge: determineEdge(for: fallbackPosition))
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
            totalArrows: 1
        )
    }
}
