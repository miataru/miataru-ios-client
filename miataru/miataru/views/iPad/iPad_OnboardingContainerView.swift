/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_OnboardingContainerView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPad_OnboardingContainerView: View {
    @Binding var isPresented: Bool
    @Binding var currentPage: Int
    
    private var pages: [AnyView] {
        [
            AnyView(iPhone_1_OnboardingWelcomeView()),
            AnyView(iPhone_2_OnboardingLocationPermissionView()),
            AnyView(iPhone_3_OnboardingServerView()),
            AnyView(iPhone_4_OnboardingLocationHistoryView()),
            AnyView(iPhone_5_OnboardingQRcodeView()),
            AnyView(iPhone_6_OnboardingDoneView(onFinish: {
                UserDefaults.standard.hasCompletedOnboarding = true
                isPresented = false
            }))
        ]
    }
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    pages[index]
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

#Preview {
    // Beispiel-Bindings für die Vorschau
    @Previewable @State var isPresented = true
    @Previewable @State var currentPage = 0
    return iPad_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
}
