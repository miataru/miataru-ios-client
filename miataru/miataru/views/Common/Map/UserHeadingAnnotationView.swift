/*
 * UserHeadingAnnotationView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 05.02.26.
 */

import SwiftUI

struct UserHeadingAnnotationView: View {
    let heading: Double?
    let isHeadingValid: Bool
    let mapHeading: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 36, height: 36)
            Circle()
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
            HeadingArrowShape()
                .fill(Color.accentColor)
                .opacity(isHeadingValid && heading != nil ? 1 : 0)
                // Adjust for map rotation so the arrow reflects on-screen direction
                .rotationEffect(.degrees((heading ?? 0) - mapHeading))
            Circle()
                .fill(Color.accentColor)
                .frame(width: 10, height: 10)
        }
    }
}

private struct HeadingArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tipY: CGFloat = -11
        let baseY: CGFloat = 2
        let halfBase: CGFloat = 4.5

        var path = Path()
        path.move(to: CGPoint(x: 0, y: tipY))
        path.addLine(to: CGPoint(x: halfBase, y: baseY))
        path.addLine(to: CGPoint(x: -halfBase, y: baseY))
        path.closeSubpath()

        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        return path.applying(transform)
    }
}
