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
    let mode: OnboardingMode
    @StateObject private var settings = SettingsManager.shared
    
    private var pages: [AnyView] {
        switch mode {
        case .postUpdate:
            return [
                AnyView(iPhone_1_OnboardingWelcomeView()),
                AnyView(iPhone_6_OnboardingDeviceKeyView()),
                AnyView(iPhone_7_OnboardingDoneView(onFinish: {
                    UserDefaults.standard.hasShownPostUpdateOnboarding = true
                    isPresented = false
                }))
            ]
        case .full:
            var pages: [AnyView] = [
                AnyView(iPhone_1_OnboardingWelcomeView()),
                AnyView(iPhone_2_OnboardingLocationPermissionView()),
                AnyView(iPhone_3_OnboardingServerView()),
                AnyView(iPhone_5_OnboardingQRcodeView())
            ]
            if settings.trackAndReportLocation {
                pages.append(AnyView(iPhone_4_OnboardingLocationHistoryView()))
            }
            if settings.trackAndReportLocation {
                pages.append(AnyView(iPhone_6_OnboardingDeviceKeyView()))
            }
            if settings.trackAndReportLocation {
                pages.append(AnyView(iPhone_8_OnboardingAllowedDeviceListView()))
            }
            pages.append(AnyView(iPhone_7_OnboardingDoneView(onFinish: {
                UserDefaults.standard.hasCompletedOnboarding = true
                isPresented = false
            })))
            return pages
        }
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
    return iPad_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: .full)
}
