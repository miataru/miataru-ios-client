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
#if canImport(UIKit)
import UIKit
#endif

struct iPhone_DeviceHistoryMapView: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    let device: KnownDevice
    @StateObject private var viewModel = DeviceHistoryMapViewModel()
    // Map state
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
        )
    )
    @State private var currentRegion: MKCoordinateRegion? = nil
    @State private var playbackLockedSpan: MKCoordinateSpan? = nil
    @State private var suppressUserCameraChangeDetectionUntil: Date? = nil
    // Loading & data
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @ObservedObject private var cache = DeviceHistoryCacheStore.shared
    // Timeline state
    @State private var selectedRange: ClosedRange<Double>? = nil
    /// The committed range used for map rendering - only updates when dragging ends
    @State private var displayRange: ClosedRange<Double>? = nil
    @State private var scrubTimestamp: Double? = nil
    // Playback
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var hasUserScrubbed = false
    @State private var isPlaybackStepping = false
    @State private var playbackSpeed: Double = 1.0
    @State private var showSpeedOverlay = false
    @State private var speedOverlayTask: Task<Void, Never>?
    // Debounced tasks to avoid excessive map updates
    @State private var debouncedRegionTask: Task<Void, Never>?
    @State private var debouncedFocusTask: Task<Void, Never>?
    // Interaction flags
    @State private var isScrubbing = false
    @State private var pendingFocusAfterScrub = false
    @State private var isSelectionDragging = false
    private let playbackContextPadding = 50

    /// Uses displayRange (committed range) for map rendering to avoid constant updates during dragging
    private var visibleHistory: [MiataruLocationData] {
        viewModel.visibleHistory(in: displayRange)
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

    private let quickRanges: [(key: String, duration: TimeInterval)] = [
        ("history_quick_range_24h", 24 * 60 * 60),
        ("history_quick_range_7d", 7 * 24 * 60 * 60),
        ("history_quick_range_31d", 31 * 24 * 60 * 60),
        // Use a very large duration to cover the full available range
        ("history_quick_range_all", Double.greatestFiniteMagnitude)
    ]

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
        // Only downsample annotations (markers), NOT the polyline source
        // This preserves the actual route shape while reducing marker count
        let annotations = useDownsampling
            ? viewModel.downsample(mapHistory, selected: selectedEntry)
            : mapHistory
        // Always use full history for polyline to show accurate path
        let polylineSegments = viewModel.polylineSegments(from: mapHistory)

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
        .onMapCameraChange(frequency: .continuous) { context in
            let previousRegion = currentRegion
            let now = Date()
            let suppressed = suppressUserCameraChangeDetectionUntil.map { now < $0 } ?? false

            let zoomChanged: Bool
            if let previousSpan = previousRegion?.span {
                let latDiff = abs(previousSpan.latitudeDelta - context.region.span.latitudeDelta)
                let lonDiff = abs(previousSpan.longitudeDelta - context.region.span.longitudeDelta)
                zoomChanged = latDiff > 0.00005 || lonDiff > 0.00005
            } else {
                zoomChanged = false
            }

            if isPlaying && zoomChanged && !suppressed {
                playbackLockedSpan = context.region.span
            }

            currentRegion = context.region
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
                    if isPlaying {
                        // Collapsed view: only play button
                        collapsedPlaybackButton
                            .padding(.horizontal, 16)
                    } else {
                        // Expanded view: all controls
                        quickRangePicker(bounds: bounds)
                            .padding(.horizontal, 16)
                            .transition(animationsAllowed ? .opacity.combined(with: .move(edge: .bottom)) : .identity)

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
                            playbackSpeed: playbackSpeed,
                            onPlayPause: togglePlayback,
                            onLongPressSpeedUp: handleLongPressSpeedUp,
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
                        .transition(animationsAllowed ? .opacity.combined(with: .move(edge: .bottom)) : .identity)
                    }
                }
            }
            .padding(.bottom, 16)
            .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: isPlaying)
        }
        .overlay {
            if showSpeedOverlay {
                PlaybackSpeedOverlay(speed: playbackSpeed)
                    .transition(animationsAllowed ? .opacity.combined(with: .scale(scale: 0.8)) : .identity)
            }
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
            speedOverlayTask?.cancel()
        }
        .onReceive(viewModel.$history) { _ in
            initializeTimelineIfNeeded()
            updateRegion(animated: false)
            stopPlayback()
        }
        .onChange(of: selectedRange) { _, newValue in
            clampScrubToRange()
            // Only update displayRange (and thus the map) when not dragging
            if isSelectionDragging { return }
            displayRange = newValue
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

    @ViewBuilder
    private func quickRangePicker(bounds: ClosedRange<Double>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickRanges, id: \.key) { item in
                    let isSelected = isQuickRangeSelected(duration: item.duration, bounds: bounds)
                    Button {
                        applyQuickRange(duration: item.duration, bounds: bounds)
                    } label: {
                        Text(NSLocalizedString(item.key, comment: "Quick picker option for a fixed time range"))
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minWidth: 70)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .accentColor : .secondary)
                    .accessibilityIdentifier(item.key)
                }
            }
        }
    }

    @ViewBuilder
    private var collapsedPlaybackButton: some View {
        ZStack {
            // Play/Pause icon with pulse animation when playing
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 56))
                .foregroundStyle(isPlaying ? Color.accentColor : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isPlaying ? 1.05 : 1.0)
                .animation(
                    animationsAllowed
                        ? (isPlaying
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .default)
                        : nil,
                    value: isPlaying
                )

            // Speed badge shown when playing faster than 1x
            if isPlaying && playbackSpeed > 1.0 {
                Text(String(format: "%.0fx", playbackSpeed))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue, in: Capsule())
                    .offset(x: 20, y: -20)
                    .transition(animationsAllowed ? .scale.combined(with: .opacity) : .identity)
                    .animation(animationsAllowed ? .easeInOut(duration: 0.2) : nil, value: playbackSpeed)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            togglePlayback()
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            triggerMediumHaptic()
            handleLongPressSpeedUp()
        }
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(in: .circle)
            } else {
                Color.clear
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(12)
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

    private func triggerMediumHaptic() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
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
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            debugLog("[DeviceHistoryMapView] Fetching history for device \(device.DeviceID)")
            APIRequestCounter.shared.record(.getLocationHistory)
            let data = try await MiataruAPIClient.getLocationHistory(
                serverURL: url,
                forDeviceID: device.DeviceID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: SettingsManager.shared.deviceKey,
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
        if displayRange == nil {
            displayRange = selectedRange
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

        setCameraRegion(region, animated: animated)
    }

    @MainActor
    private func setCameraRegion(_ region: MKCoordinateRegion, animated: Bool) {
        let suppressionWindow: TimeInterval = animated ? 0.9 : 0.35
        suppressUserCameraChangeDetectionUntil = Date().addingTimeInterval(suppressionWindow)

        if animated && animationsAllowed {
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
        // Use the full history to keep a consistent color mapping regardless of timeline selection
        let reference = viewModel.history.isEmpty ? entries : viewModel.history
        guard !reference.isEmpty else { return .blue }
        let timestamps = reference.map { $0.TimestampDate.timeIntervalSince1970 }
        guard let minTimestamp = timestamps.min(), let maxTimestamp = timestamps.max() else { return .blue }
        let total = maxTimestamp - minTimestamp
        let diff = entry.TimestampDate.timeIntervalSince1970 - minTimestamp
        let ratio = total > 0 ? diff / total : 0
        return Self.historyColor(for: ratio)
    }

    private func formattedDateTimeLabel(for entry: MiataruLocationData) -> String {
        let dateTimeText = Self.timelineDateFormatter.string(from: entry.TimestampDate)
        let speedText = mapSpeedLabelText(speedMetersPerSecond: entry.Speed, minSpeedKmh: 0)
        return speedText != nil ? "\(dateTimeText) • \(speedText!)" : dateTimeText
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
            debugLog("[DeviceHistoryMapView] Encoding error while loading history: \(err.localizedDescription)")
            return NSLocalizedString("history_load_failed", comment: "Could not load history.")
        case .decodingError(let err):
            return "\(NSLocalizedString("decoding_error", comment: "Error processing the server response.")) \(err.localizedDescription)"
        case .requestFailed(let err):
            return "\(NSLocalizedString("network_error", comment: "Network error. Please check your internet connection.")) \(err.localizedDescription)"
        case .serverError(_, let message):
            return String(format: NSLocalizedString("server_error", comment: "Server error: %@"), message)
        }
    }

    private func applyQuickRange(duration: TimeInterval, bounds: ClosedRange<Double>) {
        let upper = bounds.upperBound
        let lower = max(bounds.lowerBound, upper - duration)
        let newRange = lower...upper
        selectedRange = newRange
        displayRange = newRange
        scrubTimestamp = upper
        hasUserScrubbed = false
        scheduleRegionUpdate(animated: true)
    }

    private func isQuickRangeSelected(duration: TimeInterval, bounds: ClosedRange<Double>) -> Bool {
        guard let selectedRange else { return false }
        let upper = bounds.upperBound
        let lower = max(bounds.lowerBound, upper - duration)
        let epsilon: Double = 1.0
        return abs(selectedRange.lowerBound - lower) <= epsilon && abs(selectedRange.upperBound - upper) <= epsilon
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
        // Commit the selection to displayRange - this triggers the map update
        displayRange = selectedRange
        scheduleRegionUpdate(animated: false, useDefaultZoom: false, delayMs: 60)
    }

    private func togglePlayback() {
        if isPlaying {
            // Mark current position so resume continues from here
            hasUserScrubbed = true
            stopPlayback()
            // Reset speed to 1x on pause
            if playbackSpeed != 1.0 {
                playbackSpeed = 1.0
                showSpeedOverlayBriefly()
            }
        } else {
            startPlayback()
        }
    }

    private func handleLongPressSpeedUp() {
        guard isPlaying else { return }
        // Cycle through 1x → 2x → 4x → 8x → 1x
        switch playbackSpeed {
        case 1.0:
            playbackSpeed = 2.0
        case 2.0:
            playbackSpeed = 4.0
        case 4.0:
            playbackSpeed = 8.0
        default:
            playbackSpeed = 1.0
        }
        showSpeedOverlayBriefly()
        // Speed is read dynamically in playback loop, no restart needed
    }

    private func showSpeedOverlayBriefly() {
        speedOverlayTask?.cancel()
        if animationsAllowed {
            withAnimation(.easeInOut(duration: 0.2)) {
                showSpeedOverlay = true
            }
        } else {
            showSpeedOverlay = true
        }
        speedOverlayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if animationsAllowed {
                withAnimation(.easeOut(duration: 0.3)) {
                    showSpeedOverlay = false
                }
            } else {
                showSpeedOverlay = false
            }
        }
    }

    private func startPlayback() {
        stopPlayback()
        playbackLockedSpan = nil
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
            let baseDelay: UInt64 = 2_000_000_000
            playbackLoop: while !Task.isCancelled && isPlaying {
                for entry in entries[currentStartIndex...] {
                    if Task.isCancelled || !isPlaying { break playbackLoop }
                    await MainActor.run {
                        isPlaybackStepping = true
                        scrubTimestamp = entry.TimestampDate.timeIntervalSince1970
                        focusOnEntry(entry, within: entries)
                    }
                    // Read speed dynamically on each step to allow real-time speed changes
                    let currentSpeed = await MainActor.run { playbackSpeed }
                    let adjustedDelay = UInt64(Double(baseDelay) / currentSpeed)
                    try? await Task.sleep(nanoseconds: adjustedDelay)
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
        playbackLockedSpan = nil
    }

    @MainActor
    private func focusOnEntry(_ entry: MiataruLocationData, within entries: [MiataruLocationData]) {
        let coordinate = CLLocationCoordinate2D(latitude: entry.Latitude, longitude: entry.Longitude)
        if let lockedSpan = playbackLockedSpan, isPlaying {
            let region = MKCoordinateRegion(center: coordinate, span: lockedSpan)
            setCameraRegion(region, animated: true)
            return
        }

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
