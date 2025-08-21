/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * PulsingAccuracyCircle.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct PulsingAccuracyCircle: View {

    @State private var isPulsing = false
    let easeGently = Animation.easeOut(duration: 1).repeatForever(autoreverses: true)

    let pulsingColor: Color
    let size: CGFloat
    private let maxScale: CGFloat = 1.2
    
    init(pulsingColor: Color = .blue, size: CGFloat) {
        self.pulsingColor = pulsingColor
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Outer circle - using opacity and scale that work better with 3D
            Circle()
                .fill(pulsingColor.gradient)
                .frame(width: size, height: size)
                //.blendMode(.lighten)
                .opacity(0.1)
                .scaleEffect(isPulsing ? 0.1 : 1.2)
                .zIndex(isPulsing ? 0 : 1)
                .animation(easeGently.delay(0.4), value: isPulsing)

            // Middle circle
            Circle()
                .fill(pulsingColor.gradient)
                .frame(width: size, height: size)
                //.blendMode(.screen)
                .opacity(0.2)
                .scaleEffect(isPulsing ? 0.3 : 1.1)
                .zIndex(isPulsing ? 0 : 3)
                .animation(easeGently.delay(0.6), value: isPulsing)

            // Inner circle
            Circle()
                .fill(pulsingColor.gradient)
                .frame(width: size, height: size)
                //.blendMode(.colorDodge)
                .opacity(0.3)
                .zIndex(isPulsing ? 0 : 3)
                .scaleEffect(isPulsing ? 0.2 : 1.2)
                .animation(easeGently.delay(0.8), value: isPulsing)
        }
        // Give the drawing group enough space for the scaled circles
        .frame(width: size * maxScale, height: size * maxScale)
        // Flatten the view so it isn't affected by MapKit's perspective
        .drawingGroup()
        .onAppear {
            withAnimation {
                isPulsing.toggle()
            }
        }
    }
}

#Preview {
    ZStack() {
        PulsingAccuracyCircle(pulsingColor: Color(#colorLiteral(red: 0.9686274529, green: 0.78039217, blue: 0.3450980484, alpha: 1)), size: 172)
    }
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
