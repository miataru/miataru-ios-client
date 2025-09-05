/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceNameLabel.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI

struct DeviceNameLabel: View {
    let deviceName: String
    let deviceID: String
    let font: Font
    let topPadding: CGFloat
    let opacity: Double
    
    init(deviceName: String, deviceID: String, font: Font = .callout, topPadding: CGFloat = 2, opacity: Double = 1.0) {
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.font = font
        self.topPadding = topPadding
        self.opacity = opacity
    }
    
    private var displayText: String {
        deviceName.isEmpty ? deviceID : deviceName
    }
    
    var body: some View {
        ZStack {
            // Outline/shadow effect for better readability
            ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                    if x != 0 || y != 0 {
                        Text(displayText)
                            .font(font)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .padding(.top, topPadding)
                            .offset(x: CGFloat(x), y: CGFloat(y))
                    }
                }
            }
            // Main text
            Text(displayText)
                .font(font)
                .foregroundColor(Color(UIColor.label).opacity(opacity))
                .padding(.top, topPadding)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DeviceNameLabel(deviceName: "iPhone 15 Pro", deviceID: "device123")
        
        DeviceNameLabel(deviceName: "", deviceID: "device456")
        
        DeviceNameLabel(deviceName: "iPad Air", deviceID: "device789", font: .caption2, topPadding: 1, opacity: 0.8)
    }
    .padding()
    .background(Color.blue.opacity(0.3))
}
