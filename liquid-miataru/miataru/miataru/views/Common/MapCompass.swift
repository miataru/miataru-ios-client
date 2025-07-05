import SwiftUI

struct MapCompass: View {
    /// Heading in Grad (0 = Norden, 90 = Osten, 180 = Süden, 270 = Westen)
    let heading: Double
    let size: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Kompass-Kreis
                Circle()
                    .stroke(Color.primary, lineWidth: 2)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.thinMaterial))
                // Nadel (zeigt nach Norden)
                CompassNeedle(size: size * 0.7)
                    .fill(Color.red)
                    .rotationEffect(.degrees(heading))
                    .animation(.easeInOut(duration: 0.2), value: heading)
                // N-Markierung
                Text("N")
                    .font(.caption2.bold())
                    .foregroundColor(.primary)
                    .offset(y: -size * 0.38)
            }
            .frame(width: size, height: size)
            // Gradzahl und Richtung
            Text(compassLabel(for: heading))
                .font(.caption2)
                .foregroundColor(.primary)
                .padding(.top, 2)
        }
        .padding(4)
        .background(.thinMaterial)
        .cornerRadius(size/2 + 8)
        .shadow(radius: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kompass")
        .accessibilityValue(compassLabel(for: heading))
    }

    /// Gibt z.B. "NE 45°" zurück
    private func compassLabel(for heading: Double) -> String {
        let directions = ["N", "NO", "O", "SO", "S", "SW", "W", "NW", "N"]
        let index = Int((heading + 22.5) / 45.0) % 8
        let dir = directions[index]
        let deg = Int(round(heading))
        return String(format: "%@ %d°", dir, deg)
    }
}

/// Einfache Kompassnadel als Shape
struct CompassNeedle: Shape {
    let size: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        // Dreieckige Nadel nach oben
        path.move(to: CGPoint(x: center.x, y: center.y - size/2)) // Spitze oben
        path.addLine(to: CGPoint(x: center.x - size/8, y: center.y + size/4))
        path.addLine(to: CGPoint(x: center.x + size/8, y: center.y + size/4))
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
    }
} 