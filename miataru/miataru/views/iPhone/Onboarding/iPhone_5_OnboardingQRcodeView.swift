/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_5_OnboardingQRcodeView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

struct iPhone_5_OnboardingQRcodeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Share & Scan with QR-Codes", tableName: "OnboardingQR")
                .font(.largeTitle)
                .fontWeight(.bold)
            Image("qrcode")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .padding(.horizontal)
                .accessibilityHidden(true)
            Text("Easily share your device ID or add others by scanning QR-Codes.", tableName: "OnboardingQR")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 8) {
                Text("To share:", tableName: "OnboardingQR").bold().font(.headline)
                Text("Show your QR-Code to someone you trust.", tableName: "OnboardingQR").font(.subheadline)
                Text("To add:", tableName: "OnboardingQR").bold().font(.headline)
                    Text("Scan a QR-Code from another device running Miataru.", tableName: "OnboardingQR")
                }.padding(.horizontal,10)
            Text("").padding(.bottom,16)
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    iPhone_5_OnboardingQRcodeView()
}
