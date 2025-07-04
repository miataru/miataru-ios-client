import SwiftUI

struct iPhone_PinView: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            // Kopf
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: 3)
            // Nadel
            Rectangle()
                .fill(Color.gray)
                .frame(width: 4, height: 24)
                .cornerRadius(2)
                .offset(y: -2)
        }
    }
} 
