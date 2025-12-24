/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * TimelineRangeSlider.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-12-24.
 */

import SwiftUI

struct TimelineRangeSlider: View {
    let range: ClosedRange<Double>
    @Binding var selection: ClosedRange<Double>
    @Binding var scrubValue: Double
    let ticks: [Double]
    let externalShowHandle: Bool
    let onScrubShown: () -> Void
    let isPlaying: Bool
    let isPlaybackStepping: Bool
    let stopPlayback: () -> Void
    let startPlayback: () -> Void
    let onScrubBegan: () -> Void
    let onScrubEnded: () -> Void
    let onSelectionDragBegan: () -> Void
    let onSelectionDragEnded: () -> Void

    @State private var lowerStart: Double?
    @State private var upperStart: Double?
    @State private var scrubStart: Double?
    @State private var selectionDragStart: ClosedRange<Double>?
    @State private var showScrubHandle = false
    @State private var isHandleDragging = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackHeight: CGFloat = 8
            let rangeSpan = range.upperBound - range.lowerBound
            let minimumGap = rangeSpan > 0 ? min(max(rangeSpan * 0.02, 0.001), rangeSpan) : 0
            let lowerX = xPosition(for: selection.lowerBound, width: width)
            let upperX = xPosition(for: selection.upperBound, width: width)
            let scrubX = xPosition(for: scrubValue, width: width)
            let selectionSpan = selection.upperBound - selection.lowerBound
            let trackCenterY = geometry.size.height / 2
            let selectionHeight: CGFloat = max(2, trackHeight * 0.35)
            let gradient = LinearGradient(
                colors: gradientColors,
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack(alignment: .leading) {
                // Base gradient track showing oldest→newest color ramp
                Capsule()
                    .fill(gradient)
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Selection overlay: thin solid line centered on the track (adaptive color)
                Capsule()
                    .fill(Color.primary)
                    .frame(width: max(upperX - lowerX, 2), height: selectionHeight)
                    .offset(x: lowerX)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .overlay(
                        // Subtle stroke to outline the selection
                        Capsule()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            .frame(width: max(upperX - lowerX, 2), height: selectionHeight + 2)
                            .offset(x: lowerX)
                    )
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                showScrubHandle = true
                                let tapX = min(max(0, value.location.x), width)
                                let tappedValue = valueForPosition(tapX, width: width)
                                scrubValue = clamp(tappedValue, to: range)
                                onScrubShown()
                                if isPlaying && !isPlaybackStepping {
                                    startPlayback()
                                }
                            }
                    )
                    .contentShape(Rectangle())

                ForEach(ticks, id: \.self) { tick in
                    let x = xPosition(for: tick, width: width)
                    Rectangle()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 1, height: 22)
                        .offset(x: x - 0.5, y: 5)
                        .allowsHitTesting(false)
                }

                if showScrubHandle || externalShowHandle {
                    scrubHandle(
                        x: scrubX,
                        trackCenterY: trackCenterY,
                        timestamp: scrubValue
                    )
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scrubStart == nil {
                                        scrubStart = scrubValue
                                        onScrubBegan()
                                    }
                                    let base = xPosition(for: scrubStart ?? scrubValue, width: width)
                                    let candidate = valueForPosition(base + value.translation.width, width: width)
                                    let clamped = clamp(candidate, to: selection)
                                    scrubValue = clamped
                                    if isPlaying && !isPlaybackStepping {
                                        startPlayback()
                                    }
                                    onScrubShown()
                                }
                                .onEnded { _ in
                                    scrubStart = nil
                                    onScrubEnded()
                                }
                        )
                }

                rangeHandle(x: lowerX, systemName: "arrowtriangle.backward.fill")
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if lowerStart == nil {
                                    lowerStart = selection.lowerBound
                                    isHandleDragging = true
                                    onSelectionDragBegan()
                                }
                                guard minimumGap > 0 else { return }
                                let baseX = xPosition(for: lowerStart ?? selection.lowerBound, width: width)
                                let candidate = valueForPosition(baseX + value.translation.width, width: width)
                                let clamped = min(clamp(candidate, to: range), selection.upperBound - minimumGap)
                                selection = clamped...selection.upperBound
                                if scrubValue < clamped {
                                    scrubValue = clamped
                                }
                            }
                            .onEnded { _ in
                                lowerStart = nil
                                isHandleDragging = false
                                onSelectionDragEnded()
                            }
                    )

                rangeHandle(x: upperX, systemName: "arrowtriangle.forward.fill")
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if upperStart == nil {
                                    upperStart = selection.upperBound
                                    isHandleDragging = true
                                    onSelectionDragBegan()
                                }
                                guard minimumGap > 0 else { return }
                                let baseX = xPosition(for: upperStart ?? selection.upperBound, width: width)
                                let candidate = valueForPosition(baseX + value.translation.width, width: width)
                                let clamped = max(clamp(candidate, to: range), selection.lowerBound + minimumGap)
                                selection = selection.lowerBound...clamped
                                if scrubValue > clamped {
                                    scrubValue = clamped
                                }
                            }
                            .onEnded { _ in
                                upperStart = nil
                                isHandleDragging = false
                                onSelectionDragEnded()
                            }
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if isHandleDragging || scrubStart != nil { return }
                        if selectionDragStart == nil {
                            selectionDragStart = selection
                            onSelectionDragBegan()
                        }
                        guard let startRange = selectionDragStart else { return }
                        let deltaValue = Double(value.translation.width / width) * rangeSpan
                        let candidateLower = startRange.lowerBound + deltaValue
                        let clampedLower = min(max(range.lowerBound, candidateLower), range.upperBound - selectionSpan)
                        let newSelection = clampedLower...(clampedLower + selectionSpan)
                        if newSelection == selection { return }
                        selection = newSelection
                        if scrubValue < newSelection.lowerBound {
                            scrubValue = newSelection.lowerBound
                        } else if scrubValue > newSelection.upperBound {
                            scrubValue = newSelection.upperBound
                        }
                        showScrubHandle = true
                        if isPlaying && !isPlaybackStepping {
                            startPlayback()
                        }
                        onScrubShown()
                    }
                    .onEnded { _ in
                        if selectionDragStart != nil {
                            onSelectionDragEnded()
                        }
                        selectionDragStart = nil
                    }
            )
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(ratio) * width
    }

    private var gradientColors: [Color] {
        stride(from: 0.0, through: 1.0, by: 0.2).map { ratio in
            iPhone_DeviceHistoryMapView.historyColor(for: ratio)
        }
    }

    private func valueForPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let clampedX = min(max(0, x), width)
        let ratio = Double(clampedX / width)
        return range.lowerBound + (range.upperBound - range.lowerBound) * ratio
    }

    private func scrubHandle(x: CGFloat, trackCenterY: CGFloat, timestamp: Double) -> some View {
        let dateText = formattedDate(timestamp)
        let timeText = formattedTime(timestamp)
        return ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .shadow(radius: 2)
                .position(x: x, y: trackCenterY + 1)
            VStack(spacing: 2) {
                Text(dateText)
                Text(timeText)
            }
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .position(x: x, y: trackCenterY - 24)
        }
        .accessibilityLabel(Text(NSLocalizedString("history_timeline_scrub_handle", comment: "Scrub handle for history timeline")))
    }

    private func formattedTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineTimeFormatter.string(from: date)
    }

    private func formattedDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineDayFormatter.string(from: date)
    }

    private func rangeHandle(x: CGFloat, systemName: String) -> some View {
        let visualHandleSize: CGFloat = 26
        let hitTargetSize: CGFloat = 44 // Increase touch target for easier dragging

        return Capsule()
            .fill(.thinMaterial)
            .frame(width: visualHandleSize, height: visualHandleSize)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
            )
            .shadow(radius: 2)
            .frame(width: hitTargetSize, height: hitTargetSize)
            .contentShape(Rectangle())
            .offset(x: x - (hitTargetSize / 2))
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

