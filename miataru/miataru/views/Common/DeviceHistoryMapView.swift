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
    @State private var loadError: String? = nil
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
        .overlay {
            if !isLoading, history.isEmpty, loadError == nil {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("history_no_data", comment: "No history available placeholder"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let loadError {
                VStack(spacing: 6) {
                    Text(NSLocalizedString("history_load_failed", comment: "History load failed message"))
                        .font(.footnote)
                        .bold()
                        .multilineTextAlignment(.center)
                    Text(loadError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.85), in: Capsule())
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
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
            debugLog("[DeviceHistoryMapView] Using cached history for device \(device.DeviceID) entries=\(cached.count)")
            await MainActor.run {
                history = cached
                updateRegion()
            }
            return
        }
        guard let url = URL(string: SettingsManager.shared.miataruServerURL) else { return }
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            debugLog("[DeviceHistoryMapView] Fetching history for device \(device.DeviceID)")
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
                debugLog("[DeviceHistoryMapView] Loaded history entries=\(sorted.count) for device \(device.DeviceID)")
            }
        } catch {
            debugLog("[DeviceHistoryMapView] Failed to load history for device \(device.DeviceID): \(error.localizedDescription)")
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
            }
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
