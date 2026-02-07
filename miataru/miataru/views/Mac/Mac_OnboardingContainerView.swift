/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * Mac_OnboardingContainerView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct Mac_OnboardingContainerView: View {
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
                AnyView(iPhone_7_OnboardingDoneView())
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
            pages.append(AnyView(iPhone_7_OnboardingDoneView()))
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
            
            HStack {
                if currentPage > 0 {
                    Button("Previous") { currentPage -= 1 }
                }
                Spacer()
                if currentPage < pages.count - 1 {
                    Button("Next") { currentPage += 1 }
                } else {
                    Button("Finish") {
                        switch mode {
                        case .postUpdate:
                            UserDefaults.standard.hasShownPostUpdateOnboarding = true
                        case .full:
                            UserDefaults.standard.hasCompletedOnboarding = true
                        }
                        isPresented = false
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

struct Mac_OnboardingContainerView_Previews: PreviewProvider {
    @State static var isPresented = true
    @State static var currentPage = 0
    static var previews: some View {
        Mac_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage, mode: .full)
            .frame(width: 600, height: 400)
    }
}
