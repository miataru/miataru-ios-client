/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryHistogramView.swift
 * miataru
 */

import SwiftUI

struct HistoryHistogramView: View {
    let values: [Double?]
    let currentIndex: Int?
    let valueRange: ClosedRange<Double>?

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty, size.width > 0, size.height > 0 else { return }

            let displayValues = renderedValues(for: size)
            guard !displayValues.isEmpty else {
                drawPlayhead(in: &context, size: size)
                return
            }

            let range = resolvedRange
            guard range.upperBound > range.lowerBound else {
                drawPlayhead(in: &context, size: size)
                return
            }

            drawGuideLines(in: &context, size: size)

            let count = displayValues.count
            let slotWidth = size.width / CGFloat(max(count, 1))
            let barWidth = min(max(slotWidth * 0.72, 1.5), 5)
            let topInset: CGFloat = 2
            let bottomInset: CGFloat = 2
            let chartHeight = max(size.height - topInset - bottomInset, 1)
            let baseline = size.height - bottomInset

            for (index, value) in displayValues.enumerated() {
                guard let value, value.isFinite else { continue }
                let linearNormalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                let normalized = sqrt(min(max(linearNormalized, 0), 1))
                guard normalized > 0 else { continue }

                let barHeight = max(1, CGFloat(normalized) * chartHeight)
                let x = slotWidth * CGFloat(index) + (slotWidth - barWidth) / 2
                let rect = CGRect(x: x, y: baseline - barHeight, width: barWidth, height: barHeight)
                let isClipped = value > range.upperBound
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(barWidth / 2, 2)),
                    with: .color(isClipped ? Color.accentColor.opacity(0.95) : Color.accentColor.opacity(0.82))
                )

                if isClipped {
                    var cap = Path()
                    cap.move(to: CGPoint(x: rect.minX, y: topInset))
                    cap.addLine(to: CGPoint(x: rect.maxX, y: topInset))
                    context.stroke(cap, with: .color(.primary.opacity(0.7)), lineWidth: 1)
                }
            }

            drawPlayhead(in: &context, size: size)
        }
    }

    private var resolvedRange: ClosedRange<Double> {
        if let valueRange,
           valueRange.lowerBound.isFinite,
           valueRange.upperBound.isFinite,
           valueRange.upperBound > valueRange.lowerBound {
            return valueRange
        }

        let validValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        let maximum = max(validValues.max() ?? 1, 1)
        return 0...maximum
    }

    private func renderedValues(for size: CGSize) -> [Double?] {
        guard !values.isEmpty else { return [] }

        let targetSlotCount = max(80, Int(size.width.rounded(.down)))
        guard values.count > targetSlotCount else { return values }

        return (0..<targetSlotCount).map { slotIndex in
            let lowerBound = Int((Double(slotIndex) / Double(targetSlotCount)) * Double(values.count))
            let upperBound = Int((Double(slotIndex + 1) / Double(targetSlotCount)) * Double(values.count))
            let safeUpperBound = min(max(upperBound, lowerBound + 1), values.count)
            let validValues = values[lowerBound..<safeUpperBound].compactMap { value -> Double? in
                guard let value, value.isFinite else { return nil }
                return value
            }

            guard !validValues.isEmpty else { return nil }
            return validValues.max()
        }
    }

    private func drawGuideLines(in context: inout GraphicsContext, size: CGSize) {
        let baselineY = size.height - 2
        let middleY = size.height / 2

        var path = Path()
        path.move(to: CGPoint(x: 0, y: middleY))
        path.addLine(to: CGPoint(x: size.width, y: middleY))
        path.move(to: CGPoint(x: 0, y: baselineY))
        path.addLine(to: CGPoint(x: size.width, y: baselineY))

        context.stroke(path, with: .color(.secondary.opacity(0.16)), lineWidth: 0.75)
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        guard let currentIndex,
              values.indices.contains(currentIndex),
              size.width > 0 else { return }

        let x: CGFloat
        if values.count <= 1 {
            x = size.width / 2
        } else {
            x = CGFloat(currentIndex) / CGFloat(values.count - 1) * size.width
        }

        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.primary.opacity(0.55)), lineWidth: 1)
    }
}
