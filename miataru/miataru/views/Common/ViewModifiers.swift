/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * ViewModifiers.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

enum MiataruZoomTransitionSource: Hashable {
    case device(String)
    case group(String)
}

struct OnboardingPageMotion: ViewModifier {
    @Environment(\.animationsAllowed) private var animationsAllowed
    let trigger: Int
    let isActive: Bool
    @State private var isVisible = false
    @State private var revealTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        let shouldAnimate = animationsAllowed && isActive

        content
            .opacity(isVisible || !shouldAnimate ? 1 : 0)
            .offset(y: isVisible || !shouldAnimate ? 0 : 22)
            .scaleEffect(isVisible || !shouldAnimate ? 1 : 0.97)
            .onAppear {
                reveal()
            }
            .onChange(of: trigger) { _, _ in
                reveal()
            }
            .onChange(of: isActive) { _, _ in
                reveal()
            }
            .onDisappear {
                revealTask?.cancel()
            }
    }

    private func reveal() {
        revealTask?.cancel()

        guard animationsAllowed, isActive else {
            isVisible = true
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isVisible = false
        }

        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
    }
}

/// ViewModifier that automatically applies the correct toolbar and tabbar backgrounds based on iOS version
/// iOS 26+: transparent background, iOS prior: ultrathin material
struct AdaptiveToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26: keep toolbar visible but transparent to avoid layout gaps
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.clear, for: .tabBar)
        } else {
            // iOS prior to 26: ultrathin material
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        }
    }
}

/// ViewModifier specifically for NavigationStack views
struct AdaptiveNavigationBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26: transparent background
            content
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarBackgroundVisibility(.hidden)
        } else {
            // iOS prior to 26: ultrathin material
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}

extension View {
    /// Applies adaptive toolbar backgrounds based on iOS version
    func adaptiveToolbarBackground() -> some View {
        modifier(AdaptiveToolbarBackground())
    }
    
    /// Applies adaptive navigation background based on iOS version
    func adaptiveNavigationBackground() -> some View {
        modifier(AdaptiveNavigationBackground())
    }

    func miataruStateTransition(_ animationsAllowed: Bool) -> some View {
        transition(animationsAllowed ? .opacity.combined(with: .move(edge: .top)) : .identity)
    }

    func miataruOverlayTransition(_ animationsAllowed: Bool) -> some View {
        transition(animationsAllowed ? .opacity.combined(with: .scale(scale: 0.92)) : .identity)
    }

    func miataruAnimated<V: Equatable>(
        _ animation: Animation = .easeInOut(duration: 0.25),
        value: V,
        animationsAllowed: Bool
    ) -> some View {
        self.animation(animationsAllowed ? animation : nil, value: value)
    }

    func onboardingPageMotion(trigger: Int, isActive: Bool) -> some View {
        modifier(OnboardingPageMotion(trigger: trigger, isActive: isActive))
    }
}
