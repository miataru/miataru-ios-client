/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_7_OnboardingDoneView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_7_OnboardingDoneView: View {
    var onFinish: () -> Void = {}

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("You are Ready to Go!")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("done")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            Text("Miataru is set up and ready.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("You can change your settings or permissions anytime in the app.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Tap on Finish to start using Miataru.")
                .font(.body)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Finish") {
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    iPhone_7_OnboardingDoneView()
}
