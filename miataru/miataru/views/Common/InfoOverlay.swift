/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * InfoOverlay.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 25.08.25.
 */

import SwiftUI
import Combine

struct InfoOverlay: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

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
                        .background(Color.blue.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            }
            .transition(animationsAllowed ? .scale.combined(with: .opacity) : .identity)
            .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: visible)
            .zIndex(1)
        }
    }
}

class InfoOverlayManager: ObservableObject {
    @Published var message: String = ""
    @Published var visible: Bool = false

    private var hideCancellable: AnyCancellable?

    func show(message: String, duration: TimeInterval = 3.0, animationsAllowed: Bool = true) {
        self.message = message
        if animationsAllowed {
            withAnimation {
                self.visible = true
            }
        } else {
            self.visible = true
        }
        hideCancellable?.cancel()
        hideCancellable = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                if animationsAllowed {
                    withAnimation {
                        self?.visible = false
                    }
                } else {
                    self?.visible = false
                }
            }
    }
}

#Preview {
    InfoOverlay(message: "This is an example info message!", visible: true)
        .background(Color.gray.opacity(0.2))
        .edgesIgnoringSafeArea(.all)
}
