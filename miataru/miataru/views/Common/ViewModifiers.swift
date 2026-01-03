/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * ViewModifiers.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

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
}
