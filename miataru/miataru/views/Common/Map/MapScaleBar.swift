/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MapScaleBar.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MapKit

struct MapScaleBar: View {
    let region: MKCoordinateRegion
    let width: CGFloat

    @StateObject private var viewModel = MapScaleBarViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            Text(viewModel.label.isEmpty ? defaultLabel : viewModel.label)
                .font(.caption2)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle()
                .frame(width: width, height: 2)
                .foregroundColor(.primary)
                .cornerRadius(4)
        }
        .frame(width: width)
        .padding(4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onAppear {
            viewModel.schedule(region: region, width: width)
        }
        .onChange(of: regionToken) { _, _ in
            viewModel.schedule(region: region, width: width)
        }
        .onChange(of: width) { _, newValue in
            viewModel.schedule(region: region, width: newValue)
        }
        .onChange(of: colorScheme) { _, _ in
            // Force recalculation to ensure colors and label adapt on theme changes
            viewModel.schedule(region: region, width: width)
        }
    }

    private var defaultLabel: String {
        // Localized: Placeholder text while computing scale
        NSLocalizedString("scalebar_computing", comment: "Scale bar: computing distance placeholder")
    }

    private struct RegionToken: Equatable {
        let latBucket: Int
        let lonBucket: Int
        let latDeltaBucket: Int
        let lonDeltaBucket: Int
    }

    private var regionToken: RegionToken {
        let latBucket = Int((region.center.latitude * 1000.0).rounded())
        let lonBucket = Int((region.center.longitude * 1000.0).rounded())
        let latDeltaBucket = Int((region.span.latitudeDelta * 1000.0).rounded())
        let lonDeltaBucket = Int((region.span.longitudeDelta * 1000.0).rounded())
        return RegionToken(latBucket: latBucket, lonBucket: lonBucket, latDeltaBucket: latDeltaBucket, lonDeltaBucket: lonDeltaBucket)
    }
}

#Preview {
    let center = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405)
    // 10 verschiedene Zoom-Levels von sehr nah bis weit entfernt
    let latitudeDeltas: [CLLocationDegrees] = [0.0002, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2]
    VStack(alignment: .leading, spacing: 16) {
        ForEach(latitudeDeltas, id: \.self) { delta in
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom (latitudeDelta): \(String(format: "%.4f", delta))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                MapScaleBar(
                    region: MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
                    ),
                    width: 100
                )
            }
        }
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
