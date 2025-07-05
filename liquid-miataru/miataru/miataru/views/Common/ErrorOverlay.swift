import SwiftUI

struct ErrorOverlay: View {
    let message: String
    let visible: Bool

    var body: some View {
        if visible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(message)
                        .padding(16)
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: visible)
            .zIndex(1)
        }
    }
} 