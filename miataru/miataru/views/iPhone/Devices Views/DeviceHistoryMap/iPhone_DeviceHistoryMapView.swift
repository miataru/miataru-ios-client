/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_DeviceHistoryMapView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.12.25.
 */

import SwiftUI
import MapKit
import MiataruAPIClient

struct iPhone_DeviceHistoryMapView: View {
    let device: KnownDevice
    @StateObject private var viewModel = DeviceHistoryMapViewModel()
    // Map state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
    )
    // Loading & data
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @ObservedObject private var cache = DeviceHistoryCacheStore.shared
    // Timeline state
    @State private var selectedRange: ClosedRange<Double>? = nil
    @State private var scrubTimestamp: Double? = nil
    // Playback
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var hasUserScrubbed = false
    @State private var isPlaybackStepping = false
    // Debounced tasks to avoid excessive map updates
    @State private var debouncedRegionTask: Task<Void, Never>?
    @State private var debouncedFocusTask: Task<Void, Never>?
    // Interaction flags
    @State private var isScrubbing = false
    @State private var pendingFocusAfterScrub = false
    @State private var isSelectionDragging = false
    private let playbackContextPadding = 50

    private var visibleHistory: [MiataruLocationData] {
        viewModel.visibleHistory(in: selectedRange)
    }

    private var timelineBounds: ClosedRange<Double>? {
        viewModel.timelineBounds()
    }

    private var timelineTicks: [Double] {
        guard let bounds = timelineBounds else { return [] }
        let span = bounds.upperBound - bounds.lowerBound
        let step = max(span / 4, 1)
        var values: [Double] = []
        var current = bounds.lowerBound
        while current < bounds.upperBound {
            values.append(current)
            current += step
        }
        values.append(bounds.upperBound)
        return values
    }

    private var selectedTimelineEntry: MiataruLocationData? {
        guard let scrubTimestamp else { return nil }
        return viewModel.closest(to: scrubTimestamp, in: selectedRange)
    }

    static let timelineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static let timelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static let timelineDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    static func historyColor(for ratio: Double) -> Color {
        let clamped = min(max(ratio, 0), 1)
        // Older points blue, newer red
        return Color(hue: 0.6 - 0.6 * clamped, saturation: 0.9, brightness: 0.9)
    }

    private func playbackAdjustedHistory(baseHistory: [MiataruLocationData], selectedEntry: MiataruLocationData?) -> [MiataruLocationData] {
        guard isPlaying,
              let selectedEntry,
              let index = baseHistory.firstIndex(where: { isSelectedEntry($0, selected: selectedEntry) }) else {
            return baseHistory
        }
        let lowerBound = max(0, index - playbackContextPadding)
        let upperBound = min(baseHistory.count - 1, index + playbackContextPadding)
        return Array(baseHistory[lowerBound...upperBound])
    }

    var body: some View {
        let fullVisibleHistory = visibleHistory
        let selectedEntry = selectedTimelineEntry
        let mapHistory = playbackAdjustedHistory(baseHistory: fullVisibleHistory, selectedEntry: selectedEntry)
        let useDownsampling = !isPlaying && mapHistory.count > 300
        let annotations = useDownsampling
            ? viewModel.downsample(mapHistory, selected: selectedEntry)
            : mapHistory
        let polylineSource = useDownsampling ? annotations : mapHistory
        let polylineSegments = viewModel.polylineSegments(from: polylineSource)

        Map(position: $cameraPosition) {
            ForEach(Array(polylineSegments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment)
                        .stroke(
                            Color.accentColor.opacity(0.55),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                        )
                }
            }

            ForEach(Array(annotations.enumerated()), id: \.offset) { _, entry in
                let coord = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)
                let isSelected = selectedEntry.map { isSelectedEntry(entry, selected: $0) } ?? false
                Annotation("", coordinate: coord, anchor: isSelected ? .bottom : .center) {
                    if isSelected {
                        VStack(spacing: 6) {
                            Text(formattedDateTimeLabel(for: entry))
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                            MiataruMapMarker(color: color(for: entry, within: mapHistory))
                                .shadow(radius: 2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectEntryFromMap(entry)
                        }
                    } else {
                        Circle()
                            .fill(color(for: entry, within: mapHistory))
                            .frame(width: 10, height: 10)
                            .contentShape(Circle())
                            .onTapGesture {
                                selectEntryFromMap(entry)
                            }
                    }
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
            if !isLoading, loadError == nil {
                if viewModel.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("history_no_data", comment: "No history available placeholder"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                } else if fullVisibleHistory.isEmpty {
                    ErrorOverlay(
                        message: NSLocalizedString("history_no_data_in_range", comment: "No history entries inside selected time range"),
                        visible: true
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
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
                    .padding(.horizontal, 24)
                }

                if let bounds = timelineBounds, !viewModel.history.isEmpty {
                    DeviceHistoryTimelineOverlay(
                        fullRange: bounds,
                        selection: Binding(
                            get: { selectedRange ?? bounds },
                            set: { newValue in
                                selectedRange = normalizeRange(newValue)
                            }
                        ),
                        scrubValue: Binding(
                            get: { scrubTimestamp ?? bounds.upperBound },
                            set: { newValue in
                                scrubTimestamp = newValue
                            }
                        ),
                        ticks: timelineTicks,
                        selectedCount: fullVisibleHistory.count,
                        totalCount: viewModel.history.count,
                        isPlaying: isPlaying,
                        onPlayPause: togglePlayback,
                        onScrubShown: { hasUserScrubbed = true },
                        stopPlayback: stopPlayback,
                        startPlayback: startPlayback,
                        isPlaybackStepping: isPlaybackStepping,
                        onScrubBegan: handleScrubBegan,
                        onScrubEnded: handleScrubEnded,
                        onSelectionDragBegan: handleSelectionDragBegan,
                        onSelectionDragEnded: handleSelectionDragEnded
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle(device.DeviceName)
        .toolbar(.hidden, for: .tabBar)
        .task {
            await loadHistory()
        }
        .onDisappear {
            stopPlayback()
            debouncedRegionTask?.cancel()
            debouncedFocusTask?.cancel()
        }
        .onReceive(viewModel.$history) { _ in
            initializeTimelineIfNeeded()
            updateRegion(animated: false)
            stopPlayback()
        }
        .onChange(of: selectedRange) { _, _ in
            clampScrubToRange()
            if isSelectionDragging { return }
            scheduleRegionUpdate(animated: false)
            if isPlaying {
                startPlayback()
            }
        }
        .onChange(of: scrubTimestamp) { _, _ in
            if isPlaybackStepping { return }
            if isPlaying {
                startPlayback()
            } else {
                if isScrubbing {
                    pendingFocusAfterScrub = true
                } else {
                    scheduleFocusOnScrubbedEntry(animated: false)
                }
            }
        }
    }

    private func normalizeRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        if range.lowerBound <= range.upperBound {
            return range
        } else {
            return range.upperBound...range.lowerBound
        }
    }

    private func loadHistory() async {
        // Prefer cached history for snappy resume
        if let cached = cache.getHistory(for: device.DeviceID) {
            debugLog("[DeviceHistoryMapView] Using cached history for device \(device.DeviceID) entries=\(cached.count)")
            await MainActor.run {
                viewModel.setHistory(cached)
                initializeTimelineIfNeeded()
            }
            return
        }
        guard let url = URL(string: SettingsManager.shared.miataruServerURL) else {
            await MainActor.run {
                loadError = NSLocalizedString("server_url_invalid", comment: "The server URL is invalid.")
            }
            return
        }
        let requestingDeviceID = thisDeviceIDManager.shared.deviceID
        let requestID = requestingDeviceID.isEmpty ? nil : requestingDeviceID
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            debugLog("[DeviceHistoryMapView] Fetching history for device \(device.DeviceID)")
            let data = try await MiataruAPIClient.getLocationHistory(
                serverURL: url,
                forDeviceID: device.DeviceID,
                requestingDeviceID: requestID,
                amount: 10000 // because we do not make it configurable by the user we just get 10k entries, which should be good for "all"
            )
            let normalized = normalizeHistoryEntries(from: data)
            let sorted = normalized.sorted { $0.TimestampDate < $1.TimestampDate }
            await MainActor.run {
                viewModel.setHistory(sorted)
                cache.setHistory(sorted, for: device.DeviceID)
                isLoading = false
                debugLog("[DeviceHistoryMapView] Loaded history entries=\(sorted.count) for device \(device.DeviceID)")
                if sorted.isEmpty {
                    loadError = NSLocalizedString("history_no_data", comment: "No history available placeholder")
                }
                initializeTimelineIfNeeded()
                updateRegion(animated: false)
            }
        } catch let apiError as MiataruAPIClient.APIError {
            await MainActor.run {
                isLoading = false
                loadError = mapAPIError(apiError)
                viewModel.setHistory([])
            }
        } catch {
            debugLog("[DeviceHistoryMapView] Failed to load history for device \(device.DeviceID): \(error.localizedDescription)")
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
                viewModel.setHistory([])
            }
        }
    }

    @MainActor
    private func initializeTimelineIfNeeded() {
        guard let bounds = timelineBounds else { return }
        if selectedRange == nil {
            selectedRange = bounds
        }
        if scrubTimestamp == nil {
            scrubTimestamp = bounds.upperBound
        } else if let scrubValue = scrubTimestamp, !bounds.contains(scrubValue) {
            scrubTimestamp = bounds.upperBound
        }
    }

    @MainActor
    private func updateRegion(animated: Bool = true, using entries: [MiataruLocationData]? = nil, useDefaultZoom: Bool = false) {
        let points = entries ?? visibleHistory
        guard let firstPoint = points.first else { return }

        let region: MKCoordinateRegion
        if useDefaultZoom {
            // Use a preset zoom if requested (e.g. when focusing a single point)
            let span = spanForZoomLevel(SettingsManager.shared.mapZoomLevel)
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: firstPoint.Latitude, longitude: firstPoint.Longitude),
                span: span
            )
        } else {
            // Fit all visible points with padding
            var minLat = firstPoint.Latitude
            var maxLat = firstPoint.Latitude
            var minLon = firstPoint.Longitude
            var maxLon = firstPoint.Longitude
            for h in points {
                minLat = min(minLat, h.Latitude)
                maxLat = max(maxLat, h.Latitude)
                minLon = min(minLon, h.Longitude)
                maxLon = max(maxLon, h.Longitude)
            }
            let minDelta = 0.002
            let paddedLat = max(minDelta, (maxLat - minLat) * 1.4)
            let paddedLon = max(minDelta, (maxLon - minLon) * 1.4)
            let latitudeDelta = paddedLat.isFinite ? paddedLat : minDelta
            let longitudeDelta = paddedLon.isFinite ? paddedLon : minDelta
            let span = MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            region = MKCoordinateRegion(center: center, span: span)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(region)
            }
        } else {
            cameraPosition = .region(region)
        }
    }

    private func focusOnScrubbedEntry(animated: Bool = true) {
        guard let scrubTimestamp else { return }
        guard let target = viewModel.closest(to: scrubTimestamp, in: selectedRange) else { return }
        Task { @MainActor in
            updateRegion(animated: animated, using: [target], useDefaultZoom: true)
        }
    }

    private func color(for entry: MiataruLocationData, within entries: [MiataruLocationData]) -> Color {
        guard let first = entries.first?.TimestampDate, let last = entries.last?.TimestampDate else { return .blue }
        let start = first.timeIntervalSince1970
        let end = last.timeIntervalSince1970
        let total = end - start
        let diff = entry.TimestampDate.timeIntervalSince1970 - start
        let ratio = total > 0 ? diff / total : 0
        return Self.historyColor(for: ratio)
    }

    private func formattedDateTimeLabel(for entry: MiataruLocationData) -> String {
        Self.timelineDateFormatter.string(from: entry.TimestampDate)
    }

    private func isSelectedEntry(_ entry: MiataruLocationData, selected: MiataruLocationData) -> Bool {
        return selected.Timestamp == entry.Timestamp &&
            selected.Latitude == entry.Latitude &&
            selected.Longitude == entry.Longitude
    }

    private func selectEntryFromMap(_ entry: MiataruLocationData) {
        scrubTimestamp = entry.TimestampDate.timeIntervalSince1970
        hasUserScrubbed = true
        // onChange(of: scrubTimestamp) handles focusing or playback restart
    }

    private func normalizeHistoryEntries(from entries: [MiataruLocationData]) -> [MiataruLocationData] {
        var uniqueEntries: [MiataruLocationData] = []
        uniqueEntries.reserveCapacity(entries.count)

        var seenKeys = Set<String>()
        var droppedDuplicates = 0
        var droppedInvalid = 0

        for entry in entries {
            guard entry.Latitude.isFinite, entry.Longitude.isFinite else {
                droppedInvalid += 1
                continue
            }

            let key = "\(entry.Timestamp)|\(entry.Latitude)|\(entry.Longitude)"
            if seenKeys.insert(key).inserted {
                uniqueEntries.append(entry)
            } else {
                droppedDuplicates += 1
            }
        }

        if droppedDuplicates > 0 || droppedInvalid > 0 {
            debugLog("[DeviceHistoryMapView] Normalized history for device \(device.DeviceID) dropped duplicates=\(droppedDuplicates) invalid=\(droppedInvalid)")
        }

        return uniqueEntries
    }

    private func mapAPIError(_ error: MiataruAPIClient.APIError) -> String {
        switch error {
        case .invalidURL:
            return NSLocalizedString("server_url_invalid", comment: "The server URL is invalid.")
        case .invalidResponse(_):
            return NSLocalizedString("server_response_invalid", comment: "The server response was invalid.")
        case .encodingError(let err):
            return "\(NSLocalizedString("encoding_error", comment: "Error encoding the request.")) \(err.localizedDescription)"
        case .decodingError(let err):
            return "\(NSLocalizedString("decoding_error", comment: "Error processing the server response.")) \(err.localizedDescription)"
        case .requestFailed(let err):
            return "\(NSLocalizedString("network_error", comment: "Network error. Please check your internet connection.")) \(err.localizedDescription)"
        }
    }

    private func clampScrubToRange() {
        guard let bounds = selectedRange else { return }
        if let scrubTimestamp {
            if !bounds.contains(scrubTimestamp) {
                self.scrubTimestamp = clamp(scrubTimestamp, to: bounds)
                hasUserScrubbed = false
            }
        } else {
            scrubTimestamp = bounds.upperBound
        }
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func scheduleRegionUpdate(animated: Bool, useDefaultZoom: Bool = false, delayMs: UInt64 = 80) {
        debouncedRegionTask?.cancel()
        debouncedRegionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            updateRegion(animated: animated, using: nil, useDefaultZoom: useDefaultZoom)
        }
    }

    private func scheduleFocusOnScrubbedEntry(animated: Bool, delayMs: UInt64 = 90) {
        debouncedFocusTask?.cancel()
        debouncedFocusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            focusOnScrubbedEntry(animated: animated)
        }
    }

    private func handleScrubBegan() {
        isScrubbing = true
        pendingFocusAfterScrub = false
        debouncedFocusTask?.cancel()
    }

    private func handleScrubEnded() {
        isScrubbing = false
        if pendingFocusAfterScrub {
            pendingFocusAfterScrub = false
            scheduleFocusOnScrubbedEntry(animated: true, delayMs: 50)
        }
    }

    private func handleSelectionDragBegan() {
        isSelectionDragging = true
        debouncedRegionTask?.cancel()
    }

    private func handleSelectionDragEnded() {
        isSelectionDragging = false
        scheduleRegionUpdate(animated: false, useDefaultZoom: false, delayMs: 60)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        stopPlayback()
        let entries = visibleHistory
        guard !entries.isEmpty else { return }
        let startTimestamp: Double
        if hasUserScrubbed, let scrubTimestamp {
            startTimestamp = scrubTimestamp
        } else if let selectedRange {
            startTimestamp = selectedRange.lowerBound
        } else {
            startTimestamp = entries.first!.TimestampDate.timeIntervalSince1970
        }
        let startIndex = entries.firstIndex { $0.TimestampDate.timeIntervalSince1970 >= startTimestamp } ?? entries.count - 1
        isPlaying = true
        playbackTask = Task {
            var currentStartIndex = startIndex
            playbackLoop: while !Task.isCancelled && isPlaying {
                for entry in entries[currentStartIndex...] {
                    if Task.isCancelled || !isPlaying { break playbackLoop }
                    await MainActor.run {
                        isPlaybackStepping = true
                        scrubTimestamp = entry.TimestampDate.timeIntervalSince1970
                        focusOnEntry(entry, within: entries)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        isPlaybackStepping = false
                    }
                    if !isPlaying { break playbackLoop }
                }
                currentStartIndex = 0
            }
            await MainActor.run {
                playbackTask = nil
                isPlaybackStepping = false
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        isPlaybackStepping = false
    }

    @MainActor
    private func focusOnEntry(_ entry: MiataruLocationData, within entries: [MiataruLocationData]) {
        guard let index = entries.firstIndex(where: { $0.Timestamp == entry.Timestamp && $0.Latitude == entry.Latitude && $0.Longitude == entry.Longitude }) else {
            updateRegion(animated: true, using: [entry], useDefaultZoom: true)
            return
        }
        let lowerBound = max(0, index - 1)
        let upperBound = min(entries.count - 1, index + 1)
        let contextEntries = Array(entries[lowerBound...upperBound])
        updateRegion(animated: true, using: contextEntries, useDefaultZoom: false)
    }
}
