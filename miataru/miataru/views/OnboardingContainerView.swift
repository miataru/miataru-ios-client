/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * OnboardingContainerView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

enum OnboardingMode {
    case full
    case postUpdate
}

struct OnboardingContainerView: View {
    // Access the horizontal size class from the environment to distinguish between compact (iPhone) and regular (iPad) layouts
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    // Binding to control whether the onboarding is presented
    @Binding var isPresented: Bool
    let mode: OnboardingMode
    // Tracks the current page in the onboarding flow
    @State private var currentPage = 0
    
    var body: some View {
        #if os(macOS)
        // Use the macOS-specific onboarding container view
        Mac_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: mode)
        #else
        if horizontalSizeClass == .compact {
            // Show the iPhone-specific onboarding container view for compact width devices
            iPhone_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: mode)
        } else {
            // Show the iPad-specific onboarding container view for regular width devices
            iPad_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: mode)
        }
        #endif
    }
}

// Preview provider for SwiftUI previews
struct OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    static var previews: some View {
        OnboardingContainerView(isPresented: $isPresented, mode: .full)
    }
}

