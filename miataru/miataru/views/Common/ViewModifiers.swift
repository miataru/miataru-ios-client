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
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .scaleEffect(isVisible ? 1 : 0.98)
            .animation(animationsAllowed ? .easeOut(duration: 0.32) : nil, value: isVisible)
            .onAppear {
                reveal()
            }
            .onChange(of: trigger) { _, _ in
                reveal()
            }
    }

    private func reveal() {
        guard animationsAllowed else {
            isVisible = true
            return
        }

        isVisible = false
        DispatchQueue.main.async {
            isVisible = true
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

    func onboardingPageMotion(trigger: Int) -> some View {
        modifier(OnboardingPageMotion(trigger: trigger))
    }
}
