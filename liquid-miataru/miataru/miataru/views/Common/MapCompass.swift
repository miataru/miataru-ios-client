import SwiftUI

struct MapCompass: View {
    /// Heading in degrees (0 = North, 90 = East, 180 = South, 270 = West)
    let heading: Double
    let size: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Compass circle
                Circle()
                    .stroke(Color.primary.opacity(0.5), lineWidth: 1)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.ultraThinMaterial))
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: size * 0.96, height: size * 0.96)
                    .offset(y: -size * 0.04)
                // Needle (points North)
                CompassNeedle(size: size * 0.5)
                    .rotationEffect(.degrees(heading))
                // N marker
                Text(NSLocalizedString("compass_north_label", comment: "Compass North label"))
                    //.font(.caption2.bold())
                    .font(.caption2.smallCaps().bold())
                    .foregroundColor(.primary)
                    .offset(y: -size * 0.36)
            }
            .frame(width: size, height: size)
            // Degree and direction label
            Text(compassLabel(for: heading))
                .font(.caption2)
                .foregroundColor(.primary)
                .padding(.top, 2)
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .cornerRadius(size/5 + 8)
        .shadow(radius: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("Compass", comment: "Accessibility label for compass"))
        .accessibilityValue(compassLabel(for: heading))
    }

    /// Returns e.g. "NE 45°"
    private func compassLabel(for heading: Double) -> String {
        let directions = [
            NSLocalizedString("compass_N", comment: "Compass North abbreviation"),
            NSLocalizedString("compass_NE", comment: "Compass North-East abbreviation"),
            NSLocalizedString("compass_E", comment: "Compass East abbreviation"),
            NSLocalizedString("compass_SE", comment: "Compass South-East abbreviation"),
            NSLocalizedString("compass_S", comment: "Compass South abbreviation"),
            NSLocalizedString("compass_SW", comment: "Compass South-West abbreviation"),
            NSLocalizedString("compass_W", comment: "Compass West abbreviation"),
            NSLocalizedString("compass_NW", comment: "Compass North-West abbreviation"),
            NSLocalizedString("compass_N", comment: "Compass North abbreviation (repeat for wraparound)")
        ]
        let index = Int((heading + 22.5) / 45.0) % 8
        let dir = directions[index]
        let deg = Int(round(heading))
        // Formatted string for direction and degree
        return String(format: NSLocalizedString("compass_%@ %d°", comment: "Compass direction and degree, e.g. 'NE 45°'"), dir, deg)
    }
}

// Neue, schönere Kompassnadel als View
struct CompassNeedle: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            // Südspitze (grau)
            NeedleHalf(size: size, isNorth: false)
                .fill(Color.gray)
            // Nordspitze (rot)
            NeedleHalf(size: size, isNorth: true)
                .fill(Color.red)
            // Mittelkreis
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.18, height: size * 0.18)
                .shadow(radius: 1)
        }
    }
}

struct NeedleHalf: Shape {
    let size: CGFloat
    let isNorth: Bool
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        if isNorth {
            // Nordspitze
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x - size/8, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y - size/2))
            path.addLine(to: CGPoint(x: center.x + size/8, y: center.y))
        } else {
            // Südspitze
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x - size/8, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + size/2))
            path.addLine(to: CGPoint(x: center.x + size/8, y: center.y))
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack {
        MapCompass(heading: 0, size: 48)
        MapCompass(heading: 45, size: 48)
        MapCompass(heading: 90, size: 48)
        MapCompass(heading: 135, size: 48)
        MapCompass(heading: 180, size: 48)
        MapCompass(heading: 225, size: 48)
        MapCompass(heading: 270, size: 48)
        MapCompass(heading: 315, size: 48)
    } .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue, .purple, .orange]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}
