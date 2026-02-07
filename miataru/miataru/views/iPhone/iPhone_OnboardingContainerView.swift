/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_OnboardingContainerView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_OnboardingContainerView: View {
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

struct iPhone_OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    @State static var currentPage = 0
    static var previews: some View {
        iPhone_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: .full)
    }
}
