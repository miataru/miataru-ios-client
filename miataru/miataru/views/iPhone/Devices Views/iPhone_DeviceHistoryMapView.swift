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
    @State private var selectedRange: ClosedRange<Double>? = nil
    @State private var scrubTimestamp: Double? = nil
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var hasUserScrubbed = false
    @State private var isPlaybackStepping = false

    private var visibleHistory: [MiataruLocationData] {
        guard let selectedRange else { return history }
        return history.filter { selectedRange.contains($0.TimestampDate.timeIntervalSince1970) }
    }

    private var timelineBounds: ClosedRange<Double>? {
        guard let first = history.first?.TimestampDate.timeIntervalSince1970,
              let last = history.last?.TimestampDate.timeIntervalSince1970 else { return nil }
        return first...last
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
        return entryClosest(to: scrubTimestamp, in: visibleHistory)
    }

    fileprivate static let timelineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    fileprivate static let timelineTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        let displayedHistory = visibleHistory

        Map(position: $cameraPosition) {
            ForEach(Array(displayedHistory.enumerated()), id: \.offset) { _, entry in
                let coord = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)
                let isSelected = isSelectedEntry(entry)
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
                            MiataruMapMarker(color: color(for: entry, within: displayedHistory))
                                .shadow(radius: 2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectEntryFromMap(entry)
                        }
                    } else {
                        Circle()
                            .fill(color(for: entry, within: displayedHistory))
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
                if history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("history_no_data", comment: "No history available placeholder"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                } else if displayedHistory.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "timeline.selection")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("history_no_data_in_range", comment: "No history entries inside selected time range"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
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

                if let bounds = timelineBounds, !history.isEmpty {
                    DeviceHistoryTimelineOverlay(
                        fullRange: bounds,
                        selection: Binding(
                            get: { selectedRange ?? bounds },
                            set: { newValue in
                                selectedRange = newValue
                            }
                        ),
                        scrubValue: Binding(
                            get: { scrubTimestamp ?? bounds.upperBound },
                            set: { newValue in
                                scrubTimestamp = newValue
                            }
                        ),
                        ticks: timelineTicks,
                        selectedCount: displayedHistory.count,
                        totalCount: history.count,
                        isPlaying: isPlaying,
                        onPlayPause: togglePlayback,
                        onScrubShown: { hasUserScrubbed = true },
                        stopPlayback: stopPlayback,
                        startPlayback: startPlayback,
                        isPlaybackStepping: isPlaybackStepping
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
        }
        .onChange(of: history.map { $0.Timestamp }) { _, _ in
            initializeTimelineIfNeeded()
            updateRegion(animated: false)
            stopPlayback()
        }
        .onChange(of: selectedRange) { _, _ in
            clampScrubToRange()
            updateRegion()
            if isPlaying {
                startPlayback()
            }
        }
        .onChange(of: scrubTimestamp) { _, _ in
            if isPlaybackStepping { return }
            if isPlaying {
                startPlayback()
            } else {
                focusOnScrubbedEntry()
            }
        }
    }

    private func loadHistory() async {
        if let cached = cache.getHistory(for: device.DeviceID) {
            debugLog("[DeviceHistoryMapView] Using cached history for device \(device.DeviceID) entries=\(cached.count)")
            await MainActor.run {
                history = cached
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
                amount: 1000
            )
            let normalized = normalizeHistoryEntries(from: data)
            let sorted = normalized.sorted { $0.TimestampDate < $1.TimestampDate }
            await MainActor.run {
                history = sorted
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
                history = []
            }
        } catch {
            debugLog("[DeviceHistoryMapView] Failed to load history for device \(device.DeviceID): \(error.localizedDescription)")
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
                history = []
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
            let span = spanForZoomLevel(SettingsManager.shared.mapZoomLevel)
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: firstPoint.Latitude, longitude: firstPoint.Longitude),
                span: span
            )
        } else {
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
        let source = visibleHistory
        guard let target = entryClosest(to: scrubTimestamp, in: source) else { return }
        Task { @MainActor in
            updateRegion(animated: animated, using: [target], useDefaultZoom: true)
        }
    }

    private func entryClosest(to timestamp: Double, in entries: [MiataruLocationData]) -> MiataruLocationData? {
        guard !entries.isEmpty else { return nil }
        return entries.min(by: { abs($0.TimestampDate.timeIntervalSince1970 - timestamp) < abs($1.TimestampDate.timeIntervalSince1970 - timestamp) })
    }

    private func color(for entry: MiataruLocationData, within entries: [MiataruLocationData]) -> Color {
        guard let first = entries.first?.TimestampDate, let last = entries.last?.TimestampDate else { return .blue }
        let total = last.timeIntervalSince(first)
        let diff = entry.TimestampDate.timeIntervalSince(first)
        let ratio = total > 0 ? diff / total : 0
        // Older points blue, newer red
        return Color(hue: 0.6 - 0.6 * ratio, saturation: 0.9, brightness: 0.9)
    }

    private func formattedDateTimeLabel(for entry: MiataruLocationData) -> String {
        Self.timelineDateFormatter.string(from: entry.TimestampDate)
    }

    private func isSelectedEntry(_ entry: MiataruLocationData) -> Bool {
        guard let selectedTimelineEntry else { return false }
        return selectedTimelineEntry.Timestamp == entry.Timestamp &&
            selectedTimelineEntry.Latitude == entry.Latitude &&
            selectedTimelineEntry.Longitude == entry.Longitude
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

private struct DeviceHistoryTimelineOverlay: View {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formattedDate(selection.lowerBound)) – \(formattedDate(selection.upperBound))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Text(String(format: NSLocalizedString("history_timeline_visible_count", comment: "Visible items count out of total"), selectedCount, totalCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: { onPlayPause() }) {
                    Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                        .id(isPlaying ? "pause-icon" : "play-icon")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title)
                        .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                        .padding(10)
                        .background(buttonBackground)
                        .overlay(buttonStroke)
                        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                        .scaleEffect(isPlaying ? 1.05 : 1.0)
                        .animation(
                            isPlaying
                                ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                                : .default,
                            value: isPlaying
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        NSLocalizedString(
                            isPlaying ? "history_pause_timeline" : "history_play_timeline",
                            comment: "Play/pause timeline playback"
                        )
                    )
                )
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
                startPlayback: startPlayback
            )
            .frame(height: 52)
        }
        .padding(12)
        .background(timelineBackground(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = Circle()
        if #available(iOS 26.0, *) {
            shape
                .glassEffect(in: .rect(cornerRadius: 40))
        } else {
            shape
                .fill(.thinMaterial)
        }
    }

    private var buttonStroke: some View {
        Circle()
            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    }

    private func formattedDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineDateFormatter.string(from: date)
    }

    private func formattedTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineTimeFormatter.string(from: date)
    }

    @ViewBuilder
    private func timelineBackground(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .glassEffect(in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

private struct TimelineRangeSlider: View {
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

    @State private var lowerStart: Double?
    @State private var upperStart: Double?
    @State private var scrubStart: Double?
    @State private var selectionDragStart: ClosedRange<Double>?
    @State private var showScrubHandle = false
    @State private var playPauseHighlight = false

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

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(upperX - lowerX, 2), height: trackHeight + 2)
                    .offset(x: lowerX)
                    .frame(maxHeight: .infinity, alignment: .center)
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
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if selectionDragStart == nil { selectionDragStart = selection }
                                guard let startRange = selectionDragStart else { return }
                                let deltaValue = Double(value.translation.width / width) * rangeSpan
                                let candidateLower = startRange.lowerBound + deltaValue
                                let clampedLower = min(max(range.lowerBound, candidateLower), range.upperBound - selectionSpan)
                                let newSelection = clampedLower...(clampedLower + selectionSpan)
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
                                selectionDragStart = nil
                            }
                    )

                ForEach(ticks, id: \.self) { tick in
                    let x = xPosition(for: tick, width: width)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 22)
                        .offset(x: x - 0.5, y: 5)
                        .allowsHitTesting(false)
                }

                if showScrubHandle || externalShowHandle {
                    scrubHandle(
                        x: scrubX,
                        trackCenterY: trackCenterY,
                        label: formattedTime(scrubValue)
                    )
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scrubStart == nil { scrubStart = scrubValue }
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
                                }
                        )
                }

                rangeHandle(x: lowerX, systemName: "arrowtriangle.backward.fill")
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if lowerStart == nil { lowerStart = selection.lowerBound }
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
                            }
                    )

                rangeHandle(x: upperX, systemName: "arrowtriangle.forward.fill")
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if upperStart == nil { upperStart = selection.upperBound }
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
                            }
                    )
            }
        }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0 }
        let ratio = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(ratio) * width
    }

    private func valueForPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let clampedX = min(max(0, x), width)
        let ratio = Double(clampedX / width)
        return range.lowerBound + (range.upperBound - range.lowerBound) * ratio
    }

    private func scrubHandle(x: CGFloat, trackCenterY: CGFloat, label: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 18)
                .shadow(radius: 2)
                .position(x: x, y: trackCenterY + 1)
            Text(label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .position(x: x, y: trackCenterY - 16)
        }
        .accessibilityLabel(Text(NSLocalizedString("history_timeline_scrub_handle", comment: "Scrub handle for history timeline")))
    }

    private func formattedTime(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return iPhone_DeviceHistoryMapView.timelineTimeFormatter.string(from: date)
    }

    private func rangeHandle(x: CGFloat, systemName: String) -> some View {
        Capsule()
            .fill(.thinMaterial)
            .frame(width: 26, height: 26)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
            )
            .shadow(radius: 2)
            .offset(x: x - 13)
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
