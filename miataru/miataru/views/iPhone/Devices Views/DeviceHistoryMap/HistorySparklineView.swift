/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistorySparklineView.swift
 * miataru
 */

import SwiftUI

struct HistorySparklineView: View {
    let values: [Double?]
    let currentIndex: Int?
    let valueRange: ClosedRange<Double>?

    var body: some View {
        Canvas { context, size in
            guard !values.isEmpty, size.width > 0, size.height > 0 else { return }

            let range = resolvedRange
            var path = Path()
            var hasActiveSegment = false

            drawGuideLines(in: &context, size: size)

            for (index, value) in values.enumerated() {
                guard let value, value.isFinite else {
                    hasActiveSegment = false
                    continue
                }

                let point = point(for: value, at: index, range: range, size: size)
                if hasActiveSegment {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    hasActiveSegment = true
                }
            }

            context.stroke(
                path,
                with: .color(.secondary.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )

            drawIsolatedPoints(in: &context, range: range, size: size)
            drawPlayhead(in: &context, size: size)
        }
    }

    private var resolvedRange: ClosedRange<Double> {
        if let valueRange,
           valueRange.lowerBound.isFinite,
           valueRange.upperBound.isFinite {
            return valueRange
        }

        let validValues = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard let minimum = validValues.min(),
              let maximum = validValues.max() else {
            return 0...1
        }
        return minimum...maximum
    }

    private func point(for value: Double, at index: Int, range: ClosedRange<Double>, size: CGSize) -> CGPoint {
        let x: CGFloat
        if values.count <= 1 {
            x = size.width / 2
        } else {
            x = CGFloat(index) / CGFloat(values.count - 1) * size.width
        }

        let y: CGFloat
        let topInset: CGFloat = 2
        let bottomInset: CGFloat = 2
        let chartHeight = max(size.height - topInset - bottomInset, 1)
        if range.upperBound > range.lowerBound {
            let normalized = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            y = topInset + (1 - CGFloat(normalized)) * chartHeight
        } else {
            y = size.height / 2
        }

        return CGPoint(x: x, y: y)
    }

    private func drawGuideLines(in context: inout GraphicsContext, size: CGSize) {
        let upperY: CGFloat = 2
        let middleY = size.height / 2
        let lowerY = size.height - 2

        var path = Path()
        path.move(to: CGPoint(x: 0, y: upperY))
        path.addLine(to: CGPoint(x: size.width, y: upperY))
        path.move(to: CGPoint(x: 0, y: middleY))
        path.addLine(to: CGPoint(x: size.width, y: middleY))
        path.move(to: CGPoint(x: 0, y: lowerY))
        path.addLine(to: CGPoint(x: size.width, y: lowerY))

        context.stroke(path, with: .color(.secondary.opacity(0.13)), lineWidth: 0.75)
    }

    private func drawIsolatedPoints(in context: inout GraphicsContext, range: ClosedRange<Double>, size: CGSize) {
        for (index, value) in values.enumerated() {
            guard let value, value.isFinite,
                  !hasValidNeighbor(around: index) else {
                continue
            }

            let point = point(for: value, at: index, range: range, size: size)
            let diameter: CGFloat = 2.4
            let rect = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.9)))
        }
    }

    private func hasValidNeighbor(around index: Int) -> Bool {
        let previousIndex = index - 1
        let nextIndex = index + 1
        let previousIsValid = values.indices.contains(previousIndex) && (values[previousIndex]?.isFinite == true)
        let nextIsValid = values.indices.contains(nextIndex) && (values[nextIndex]?.isFinite == true)
        return previousIsValid || nextIsValid
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
