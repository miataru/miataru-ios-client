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
                    .background(Circle().fill(.ultraThinMaterial))
                // Nadel (zeigt nach Norden)
                CompassNeedle(size: size * 0.5)
                    .fill(Color.red)
                    .rotationEffect(.degrees(heading))
                // N-Markierung
                Text(NSLocalizedString("N", comment: "Compass North label"))
                    //.font(.caption2.bold())
                    .font(.caption2.smallCaps().bold())
                    .foregroundColor(.primary)
                    .offset(y: -size * 0.36)
            }
            .frame(width: size, height: size)
            // Gradzahl und Richtung
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

    /// Gibt z.B. "NE 45°" zurück
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
        // Formatierter String für Richtung und Gradzahl
        return String(format: NSLocalizedString("compass_%@ %d°", comment: "Compass direction and degree, e.g. 'NE 45°'"), dir, deg)
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
    } .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [.blue, .purple, .orange]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
}
