/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceHistoryTimelineOverlay.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-12-24.
 */

import SwiftUI

struct DeviceHistoryTimelineOverlay: View {
    let fullRange: ClosedRange<Double>
    @Binding var selection: ClosedRange<Double>
    @Binding var scrubValue: Double
    let ticks: [Double]
    let selectedCount: Int
    let totalCount: Int
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onScrubShown: () -> Void
    let stopPlayback: () -> Void
    let startPlayback: () -> Void
    let isPlaybackStepping: Bool
    let onScrubBegan: () -> Void
    let onScrubEnded: () -> Void
    let onSelectionDragBegan: () -> Void
    let onSelectionDragEnded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formattedDateTime(selection.lowerBound)) – \(formattedDateTime(selection.upperBound))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(String(format: NSLocalizedString("history_timeline_visible_count", comment: "Visible items count out of total"), selectedCount, totalCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if #available(iOS 26.0, *) {
                    Button(action: { onPlayPause() }) {
                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                            .id(isPlaying ? "pause-icon" : "play-icon")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title)
                            .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                            .padding(10)
                            .scaleEffect(isPlaying ? 1.05 : 1.0)
                    }
                    .buttonStyle(.glass)
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default,
                        value: isPlaying
                    )
                    .accessibilityLabel(
                        Text(
                            NSLocalizedString(
                                isPlaying ? "history_pause_timeline" : "history_play_timeline",
                                comment: "Play/pause timeline playback"
                            )
                        )
                    )
                } else {
                    Button(action: { onPlayPause() }) {
                        Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                            .id(isPlaying ? "pause-icon" : "play-icon")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title)
                            .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                            .padding(10)
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                            .scaleEffect(isPlaying ? 1.05 : 1.0)
                            .animation(
                                isPlaying
                                    ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                    : .default,
                                value: isPlaying
                            )
                    }
                    //.buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(
                            NSLocalizedString(
                                isPlaying ? "history_pause_timeline" : "history_play_timeline",
                                comment: "Play/pause timeline playback"
                            )
                        )
                    )
                }
            }
            TimelineRangeSlider(
                range: fullRange,
                selection: $selection,
                scrubValue: $scrubValue,
                ticks: ticks,
                externalShowHandle: isPlaying,
                onScrubShown: onScrubShown,
                isPlaying: isPlaying,
                isPlaybackStepping: isPlaybackStepping,
                stopPlayback: stopPlayback,
                startPlayback: startPlayback,
                onScrubBegan: onScrubBegan,
                onScrubEnded: onScrubEnded,
                onSelectionDragBegan: onSelectionDragBegan,
                onSelectionDragEnded: onSelectionDragEnded
            )
            .padding(.horizontal, 8)
            .frame(height: 52)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(fullRange.lowerBound))
                    Text(formattedTime(fullRange.lowerBound))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedDate(fullRange.upperBound))
                    Text(formattedTime(fullRange.upperBound))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .background(tintedOverlayBackground(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    private func formattedDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineDayFormatter.string(from: date)
    }

    private func formattedDateTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineDateFormatter.string(from: date)
    }

    private func formattedTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineTimeFormatter.string(from: date)
    }

    @ViewBuilder
    /// Creates the translucent background for the overlay with material effects.
    ///
    /// - Simulator and pre-iOS 26: ultra-thin material with rounded corners and a subtle stroke.
    /// - iOS 26+: glass morphism effect with a light stroke for separation.
    private func tintedOverlayBackground(cornerRadius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
                /*.overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )*/
        } else {
            Color.clear
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                /*.overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )*/
        }
    }
}

