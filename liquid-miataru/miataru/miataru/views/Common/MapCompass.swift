import SwiftUI

struct MapCompass: View {
    /// Heading in Grad (0 = Norden, 90 = Osten, 180 = Süden, 270 = Westen)
    let heading: Double
    let size: CGFloat

    var body: some View {
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
            // N-Markierung
            Text("N")
                .font(.caption2.bold())
                .foregroundColor(.primary)
                .offset(y: -size * 0.38)
        }
        .frame(width: size, height: size)
        .padding(4)
        .background(.thinMaterial)
        .cornerRadius(size/2 + 4)
        .shadow(radius: 1)
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
        MapCompass(heading: 90, size: 48)
        MapCompass(heading: 180, size: 48)
        MapCompass(heading: 270, size: 48)
    }
} 