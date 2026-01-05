/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * PlaybackSpeedOverlay.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-05.
 */

import SwiftUI

/// A centered overlay that briefly displays the current playback speed.
struct PlaybackSpeedOverlay: View {
    let speed: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: speed > 1.0 ? "forward.fill" : "play.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            Text(String(format: NSLocalizedString("playback_speed_format", comment: "Playback speed indicator format like 1x or 2x"), speed))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(in: .rect(cornerRadius: 20))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.black.opacity(0.4))
                    )
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        PlaybackSpeedOverlay(speed: 2.0)
    }
}

