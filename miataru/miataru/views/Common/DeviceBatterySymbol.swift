/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceBatterySymbol.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI

struct DeviceBatterySymbol: View {
    let batteryLevel: Double
    let deviceColor: Color
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    init(batteryLevel: Double, deviceColor: Color, size: CGFloat = 16) {
        self.batteryLevel = batteryLevel
        self.deviceColor = deviceColor
        self.size = size
    }
    
    var body: some View {
        Image(systemName: batterySymbolName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundColor(Color.adjustedDeviceColor(deviceColor, for: colorScheme))
            .shadow(radius: 4)
    }
    
    private var batterySymbolName: String {
        let percentage = Int(batteryLevel)
        
        switch percentage {
        case 100:
            return "battery.100percent"
        case 90...99:
            return "battery.75percent"
        case 75...89:
            return "battery.75percent"
        case 50...74:
            return "battery.50percent"
        case 25...49:
            return "battery.25percent"
        case 1...24:
            return "battery.0percent"
        default:
            return "battery.0percent"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 10) {
            DeviceBatterySymbol(batteryLevel: 100, deviceColor: .green)
            DeviceBatterySymbol(batteryLevel: 75, deviceColor: .blue)
            DeviceBatterySymbol(batteryLevel: 50, deviceColor: .orange)
            DeviceBatterySymbol(batteryLevel: 25, deviceColor: .red)
            DeviceBatterySymbol(batteryLevel: 0, deviceColor: .gray)
        }
        
        HStack(spacing: 10) {
            DeviceBatterySymbol(batteryLevel: 95, deviceColor: .purple, size: 20)
            DeviceBatterySymbol(batteryLevel: 60, deviceColor: .cyan, size: 20)
            DeviceBatterySymbol(batteryLevel: 15, deviceColor: .yellow, size: 20)
        }
    }
    .padding()
}
