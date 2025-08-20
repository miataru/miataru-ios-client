/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_MyDeviceQRCodeView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import QRCode

struct iPhone_MyDeviceQRCodeView: View {
    @State var content: String = "miataru://" + thisDeviceIDManager.shared.deviceID
    @State var correction: QRCode.ErrorCorrection = .low

    @State var dataColor: Color = .primary
    @State var eyeColor: Color = .primary
    @State var pupilColor: Color = .primary
    @State var backgroundColor: Color = .clear

    @State var pixelShape: String = "square"
    @State var eyeStyle: String = "square"
    @State var pupilStyle: String = "square"

    @State var dataInset: Double = 0
    @State var cornerRadiusFraction: Double = 0.5
    @State var rotationFraction: Double = 0.0
    
    @State private var showCopiedAlert = false

    let gradient = Gradient(colors: [.black, .pink])
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            ScrollView {
                VStack(spacing: 0) {
                    // QR Code Section
                    VStack(spacing: isLandscape ? 16 : 20) {
                        ZStack {
                            backgroundColor
                            qrContent
                                .components(.eyeOuter)
                                .fill(eyeColor)
                            qrContent
                                .components(.eyePupil)
                                .fill(pupilColor)
                            qrContent
                                .components(.onPixels)
                                .fill(dataColor)
                        }
                        .frame(
                            width: min(geometry.size.width * 0.6, geometry.size.height * 0.4, 300),
                            height: min(geometry.size.width * 0.6, geometry.size.height * 0.4, 300),
                            alignment: .center
                        )
                        .padding(.horizontal, isLandscape ? 20 : 16)
                        .padding(.vertical, isLandscape ? 12 : 16)
                        
                        // Title and explanation
                        VStack(spacing: isLandscape ? 8 : 12) {
                            Text("my_device_qr_code")
                                .font(isLandscape ? .title2 : .title)
                                .multilineTextAlignment(.center)
                            
                            Text("qr_code_explanation")
                                .font(isLandscape ? .caption : .body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, isLandscape ? 40 : 20)
                        }
                    }
                    .padding(.top, isLandscape ? 20 : 30)
                    
                    // Device ID Section
                    VStack(spacing: isLandscape ? 12 : 16) {
                        Text("device_id")
                            .font(isLandscape ? .subheadline : .headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: isLandscape ? 6 : 8) {
                            Text(thisDeviceIDManager.shared.deviceID)
                                .font(.system(isLandscape ? .caption : .footnote, design: .monospaced))
                                .padding(.horizontal, isLandscape ? 8 : 12)
                                .padding(.vertical, isLandscape ? 6 : 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Button(action: {
                                UIPasteboard.general.string = thisDeviceIDManager.shared.deviceID
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showCopiedAlert = true
                                }
                                
                                // Alert nach 2 Sekunden automatisch ausblenden
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showCopiedAlert = false
                                    }
                                }
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .foregroundColor(.blue)
                                    .font(isLandscape ? .title3 : .title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, isLandscape ? 20 : 16)
                    .padding(.top, isLandscape ? 16 : 20)
                    .padding(.bottom, isLandscape ? 20 : 30)
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: isLandscape ? .center : .top
                )
            }
            .navigationTitle("my_device")
            .navigationBarTitleDisplayMode(isLandscape ? .inline : .large)
        }
        .overlay(
            // Overlay für Kopier-Bestätigung
            Group {
                if showCopiedAlert {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            Text("device_id_copied_to_clipboard")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.8))
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .zIndex(1)
                }
            }
        )
    }
    
    private var qrContent: QRCodeShape {
        QRCodeShape(
            data: content.data(using: .utf8) ?? Data(),
            errorCorrection: correction
        )
    }
}

#Preview {
    iPhone_MyDeviceQRCodeView()
} 
