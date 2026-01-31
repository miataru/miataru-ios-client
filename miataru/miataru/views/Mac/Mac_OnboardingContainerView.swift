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
    
    private let pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingLocationPermissionView()),
        AnyView(iPhone_3_OnboardingServerView()),
        AnyView(iPhone_4_OnboardingLocationHistoryView()),
        AnyView(iPhone_5_OnboardingQRcodeView()),
        AnyView(iPhone_7_OnboardingDoneView())
    ]
    
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
                        UserDefaults.standard.hasCompletedOnboarding = true
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
        Mac_OnboardingContainerView(isPresented: $isPresented, currentPage: $currentPage)
            .frame(width: 600, height: 400)
    }
}
