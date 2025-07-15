import SwiftUI
import Combine

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

class ErrorOverlayManager: ObservableObject {
    @Published var message: String = ""
    @Published var visible: Bool = false

    private var hideCancellable: AnyCancellable?

    func show(message: String, duration: TimeInterval = 3.0) {
        self.message = message
        withAnimation {
            self.visible = true
        }
        hideCancellable?.cancel()
        hideCancellable = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                withAnimation {
                    self?.visible = false
                }
            }
    }
}

#Preview {
    ErrorOverlay(message: "This is an example error message!", visible: true)
        .background(Color.gray.opacity(0.2))
        .edgesIgnoringSafeArea(.all)
}
