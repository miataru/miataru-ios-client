import SwiftUI

// Hilfs-Extension für Kontrastbestimmung
extension Color {
    /// Returns true if the color is considered 'light' (für Kontrast)
    func isLight(threshold: Float = 0.6) -> Bool {
#if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return Float(luminance) > threshold
#else
        return false // macOS: ggf. NSColor analog
#endif
    }
}

struct MiataruMapMarker: View {
    var color: Color = .red
    var iconName: String = "mappin"
    var height: CGFloat = 40
    var body: some View {
        // Proportionen
        let circleDiameter = height * 0.65 // z.B. 26 bei 40
        let triangleHeight = height * 0.45 // z.B. 14 bei 40
        let triangleWidth = circleDiameter * 0.54 // z.B. 14 bei 26
        let iconSize = circleDiameter * 0.54 // z.B. 14 bei 26
        let totalWidth = max(circleDiameter, triangleWidth) + 4
        ZStack {
            // Pin-Spitze hinter dem Kreis
            Triangle()
                .fill(color.opacity(0.9))
                .background(
                    Triangle()
                        .fill(.ultraThinMaterial)
                )
                // Plastischer Rand mit Verlauf wie beim Kreis
                .overlay(
                    Triangle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    (color.isLight() ? Color.black : Color.white).opacity(0.7),
                                    (color.isLight() ? Color.black : Color.white).opacity(0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                .frame(width: triangleWidth, height: triangleHeight)
                .offset(y: circleDiameter/2 - triangleHeight/2 + 6)
                .shadow(radius: 1, y: 1)
            // Kopf (Kreis) mit getintetem Material
            Circle()
                // Farbiger Kreis mit dezentem Verlauf
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            color.opacity(1),
                            color.opacity(0.4)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                // Plastischer Rand mit Verlauf
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    (color.isLight() ? Color.black : Color.white).opacity(0.7),
                                    (color.isLight() ? Color.black : Color.white).opacity(0.2)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                )
                // Glanz-Overlay für den Kreis
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.18),
                                    Color.clear
                                ]),
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: circleDiameter * 0.7
                            )
                        )
                )
                // Dunkler radialer Verlauf für Plastizität
                /*.overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.18), // außen dunkler
                                    Color.clear // innen transparent
                                ]),
                                center: .center,
                                startRadius: circleDiameter * 0.5,
                                endRadius: circleDiameter * 0.98
                            )
                        )
                )*/
                .frame(width: circleDiameter, height: circleDiameter)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                .overlay(
                    Image(systemName: iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundColor(color.isLight() ? .black : .white)
                )
        }
        .frame(width: totalWidth, height: height)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        MiataruMapMarker(color: .red, height: 40)
        MiataruMapMarker(color: .blue, iconName: "car", height: 60)
        MiataruMapMarker(color: .green, iconName: "bicycle", height: 30)
        MiataruMapMarker(color: .orange, iconName: "star", height: 80)
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
