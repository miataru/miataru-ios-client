/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * ColorExtensions.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-01-25.
 */

import SwiftUI

// MARK: - Color Extension for Contrast Adjustment
extension Color {
    /// Adjusts device color for better contrast in light/dark mode
    /// - Parameters:
    ///   - deviceColor: The original device color
    ///   - colorScheme: Current color scheme (light/dark)
    /// - Returns: Adjusted color with better contrast
    static func adjustedDeviceColor(_ deviceColor: Color, for colorScheme: ColorScheme) -> Color {
        // Convert to UIColor for easier manipulation
        let uiColor = UIColor(deviceColor)
        
        // Get RGB components
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        // Calculate luminance to determine if color is dark or light
        let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
        
        switch colorScheme {
        case .light:
            // In light mode, if the color is too light (white-ish), make it lighter gray
            if luminance > 0.85 {
                // Make it a light gray instead of white
                return Color(red: 0.8, green: 0.8, blue: 0.8)
            }
        case .dark:
            // In dark mode, if the color is too dark (black-ish), make it darker gray
            if luminance < 0.15 {
                // Make it a dark gray instead of black
                return Color(red: 0.3, green: 0.3, blue: 0.3)
            }
        @unknown default:
            break
        }
        
        // Return original color if no adjustment needed
        return deviceColor
    }
}
