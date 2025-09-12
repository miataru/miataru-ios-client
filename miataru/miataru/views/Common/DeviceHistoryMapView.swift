/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceHistoryMapView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MapKit
import MiataruAPIClient

struct DeviceHistoryMapView: View {
    let device: KnownDevice
    @State private var history: [MiataruLocationData] = []
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
    )
    @State private var isLoading = false
    @ObservedObject private var cache = DeviceHistoryCacheStore.shared

    var body: some View {
        Map(position: $cameraPosition) {
            ForEach(history, id: \.Timestamp) { entry in
                let coord = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)
                Annotation("", coordinate: coord) {
                    Circle()
                        .fill(color(for: entry))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView()
                    .padding()
            }
        }
        .navigationTitle(device.DeviceName)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        if let cached = cache.getHistory(for: device.DeviceID) {
            history = cached
            updateRegion()
            return
        }
        guard let url = URL(string: SettingsManager.shared.miataruServerURL) else { return }
        isLoading = true
        do {
            let data = try await MiataruAPIClient.getLocationHistory(
                serverURL: url,
                forDeviceID: device.DeviceID,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                amount: 1000
            )
            let sorted = data.sorted { $0.TimestampDate < $1.TimestampDate }
            await MainActor.run {
                history = sorted
                cache.setHistory(sorted, for: device.DeviceID)
                updateRegion()
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func updateRegion() {
        guard !history.isEmpty else { return }
        var minLat = history.first!.Latitude
        var maxLat = history.first!.Latitude
        var minLon = history.first!.Longitude
        var maxLon = history.first!.Longitude
        for h in history {
            minLat = min(minLat, h.Latitude)
            maxLat = max(maxLat, h.Latitude)
            minLon = min(minLon, h.Longitude)
            maxLon = max(maxLon, h.Longitude)
        }
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.4)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func color(for entry: MiataruLocationData) -> Color {
        guard let first = history.first?.TimestampDate, let last = history.last?.TimestampDate else { return .blue }
        let total = last.timeIntervalSince(first)
        let diff = entry.TimestampDate.timeIntervalSince(first)
        let ratio = total > 0 ? diff / total : 0
        // Older points blue, newer red
        return Color(hue: 0.6 - 0.6 * ratio, saturation: 0.9, brightness: 0.9)
    }
}
