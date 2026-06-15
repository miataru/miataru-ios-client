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
import Combine
import MiataruAPIClient
#if canImport(UIKit)
import UIKit
#endif

struct iPhone_DeviceHistoryMapView: View {
    private enum HistoryPanelVisibility {
        case visible
        case hidden
    }

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
    @State private var hasUserAdjustedMapCamera = false
    // Loading & data
    @State private var isLoading = true
    @State private var hasResolvedInitialHistoryLoad = false
    @State private var loadError: String? = nil
    @ObservedObject private var cache = DeviceHistoryCacheStore.shared
    @ObservedObject private var locationCache = DeviceLocationCacheStore.shared
    @State private var lastObservedDeviceLocationTimestamp: Date? = nil
    @State private var lastLocationTriggeredRefreshAt: Date? = nil
    // Timeline state
    @State private var selectedRange: ClosedRange<Double>? = nil
    /// The committed range used for map rendering - only updates when dragging ends
    @State private var displayRange: ClosedRange<Double>? = nil
    @State private var scrubTimestamp: Double? = nil
    @State private var historyPanelVisibility: HistoryPanelVisibility = .visible
    @State private var historyPanelAutoHideTask: Task<Void, Never>?
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
    @State private var suppressNextScrubFocus = false
    private let playbackContextPadding = 50
    private let activeHistoryCacheReuseWindow: TimeInterval = 3
    private let locationTriggeredRefreshThrottle: TimeInterval = 10
    private let historyPanelAutoHideDelayNanoseconds: UInt64 = 5_000_000_000
    private let maximumPlaybackStepDelayNanoseconds: UInt64 = 2_000_000_000

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

    private var currentAnalysisBucketIndex: Int? {
        guard let analysis = viewModel.historyAnalysis else { return nil }
        let timestamp = scrubTimestamp ?? selectedRange?.upperBound ?? timelineBounds?.upperBound
        guard let timestamp else { return nil }
        return analysis.bucketIndex(for: Date(timeIntervalSince1970: timestamp))
    }

    private var currentAnalysisBucket: HistoryMetricBucket? {
        viewModel.historyAnalysis?.bucket(at: currentAnalysisBucketIndex)
    }

    private var deviceLocationTimestampPublisher: AnyPublisher<Date?, Never> {
        locationCache.$locations
            .map { locations in
                locations.first(where: { $0.deviceID == device.DeviceID })?.timestamp
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
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
        let visibleHistoryCount = viewModel.visibleHistoryCount(in: displayRange)
        let selectedEntry = selectedTimelineEntry
        let fullVisibleHistory = (isPlaying || visibleHistoryCount <= 300) ? visibleHistory : []
        let mapHistory = isPlaying
            ? playbackAdjustedHistory(baseHistory: fullVisibleHistory, selectedEntry: selectedEntry)
            : fullVisibleHistory
        let useDownsampling = !isPlaying && visibleHistoryCount > 300
        // Only downsample annotations (markers), NOT the polyline source
        // This preserves the actual route shape while reducing marker count
        let annotations = useDownsampling
            ? viewModel.downsampledVisibleHistory(in: displayRange, selected: selectedEntry)
            : mapHistory
        // Always use full history for polyline to show accurate path
        let polylineSegments = isPlaying
            ? viewModel.polylineSegments(from: mapHistory)
            : viewModel.polylineSegments(in: displayRange)

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
                        VStack(spacing: 8) {
                            historyEntryDetailBubble(for: entry)
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
        .simultaneousGesture(historyMapPanGesture)
        .simultaneousGesture(historyMapZoomGesture)
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

            let centerChanged: Bool
            if let previousCenter = previousRegion?.center {
                let latDiff = abs(previousCenter.latitude - context.region.center.latitude)
                let lonDiff = abs(previousCenter.longitude - context.region.center.longitude)
                centerChanged = latDiff > 0.00005 || lonDiff > 0.00005
            } else {
                centerChanged = false
            }

            if (zoomChanged || centerChanged) && !suppressed {
                hasUserAdjustedMapCamera = true
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
            if hasResolvedInitialHistoryLoad, !isLoading, loadError == nil {
                if viewModel.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(NSLocalizedString("history_no_data", tableName: "MapNavigationHistory", comment: "No history available placeholder"))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                } else if visibleHistoryCount == 0 {
                    ErrorOverlay(
                        message: NSLocalizedString("history_no_data_in_range", tableName: "MapNavigationHistory", comment: "No history entries inside selected time range"),
                        visible: true
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                if let loadError {
                    VStack(spacing: 6) {
                        Text(NSLocalizedString("history_load_failed", tableName: "MapNavigationHistory", comment: "History load failed message"))
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
                    switch historyPanelVisibility {
                    case .visible:
                        quickRangePicker(bounds: bounds)
                            .padding(.horizontal, 16)
                            .transition(animationsAllowed ? .opacity.combined(with: .move(edge: .bottom)) : .identity)

                        HistoryMetricsPanel(
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
                            selectedCount: visibleHistoryCount,
                            totalCount: viewModel.history.count,
                            analysis: viewModel.historyAnalysis,
                            currentBucketIndex: currentAnalysisBucketIndex,
                            currentSpeedKmh: currentAnalysisBucket?.averageSpeedKmh,
                            currentAltitudeMeters: currentAnalysisBucket?.averageAltitudeMeters,
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
                            onSelectionDragEnded: handleSelectionDragEnded,
                            onHidePanel: hideHistoryPanel
                        )
                        .padding(.horizontal, 16)
                        .transition(animationsAllowed ? .opacity.combined(with: .move(edge: .bottom)) : .identity)
                    case .hidden:
                        HistoryPanelRestorePill(onRestore: restoreHistoryPanel)
                            .padding(.horizontal, 16)
                            .transition(animationsAllowed ? .opacity.combined(with: .move(edge: .bottom)) : .identity)
                    }
                }
            }
            .padding(.bottom, 16)
            .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: isPlaying)
            .animation(animationsAllowed ? .easeInOut(duration: 0.25) : nil, value: historyPanelVisibility)
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
            cancelHistoryPanelAutoHide()
            viewModel.cancelAnalysis()
        }
        .onReceive(viewModel.$history) { _ in
            initializeTimelineIfNeeded()
            scheduleHistoryAnalysis()
            updateRegionIfUserCameraAllows(animated: false)
            stopPlayback()
        }
        .onReceive(deviceLocationTimestampPublisher) { newTimestamp in
            guard let newTimestamp else { return }
            if lastObservedDeviceLocationTimestamp == nil {
                lastObservedDeviceLocationTimestamp = newTimestamp
                return
            }
            guard newTimestamp > (lastObservedDeviceLocationTimestamp ?? .distantPast) else { return }
            lastObservedDeviceLocationTimestamp = newTimestamp
            guard shouldRefreshHistoryForNewLocationTimestamp(newTimestamp) else { return }
            lastLocationTriggeredRefreshAt = Date()
            Task {
                await loadHistory(forceRefresh: true, preserveCurrentDataOnFailure: true)
            }
        }
        .onChange(of: selectedRange) { _, newValue in
            clampScrubToRange()
            // Only update displayRange (and thus the map) when not dragging
            if isSelectionDragging { return }
            displayRange = newValue
            scheduleHistoryAnalysis()
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
                if suppressNextScrubFocus {
                    suppressNextScrubFocus = false
                    return
                }
                if isScrubbing {
                    pendingFocusAfterScrub = true
                } else {
                    scheduleFocusOnScrubbedEntry(animated: false)
                }
            }
        }
    }

    private var historyMapPanGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onEnded { _ in
                handleHistoryPanelAutoHideEvent(.mapPanZoom)
            }
    }

    private var historyMapZoomGesture: some Gesture {
        MagnifyGesture()
            .onEnded { _ in
                handleHistoryPanelAutoHideEvent(.mapPanZoom)
            }
    }

    @ViewBuilder
    private func quickRangePicker(bounds: ClosedRange<Double>) -> some View {
        let visibleQuickRanges = meaningfulQuickRanges(for: bounds)

        HStack(spacing: 4) {
            ForEach(visibleQuickRanges, id: \.key) { item in
                let isSelected = isQuickRangeSelected(duration: item.duration, bounds: bounds)
                Button {
                    applyQuickRange(duration: item.duration, bounds: bounds)
                } label: {
                    Text(NSLocalizedString(item.key, tableName: "MapNavigationHistory", comment: "Quick picker option for a fixed time range"))
                        .font(.caption2.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .background {
                            if isSelected {
                                quickRangeSelectedBackground
                            }
                        }
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier(item.key)
            }
        }
        .padding(4)
        .background(quickRangePickerBackground)
        .clipShape(Capsule(style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var quickRangePickerBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(in: .capsule)
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var quickRangeSelectedBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.accentColor.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.75)
            }
    }

    private func meaningfulQuickRanges(for bounds: ClosedRange<Double>) -> [(key: String, duration: TimeInterval)] {
        let availableDuration = max(bounds.upperBound - bounds.lowerBound, 0)
        let epsilon: TimeInterval = 1

        return quickRanges.filter { item in
            if item.duration == Double.greatestFiniteMagnitude {
                return true
            }

            return item.duration < availableDuration - epsilon
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
                NSLocalizedString("history_playback_speed_hint", tableName: "MapNavigationHistory", comment: "Long press to change playback speed"
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

    private func loadHistory(forceRefresh: Bool = false, preserveCurrentDataOnFailure: Bool = false) async {
        if let knownTimestamp = locationCache.getLocation(for: device.DeviceID)?.timestamp {
            lastObservedDeviceLocationTimestamp = knownTimestamp
        }

        if let cached = cache.getHistory(for: device.DeviceID) {
            debugLog("[DeviceHistoryMapView] Using cached history for device \(device.DeviceID) entries=\(cached.count)")
            await MainActor.run {
                viewModel.setHistory(cached)
                if !cached.isEmpty {
                    hasResolvedInitialHistoryLoad = true
                }
                initializeTimelineIfNeeded()
            }
        }

        let latestKnownLocationTimestamp = locationCache.getLocation(for: device.DeviceID)?.timestamp
        let shouldRefresh = forceRefresh || cache.shouldRefreshHistory(
            for: device.DeviceID,
            latestKnownLocationTimestamp: latestKnownLocationTimestamp,
            maxAge: activeHistoryCacheReuseWindow
        )
        guard shouldRefresh else {
            await MainActor.run {
                isLoading = false
                hasResolvedInitialHistoryLoad = true
            }
            return
        }

        guard let url = URL(string: SettingsManager.shared.miataruServerURL) else {
            await MainActor.run {
                isLoading = false
                hasResolvedInitialHistoryLoad = true
                loadError = NSLocalizedString("server_url_invalid", tableName: "SettingsDiagnostics", comment: "The server URL is invalid.")
            }
            return
        }
        let requestingDeviceID = thisDeviceIDManager.shared.deviceID
        await MainActor.run {
            isLoading = true
            if viewModel.history.isEmpty {
                hasResolvedInitialHistoryLoad = false
            }
            loadError = nil
        }
        do {
            debugLog("[DeviceHistoryMapView] Fetching history for device \(device.DeviceID)")
            APIRequestCounter.shared.record(.getLocationHistory)
            let data = try await MiataruAppAPI.getLocationHistory(
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
                if sorted.isEmpty {
                    cache.removeHistory(for: device.DeviceID)
                } else {
                    cache.setHistory(sorted, for: device.DeviceID)
                }
                isLoading = false
                hasResolvedInitialHistoryLoad = true
                debugLog("[DeviceHistoryMapView] Loaded history entries=\(sorted.count) for device \(device.DeviceID)")
                if sorted.isEmpty {
                    loadError = NSLocalizedString("history_no_data", tableName: "MapNavigationHistory", comment: "No history available placeholder")
                }
                initializeTimelineIfNeeded()
                updateRegionIfUserCameraAllows(animated: false)
            }
        } catch let apiError as MiataruAPIClient.APIError {
            await MainActor.run {
                isLoading = false
                hasResolvedInitialHistoryLoad = true
                loadError = mapAPIError(apiError)
                if !preserveCurrentDataOnFailure {
                    viewModel.setHistory([])
                }
            }
        } catch {
            debugLog("[DeviceHistoryMapView] Failed to load history for device \(device.DeviceID): \(error.localizedDescription)")
            await MainActor.run {
                loadError = error.localizedDescription
                isLoading = false
                hasResolvedInitialHistoryLoad = true
                if !preserveCurrentDataOnFailure {
                    viewModel.setHistory([])
                }
            }
        }
    }

    private func shouldRefreshHistoryForNewLocationTimestamp(_ timestamp: Date) -> Bool {
        guard !isLoading else { return false }

        if let lastLocationTriggeredRefreshAt,
           Date().timeIntervalSince(lastLocationTriggeredRefreshAt) < locationTriggeredRefreshThrottle {
            return false
        }

        if let newestHistoryTimestamp = viewModel.history.last?.TimestampDate {
            return timestamp.timeIntervalSince(newestHistoryTimestamp) > 1
        }

        return true
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
    private func scheduleHistoryAnalysis() {
        guard let bounds = timelineBounds, !viewModel.history.isEmpty else {
            viewModel.cancelAnalysis()
            return
        }

        let range = selectedRange ?? bounds
        viewModel.scheduleAnalysis(in: range)
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
    private func updateRegionIfUserCameraAllows(animated: Bool) {
        guard !hasUserAdjustedMapCamera else { return }
        updateRegion(animated: animated)
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

    private func color(for entry: MiataruLocationData, within _: [MiataruLocationData]) -> Color {
        let timestamp = entry.TimestampDate.timeIntervalSince1970
        guard let ratio = viewModel.historyColorRatio(for: timestamp) else { return .blue }
        return Self.historyColor(for: ratio)
    }

    private func historyEntryDetailBubble(for entry: MiataruLocationData) -> some View {
        let rows = historyDetailRows(for: entry)

        return VStack(alignment: .leading, spacing: 5) {
            Text(Self.timelineDateFormatter.string(from: entry.TimestampDate))
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 5) {
                    Image(systemName: row.systemImage)
                        .font(.caption2)
                        .frame(width: 12)
                        .foregroundStyle(.secondary)
                    Text(row.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: 240, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func historyDetailRows(for entry: MiataruLocationData) -> [(systemImage: String, text: String)] {
        var rows: [(systemImage: String, text: String)] = [
            ("location", coordinateText(latitude: entry.Latitude, longitude: entry.Longitude))
        ]

        if entry.HorizontalAccuracy.isFinite, entry.HorizontalAccuracy > 0 {
            rows.append(("scope", "\(NSLocalizedString("Accuracy", tableName: "MapNavigationHistory", comment: "Accuracy display in Location Tracking Details")): \(distanceText(meters: entry.HorizontalAccuracy, maximumFractionDigits: 0))"))
        }

        if let speedText = mapSpeedLabelText(speedMetersPerSecond: entry.Speed, minSpeedKmh: 0) {
            rows.append(("speedometer", "\(NSLocalizedString("Speed", tableName: "MapNavigationHistory", comment: "Speed display in Location Tracking Details")): \(speedText)"))
        }

        if let altitude = entry.Altitude, altitude.isFinite {
            rows.append(("mountain.2", "\(NSLocalizedString("altitude_label", tableName: "MapNavigationHistory", comment: "Altitude label/abbreviation for display in device row")): \(distanceText(meters: altitude, maximumFractionDigits: 0))"))
        }

        if let batteryLevel = entry.BatteryLevel, batteryLevel.isFinite, batteryLevel >= 0 {
            rows.append(("battery.100", "\(NSLocalizedString("Battery level", tableName: "MapNavigationHistory", comment: "Battery level display in Location Tracking Details")): \(batteryText(batteryLevel))"))
        }

        return rows
    }

    private func coordinateText(latitude: Double, longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private func batteryText(_ batteryLevel: Double) -> String {
        let normalized = batteryLevel <= 1 ? batteryLevel * 100 : batteryLevel
        return String(format: "%.0f%%", min(max(normalized, 0), 100))
    }

    private func distanceText(meters: Double, maximumFractionDigits: Int) -> String {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }

        let value = usesMetric ? meters : meters * 3.28084
        let unit = usesMetric
            ? NSLocalizedString("altitude_meters", tableName: "MapNavigationHistory", comment: "Altitude in meters")
            : NSLocalizedString("altitude_feet", tableName: "MapNavigationHistory", comment: "Altitude in feet")
        return "\(localizedNumber(value, maximumFractionDigits: maximumFractionDigits)) \(unit)"
    }

    private func localizedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maximumFractionDigits)f", value)
    }

    private func isSelectedEntry(_ entry: MiataruLocationData, selected: MiataruLocationData) -> Bool {
        return selected.Timestamp == entry.Timestamp &&
            selected.Latitude == entry.Latitude &&
            selected.Longitude == entry.Longitude
    }

    private func selectEntryFromMap(_ entry: MiataruLocationData) {
        let timestamp = entry.TimestampDate.timeIntervalSince1970
        handleHistoryPanelAutoHideEvent(.mapPointSelection)
        stopPlayback()
        guard scrubTimestamp != timestamp else {
            hasUserScrubbed = true
            return
        }
        suppressNextScrubFocus = true
        debouncedFocusTask?.cancel()
        scrubTimestamp = timestamp
        hasUserScrubbed = true
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
            return NSLocalizedString("server_url_invalid", tableName: "SettingsDiagnostics", comment: "The server URL is invalid.")
        case .invalidResponse(_):
            return NSLocalizedString("server_response_invalid", tableName: "SettingsDiagnostics", comment: "The server response was invalid.")
        case .encodingError(let err):
            debugLog("[DeviceHistoryMapView] Encoding error while loading history: \(err.localizedDescription)")
            return NSLocalizedString("history_load_failed", tableName: "MapNavigationHistory", comment: "Could not load history.")
        case .decodingError(let err):
            return "\(NSLocalizedString("decoding_error", tableName: "SettingsDiagnostics", comment: "Error processing the server response.")) \(err.localizedDescription)"
        case .requestFailed(let err):
            return "\(NSLocalizedString("network_error", tableName: "SettingsDiagnostics", comment: "Network error. Please check your internet connection.")) \(err.localizedDescription)"
        case .serverError(_, let message):
            return String(format: NSLocalizedString("server_error", tableName: "SettingsDiagnostics", comment: "Server error: %@"), message)
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
        hasUserAdjustedMapCamera = false
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
        scheduleHistoryAnalysis()
        scheduleRegionUpdate(animated: false, useDefaultZoom: false, delayMs: 60)
    }

    private func hideHistoryPanel() {
        cancelHistoryPanelAutoHide()
        if animationsAllowed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                historyPanelVisibility = .hidden
            }
        } else {
            historyPanelVisibility = .hidden
        }
    }

    private func restoreHistoryPanel() {
        cancelHistoryPanelAutoHide()
        if animationsAllowed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                historyPanelVisibility = .visible
            }
        } else {
            historyPanelVisibility = .visible
        }
    }

    private func scheduleHistoryPanelAutoHide(restartExisting: Bool) {
        guard historyPanelVisibility == .visible else { return }

        if restartExisting {
            cancelHistoryPanelAutoHide()
        } else if historyPanelAutoHideTask != nil {
            return
        }

        historyPanelAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: historyPanelAutoHideDelayNanoseconds)
            guard !Task.isCancelled else { return }
            historyPanelAutoHideTask = nil
            guard historyPanelVisibility == .visible else { return }
            hideHistoryPanel()
        }
    }

    private func cancelHistoryPanelAutoHide() {
        historyPanelAutoHideTask?.cancel()
        historyPanelAutoHideTask = nil
    }

    private func handleHistoryPanelAutoHideEvent(_ event: HistoryPanelAutoHideEvent) {
        switch HistoryPanelAutoHidePolicy.action(for: event) {
        case .none:
            return
        case .startOrRestart:
            scheduleHistoryPanelAutoHide(restartExisting: true)
        }
    }

    private func togglePlayback() {
        handleHistoryPanelAutoHideEvent(.playbackPlayPause)
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
            playbackLoop: while !Task.isCancelled && isPlaying {
                for index in currentStartIndex..<entries.count {
                    let entry = entries[index]
                    let nextEntry = index + 1 < entries.count ? entries[index + 1] : nil
                    if Task.isCancelled || !isPlaying { break playbackLoop }
                    await MainActor.run {
                        isPlaybackStepping = true
                        scrubTimestamp = entry.TimestampDate.timeIntervalSince1970
                        focusOnEntry(entry, within: entries)
                    }
                    // Read playback speed dynamically so long-press changes take effect immediately.
                    let currentPlaybackSpeed = await MainActor.run { playbackSpeed }
                    let adjustedDelay = playbackDelayNanoseconds(
                        from: entry,
                        to: nextEntry,
                        playbackSpeed: currentPlaybackSpeed
                    )
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

    private func playbackDelayNanoseconds(
        from entry: MiataruLocationData,
        to nextEntry: MiataruLocationData?,
        playbackSpeed: Double
    ) -> UInt64 {
        let effectivePlaybackSpeed = max(playbackSpeed, 1)
        let maximumDelay = Double(maximumPlaybackStepDelayNanoseconds) / effectivePlaybackSpeed

        guard let nextEntry else {
            return UInt64(maximumDelay.rounded())
        }

        let elapsedSeconds = nextEntry.TimestampDate.timeIntervalSince(entry.TimestampDate)
        guard elapsedSeconds.isFinite, elapsedSeconds > 0 else {
            return 0
        }

        let measuredDelay = elapsedSeconds * 1_000_000_000 / effectivePlaybackSpeed
        let clampedDelay = min(measuredDelay, maximumDelay)
        return UInt64(clampedDelay.rounded())
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
