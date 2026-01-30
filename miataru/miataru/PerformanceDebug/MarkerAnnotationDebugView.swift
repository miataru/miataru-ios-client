/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MarkerAnnotationDebugView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2025-09-05.
 */

import SwiftUI
import MapKit
import CoreLocation
import Combine

struct GhostAnnotationView: View {
    var name: String
    var iconName: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(Color.primary.opacity(0.9))
                .shadow(radius: 4)
            ZStack {
                ForEach([-1, 0, 1], id: \.self) { x in
                    ForEach([-1, 0, 1], id: \.self) { y in
                        if x != 0 || y != 0 {
                            Text(name)
                                .font(.caption2)
                                .foregroundColor(Color(UIColor.systemBackground).opacity(0.8))
                                .offset(x: CGFloat(x), y: CGFloat(y))
                        }
                    }
                }
                Text(name)
                    .font(.caption2)
                    .foregroundColor(Color(UIColor.label).opacity(0.8))
            }
        }
    }
}

struct MarkerAnnotationDebugView: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    var deviceName: String = NSLocalizedString("debug_marker_device_name", comment: "Sample device name used in the marker debug view.")
    var deviceColor: Color = .red
    var transportIconName: String = "car"
    var markerHeight: CGFloat = 48
    var pulsing: Bool = true

    // MARK: - Simple animated map demo state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050), // Berlin
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    @State private var baseA = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
    @State private var baseB = CLLocationCoordinate2D(latitude: 52.5225, longitude: 13.41)
    @State private var coordA = CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050)
    @State private var coordB = CLLocationCoordinate2D(latitude: 52.5225, longitude: 13.41)
    @State private var accuracyA: Double = 20
    @State private var accuracyB: Double = 35
    @State private var tick: Int = 0
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var rotatingTransportIndex: Int = 0 // 0: walk, 1: car, 2: tram

    private func currentTransportSymbol() -> String {
        switch rotatingTransportIndex % 3 {
        case 0: return "figure.walk"
        case 1: return "car"
        default: return "tram"
        }
    }

    private func updateAnimatedCoordinates() {
        tick += 1
        let t = Double(tick)
        // Small circular motion (~10-20m) around base positions
        let dLatA = (cos(t / 40.0) * 0.00012)
        let dLonA = (sin(t / 50.0) * 0.00018)
        let dLatB = (sin(t / 35.0) * 0.00010)
        let dLonB = (cos(t / 45.0) * 0.00014)
        coordA = CLLocationCoordinate2D(latitude: baseA.latitude + dLatA, longitude: baseA.longitude + dLonA)
        coordB = CLLocationCoordinate2D(latitude: baseB.latitude + dLatB, longitude: baseB.longitude + dLonB)
        // Subtle accuracy breathing
        accuracyA = 15 + 10 * (1 + sin(t / 30.0))
        accuracyB = 25 + 12 * (1 + cos(t / 28.0))
        // Rotate transport symbol slowly
        if tick % 90 == 0 { rotatingTransportIndex = (rotatingTransportIndex + 1) % 3 }
    }

    var body: some View {
        VStack(spacing: 18) {
            // MARK: - Map rendering demo (iOS 17+)
            if #available(iOS 17.0, *) {
                Map(position: $cameraPosition) {
                    // Accuracy circles first
                    MapCircle(center: coordA, radius: accuracyA)
                        .foregroundStyle(deviceColor.opacity(0.18))
                    MapCircle(center: coordB, radius: accuracyB)
                        .foregroundStyle(Color.blue.opacity(0.18))

                    // First marker (Device A)
                    let idA = deviceName
                    Annotation("", coordinate: coordA, anchor: .bottom) {
                        ZStack {
                            // Pulsing behind
                            if pulsing {
                                let circleDiameter = markerHeight * 0.65
                                let pulsingSize = circleDiameter * 1.5
                                let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                                PulsingAccuracyCircle(pulsingColor: deviceColor, size: pulsingSize)
                                    .offset(y: pulsingOffset)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            VStack(spacing: 0) {
                                MiataruMapMarker(color: deviceColor, iconName: currentTransportSymbol(), height: markerHeight)
                                    .shadow(radius: 2)
                                // Label with outlined readability
                                ZStack {
                                    ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                                        ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                                            if x != 0 || y != 0 {
                                                Text(idA)
                                                    .font(.callout)
                                                    .foregroundColor(Color(UIColor.systemBackground))
                                                    .padding(.top, 2)
                                                    .offset(x: CGFloat(x), y: CGFloat(y))
                                            }
                                        }
                                    }
                                    Text(idA)
                                        .font(.callout)
                                        .foregroundColor(Color(UIColor.label))
                                        .padding(.top, 2)
                                }
                            }
                            Rectangle()
                                .foregroundColor(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 80, height: 120)
                                .offset(y: 12)
                                .zIndex(1)
                        }
                        .offset(y: 35)
                    }

                    // Second marker (Device B)
                    let idB = NSLocalizedString("debug_marker_device_alt_name", comment: "Alternate sample device name used in the marker debug view.")
                    Annotation("", coordinate: coordB, anchor: .bottom) {
                        ZStack {
                            // Pulsing behind
                            if pulsing {
                                let circleDiameter = markerHeight * 0.65
                                let pulsingSize = circleDiameter * 1.5
                                let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                                PulsingAccuracyCircle(pulsingColor: .blue, size: pulsingSize)
                                    .offset(y: pulsingOffset)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            VStack(spacing: 0) {
                                MiataruMapMarker(color: .blue, iconName: currentTransportSymbol(), height: markerHeight)
                                    .shadow(radius: 2)
                                ZStack {
                                    ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                                        ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                                            if x != 0 || y != 0 {
                                                Text(idB)
                                                    .font(.callout)
                                                    .foregroundColor(Color(UIColor.systemBackground))
                                                    .padding(.top, 2)
                                                    .offset(x: CGFloat(x), y: CGFloat(y))
                                            }
                                        }
                                    }
                                    Text(idB)
                                        .font(.callout)
                                        .foregroundColor(Color(UIColor.label))
                                        .padding(.top, 2)
                                }
                            }
                            Rectangle()
                                .foregroundColor(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 80, height: 120)
                                .offset(y: 12)
                                .zIndex(1)
                        }
                        .offset(y: 35)
                    }

                    // Ghost annotation near Device B to mimic progress
                    let ghost = CLLocationCoordinate2D(
                        latitude: (coordA.latitude * 0.6 + coordB.latitude * 0.4),
                        longitude: (coordA.longitude * 0.6 + coordB.longitude * 0.4)
                    )
                    Annotation("", coordinate: ghost) {
                        GhostAnnotationView(name: idB, iconName: currentTransportSymbol())
                    }
                }
                .mapControls {
                    MapCompass(heading: 1, size: 10).mapControlVisibility(.hidden)
                }
                .mapStyle(.standard)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onAppear {
                    // Start lightweight animation timer
                    timerCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
                        .autoconnect()
                        .sink { _ in
                            if animationsAllowed {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    updateAnimatedCoordinates()
                                }
                            } else {
                                updateAnimatedCoordinates()
                            }
                        }
                }
                .onDisappear {
                    timerCancellable?.cancel()
                    timerCancellable = nil
                }
            }

            // MARK: - Standalone markers (without map) for quick tweaking
            GhostAnnotationView(name: deviceName, iconName: transportIconName)
            if pulsing {
                let circleDiameter = markerHeight * 0.65
                let pulsingSize = circleDiameter * 1.5
                let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                PulsingAccuracyCircle(pulsingColor: deviceColor, size: pulsingSize)
                    .offset(y: pulsingOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            MiataruMapMarker(color: deviceColor, iconName: transportIconName, height: markerHeight)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .padding()
    }
}

#Preview("Defaults") {
    MarkerAnnotationDebugView()
}

#Preview("Variants") {
    VStack(spacing: 28) {
        MarkerAnnotationDebugView(
            deviceName: NSLocalizedString("debug_marker_device_name", comment: "Sample device name used in the marker debug view."),
            deviceColor: .blue,
            transportIconName: "figure.walk",
            markerHeight: 40,
            pulsing: true
        )
        MarkerAnnotationDebugView(
            deviceName: NSLocalizedString("debug_marker_device_alt_name", comment: "Alternate sample device name used in the marker debug view."),
            deviceColor: .green,
            transportIconName: "tram",
            markerHeight: 64,
            pulsing: false
        )
    }
    .padding()
}


