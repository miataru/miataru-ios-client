/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryMetricsPanel.swift
 * miataru
 */

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct HistoryMetricsPanel: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    let fullRange: ClosedRange<Double>
    @Binding var selection: ClosedRange<Double>
    @Binding var scrubValue: Double
    let ticks: [Double]
    let selectedCount: Int
    let totalCount: Int
    let analysis: HistoryAnalysis?
    let currentBucketIndex: Int?
    let currentSpeedKmh: Double?
    let currentAltitudeMeters: Double?
    let isPlaying: Bool
    let playbackSpeed: Double
    let onPlayPause: () -> Void
    let onLongPressSpeedUp: () -> Void
    let onScrubShown: () -> Void
    let stopPlayback: () -> Void
    let startPlayback: () -> Void
    let isPlaybackStepping: Bool
    let onScrubBegan: () -> Void
    let onScrubEnded: () -> Void
    let onSelectionDragBegan: () -> Void
    let onSelectionDragEnded: () -> Void
    let onHidePanel: () -> Void

    private let hideThreshold: CGFloat = 90
    private let predictedHideThreshold: CGFloat = 140

    var body: some View {
        HistoryPanelContainer {
            panelContent
        }
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHandle

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(formattedDateTime(selection.lowerBound)) • \(formattedDateTime(selection.upperBound))")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(String(format: NSLocalizedString("history_timeline_visible_count", comment: "Visible items count out of total"), selectedCount, totalCount))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    playbackButton
                }

                if let metricSummaryText {
                    Text(metricSummaryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                VStack(alignment: .leading, spacing: 6) {
                    metricRow(
                        label: NSLocalizedString("history_metric_speed", comment: "Compact speed metric label"),
                        value: formatSpeed(currentSpeedKmh),
                        graph: HistoryHistogramView(
                            values: analysis?.speedValues ?? [],
                            currentIndex: currentBucketIndex,
                            valueRange: speedValueRange
                        )
                        .accessibilityLabel(Text(NSLocalizedString("history_speed_graph_label", comment: "Accessibility label for the speed graph")))
                        .accessibilityValue(Text(speedGraphAccessibilityValue))
                    )

                    metricRow(
                        label: NSLocalizedString("history_metric_altitude", comment: "Compact altitude metric label"),
                        value: formatAltitude(currentAltitudeMeters),
                        graph: HistorySparklineView(
                            values: analysis?.altitudeValues ?? [],
                            currentIndex: currentBucketIndex,
                            valueRange: altitudeValueRange
                        )
                        .accessibilityLabel(Text(NSLocalizedString("history_altitude_graph_label", comment: "Accessibility label for the altitude graph")))
                        .accessibilityValue(Text(altitudeGraphAccessibilityValue))
                    )
                }
                .opacity(hasAnyMetrics ? 1 : 0.48)
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
            .frame(height: 46)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedDate(fullRange.lowerBound))
                    Text(formattedTime(fullRange.lowerBound))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedDate(fullRange.upperBound))
                    Text(formattedTime(fullRange.upperBound))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        }
        .padding(12)
    }

    private var panelHandle: some View {
        ZStack {
            Color.clear
            Capsule()
                .frame(width: 38, height: 5)
                .foregroundStyle(.secondary.opacity(0.35))
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(panelDismissGesture)
            .onTapGesture(perform: onHidePanel)
            .accessibilityLabel(Text(NSLocalizedString("history_panel_hide_accessibility", comment: "Accessibility label to hide the history panel")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text(NSLocalizedString("history_panel_hide_accessibility", comment: "Accessibility label to hide the history panel"))) {
                onHidePanel()
            }
    }

    private var panelDismissGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onEnded { value in
                if shouldHidePanel(for: value) {
                    onHidePanel()
                }
            }
    }

    private func isDownwardDismissDrag(_ value: DragGesture.Value) -> Bool {
        let verticalDistance = value.translation.height
        let horizontalDistance = abs(value.translation.width)
        return verticalDistance > 0 && verticalDistance > horizontalDistance * 0.75
    }

    private func shouldHidePanel(for value: DragGesture.Value) -> Bool {
        let verticalDismissDrag = isDownwardDismissDrag(value) || isDownwardDismissPrediction(value)
        return verticalDismissDrag &&
            (value.translation.height > hideThreshold ||
             value.predictedEndTranslation.height > predictedHideThreshold)
    }

    private func isDownwardDismissPrediction(_ value: DragGesture.Value) -> Bool {
        let verticalDistance = value.predictedEndTranslation.height
        let horizontalDistance = abs(value.predictedEndTranslation.width)
        return verticalDistance > 0 && verticalDistance > horizontalDistance * 0.75
    }

    @ViewBuilder
    private var playbackButton: some View {
        ZStack {
            Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.title)
                .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .padding(10)
                .scaleEffect(isPlaying ? 1.05 : 1.0)
                .animation(
                    animationsAllowed
                        ? (isPlaying
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default)
                        : nil,
                    value: isPlaying
                )

            if isPlaying && playbackSpeed > 1.0 {
                Text(String(format: "%.0fx", playbackSpeed))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.blue, in: Capsule())
                    .offset(x: 14, y: -14)
                    .transition(animationsAllowed ? .scale.combined(with: .opacity) : .identity)
                    .animation(animationsAllowed ? .easeInOut(duration: 0.2) : nil, value: playbackSpeed)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlayPause)
        .onLongPressGesture(minimumDuration: 0.4) {
            triggerMediumHaptic()
            onLongPressSpeedUp()
        }
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(in: .capsule)
            } else {
                Color.clear
            }
        }
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .accessibilityLabel(
            Text(
                NSLocalizedString(
                    isPlaying ? "history_pause_timeline" : "history_play_timeline",
                    comment: "Play/pause timeline playback"
                )
            )
        )
        .accessibilityHint(
            Text(
                NSLocalizedString(
                    "history_playback_speed_hint",
                    comment: "Long press to change playback speed"
                )
            )
        )
    }

    private func metricRow<Graph: View>(label: String, value: String, graph: Graph) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            graph
                .frame(height: 38)
                .frame(maxWidth: .infinity)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var metricSummaryText: String? {
        guard let analysis else { return nil }
        var segments: [String] = []

        if let distance = analysis.totalDistanceMeters {
            segments.append("\(NSLocalizedString("history_metric_distance", comment: "Compact distance metric label")) \(formatDistance(distance))")
        }

        if let maxSpeed = analysis.maxSpeedKmh {
            segments.append("\(NSLocalizedString("history_metric_max_speed", comment: "Compact maximum speed metric label")) \(formatSpeed(maxSpeed))")
        }

        if let altitudeRangeText = formatAltitudeRange(minimum: analysis.minAltitudeMeters, maximum: analysis.maxAltitudeMeters) {
            segments.append(altitudeRangeText)
        }

        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    private var hasAnyMetrics: Bool {
        guard let analysis else { return false }
        return analysis.validSpeedBucketCount > 0 || analysis.validAltitudeBucketCount > 0
    }

    private var speedValueRange: ClosedRange<Double>? {
        guard let speedValues = analysis?.speedValues else { return nil }
        let sortedValues = speedValues.compactMap { value -> Double? in
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        .sorted()

        guard let maximum = sortedValues.last else { return nil }

        let displayMaximum: Double
        if sortedValues.count < 12 {
            displayMaximum = maximum
        } else {
            let percentileIndex = min(
                sortedValues.count - 1,
                max(0, Int((Double(sortedValues.count - 1) * 0.85).rounded(.up)))
            )
            let percentileMaximum = sortedValues[percentileIndex]
            let paddedPercentileMaximum = percentileMaximum * 1.35
            displayMaximum = maximum > paddedPercentileMaximum * 1.35 ? paddedPercentileMaximum : maximum
        }

        return 0...max(displayMaximum, 12)
    }

    private var altitudeValueRange: ClosedRange<Double>? {
        guard let minimum = analysis?.minAltitudeMeters,
              let maximum = analysis?.maxAltitudeMeters,
              minimum.isFinite,
              maximum.isFinite else {
            return nil
        }
        let span = max(maximum - minimum, 0)
        let padding = max(span * 0.12, 5)
        return (minimum - padding)...(maximum + padding)
    }

    private var speedGraphAccessibilityValue: String {
        guard let maxSpeed = analysis?.maxSpeedKmh else {
            return NSLocalizedString("history_graph_no_data", comment: "Accessibility value when a history graph has no data")
        }
        return String(
            format: NSLocalizedString("history_speed_graph_accessibility_value", comment: "Accessibility value for speed graph maximum"),
            formatSpeed(maxSpeed)
        )
    }

    private var altitudeGraphAccessibilityValue: String {
        guard let range = formatAltitudeRange(minimum: analysis?.minAltitudeMeters, maximum: analysis?.maxAltitudeMeters) else {
            return NSLocalizedString("history_graph_no_data", comment: "Accessibility value when a history graph has no data")
        }
        return range
    }

    private func formatSpeed(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return "\(localizedNumber(value, maximumFractionDigits: 0)) km/h"
    }

    private func formatAltitude(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return "\(localizedNumber(value, maximumFractionDigits: 0)) m"
    }

    private func formatDistance(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        if value >= 1_000 {
            return "\(localizedNumber(value / 1_000, maximumFractionDigits: 1)) km"
        }
        return "\(localizedNumber(value, maximumFractionDigits: 0)) m"
    }

    private func formatAltitudeRange(minimum: Double?, maximum: Double?) -> String? {
        guard let minimum, let maximum, minimum.isFinite, maximum.isFinite else { return nil }
        if abs(maximum - minimum) < 0.5 {
            return formatAltitude(minimum)
        }
        return "\(localizedNumber(minimum, maximumFractionDigits: 0))-\(localizedNumber(maximum, maximumFractionDigits: 0)) m"
    }

    private func localizedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
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

    private func triggerMediumHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

private struct HistoryPanelContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(historyPanelBackground(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private func historyPanelBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
        } else {
            Color.clear
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
