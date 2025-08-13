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
    
    @State private var isVisible = false
    
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
                    .foregroundColor(.white)
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
        
        // Check if device is outside screen bounds
        let margin: CGFloat = 20
        let isOutsideScreen = deviceScreenPoint.x < margin || 
                             deviceScreenPoint.x > screenSize.width - margin ||
                             deviceScreenPoint.y < margin || 
                             deviceScreenPoint.y > screenSize.height - margin
        
        guard isOutsideScreen else { return nil }
        
        // Calculate arrow position on screen edge
        let arrowPosition = calculateEdgePosition(deviceScreenPoint: deviceScreenPoint)
        
        // Calculate rotation angle to point towards device
        let rotation = calculateRotationAngle(from: arrowPosition, to: deviceScreenPoint)
        
        return (position: arrowPosition, rotation: rotation)
    }
    
    private func coordinateToScreenPoint(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
        // Convert coordinate to screen point using map region
        let latRatio = (coordinate.latitude - mapRegion.center.latitude) / mapRegion.span.latitudeDelta
        let lonRatio = (coordinate.longitude - mapRegion.center.longitude) / mapRegion.span.longitudeDelta
        
        let screenX = screenCenter.x + CGFloat(lonRatio) * screenSize.width
        let screenY = screenCenter.y - CGFloat(latRatio) * screenSize.height // Inverted Y axis
        
        return CGPoint(x: screenX, y: screenY)
    }
    
    private func calculateEdgePosition(deviceScreenPoint: CGPoint) -> CGPoint {
        let margin: CGFloat = 30
        let screenBounds = CGRect(x: margin, y: margin, 
                                width: screenSize.width - 2 * margin, 
                                height: screenSize.height - 2 * margin)
        
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
            return closest
        }
        
        // Fallback to nearest edge
        let edgeX = devicePoint.x < center.x ? margin : screenSize.width - margin
        let edgeY = devicePoint.y < center.y ? margin : screenSize.height - margin
        
        if abs(devicePoint.x - center.x) > abs(devicePoint.y - center.y) {
            return CGPoint(x: edgeX, y: devicePoint.y)
        } else {
            return CGPoint(x: devicePoint.x, y: edgeY)
        }
    }
    
    private func calculateRotationAngle(from arrowPosition: CGPoint, to devicePoint: CGPoint) -> Double {
        let dx = devicePoint.x - arrowPosition.x
        let dy = devicePoint.y - arrowPosition.y
        let angle = atan2(dy, dx) * 180 / .pi
        return angle + 90 // Adjust for arrow pointing up by default
    }
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
            isMapRotated: false
        )
    }
}
