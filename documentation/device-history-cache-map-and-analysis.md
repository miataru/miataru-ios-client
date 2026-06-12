# Device History Cache, Map, And Analysis

## Summary

This document consolidates Miataru's device history behavior: cache refresh policy, loading feedback, user camera priority, and the iPhone history analysis panel.

## Source Notes Consolidated

This document consolidates:

- `device-history-cache-refresh-2026-03-06.md`
- `device-history-loading-feedback-2026-04-24.md`
- `device-history-map-user-camera-priority-2026-04-24.md`
- `device-history-analysis-panel-2026-06-11.md`

## Cache Refresh Behavior

Device history used to remain stale after a newer location was known for the same device. The history flow now has richer cache metadata and explicit refresh decisions.

`DeviceHistoryCacheStore` entries include:

- cached history payload
- fetch timestamp
- newest history timestamp

Refresh decision:

- `shouldRefreshHistory(for:latestKnownLocationTimestamp:maxAge:)`
- Refreshes when the cache is too old.
- Refreshes when the latest known device location is newer than the cached history, with tolerance.

Invalidation:

- `removeHistory(for:)` clears stale or invalid entries.
- If the server returns empty history, the local history cache is removed for that device.

Flow behavior:

- iPhone and iPad map history entry points fetch before opening history instead of short-circuiting on cached results.
- The iPhone history map can reuse cache briefly for responsiveness.
- Active history views observe known device-location timestamp changes and refresh while in use, throttled.
- Refresh failures triggered by location changes keep the currently visible history.

Expected result:

- Opening history fetches fresh data.
- Active history usage can reuse cache briefly.
- New location updates refresh history only while the history view is active.
- Empty or unauthorized-like history responses do not leave stale local history behind.

## Loading Feedback

Opening location history now provides immediate feedback while preloading.

Behavior:

- iPhone and iPad device maps show a loading HUD during history preload.
- The selected device name or ID appears in the HUD.
- `history_loading` is localized for all app languages.
- The history map starts in an initial loading state so it does not briefly flash the empty-state screen before cached/fresh history arrives.
- Preload failures are visible for invalid configuration, invalid server response, encoding/decoding failures, network failures, server failures, and unknown errors.
- History preload error visibility increased to 5 seconds.
- The common error overlay wraps long messages more reliably.

Expected UX:

- Users immediately see that history data is loading.
- Existing history should appear without an intermediate "no history" fallback.
- Failures or real empty states show readable localized messages.

## User Camera Priority

The history map refreshes while open. Before the camera-priority fix, every `viewModel.history` publish called `updateRegion(animated: false)`, which was correct for initial setup but wrong after manual panning or zooming.

Current behavior:

- `iPhone_DeviceHistoryMapView` tracks manual camera adjustment through non-suppressed center/zoom changes from `onMapCameraChange`.
- History reloads still update timeline, annotations, and polyline.
- Region fitting goes through `updateRegionIfUserCameraAllows(animated:)`.
- Once the user pans or zooms, live history refreshes no longer override the current camera.
- Programmatic camera updates keep the existing suppression window so initial fit, playback focus, and explicit camera moves do not count as manual adjustment.
- Quick range selection resets the manual-camera flag because choosing a range is an explicit request to refit the visible slice.

## Analysis Panel

The iPhone device history map keeps its route, annotation, playback, selected range, and timeline behavior while adding compact speed and altitude analysis.

The analysis is secondary to the map:

- Speed is rendered as a small histogram.
- Altitude is rendered as a sparkline.
- The existing timeline remains the main interaction control.

The panel can be hidden with a downward swipe on the upper panel content. A restore pill remains at the bottom of the map. Tapping the pill or swiping it upward restores the full panel. Playback continues while hidden.

## Analysis Data Flow

- `HistoryMetricSample` maps `MiataruLocationData` to neutral analysis input with timestamp, coordinate, optional altitude, horizontal accuracy, and optional speed.
- `HistoryAnalyzer` is pure Swift and has no MapKit, SwiftUI, SwiftData, or network dependency.
- `HistoryAnalysisSource` prepares sorted samples once per loaded history and stores timestamps, derived speed, altitude, segment distance, and distance prefix sums for fast range analysis.
- `HistoryAnalysis` exposes time buckets, distance, max speed, altitude min/max, and valid bucket counts.

Stored history does not include vertical accuracy. Altitude values are used when present; the upload path stores altitude only when Core Location provided a valid altitude sample.

## Analysis Rendering

- `HistoryHistogramView` renders bucketed speed values with `Canvas`.
- `HistorySparklineView` renders bucketed altitude values with `Canvas`.
- Both tolerate empty arrays and nil bucket values.
- The playhead index maps through the analysis bucket time range, keeping histogram, sparkline, and timeline timestamp-driven.
- The histogram display range derives from the selected range so isolated speed spikes do not flatten normal movement.

## Panel Interaction

- The visible panel handle was removed after real-device testing.
- Hide gesture is attached to upper panel content, excluding the timeline range slider.
- The gesture no longer performs live dragging; it hides on gesture end to avoid per-frame SwiftUI state updates while graphs and map render.
- The restore pill is a direct SwiftUI view with explicit capsule hit shape, tap gesture, upward drag gesture, and accessibility action.
- The restore pill is not a nested `Button` plus competing drag gesture.
- The full panel schedules a lightweight 5-second auto-hide after direct map camera movement, marker selection, play/pause, or playback speed changes.
- Playback ticks, scrubber movement, and range-drag updates do not restart auto-hide.
- Quick range controls are compact glass segmented controls.
- Ranges shorter than the loaded span are shown; full range remains available.

## Playback Timing

Playback no longer assigns the same delay to every sample. Each step uses timestamp difference between the current sample and following sample divided by selected playback speed.

- Long gaps clamp to the previous maximum step delay, also divided by speed.
- Duplicate or non-increasing timestamps produce zero-delay steps instead of blocking playback.

## Performance Guardrails

History loads can contain up to 10,000 points. Normal panel updates avoid touching all raw points:

- Analysis preparation runs off the main actor.
- Per-range analysis caches by selected range and bucket count.
- Visible-history count uses timestamp index bounds.
- Downsampled map annotations cache by display range and limit.
- Polyline segments cache by display range and maximum gap.
- Marker color ratios use cached global timestamp range.
- Polyline gap detection uses local Haversine math instead of allocating `CLLocation` for every point.

The map still renders full route geometry for the selected range. Only point annotations are downsampled when many history entries are visible.

## Validation History

Validation included:

- App builds with `xcodebuild`.
- Focused `HistoryAnalyzerTests`.
- The analyzer suite covers empty history, one-point history, duplicate timestamps, derived speed, provided speed, speed outliers, bad horizontal accuracy, missing altitude, and 10,000-sample bucketing.
- Additional build validation after compact range picker, hidden-handle swipe behavior, auto-hide timer, and timestamp-paced playback changes.

Remaining follow-up:

- Add UI coverage for graph rendering and missing-data visual states.
- Add UI coverage for timeline/graph playhead sync, panel hide, and restore pill.
- Profile on a real device with Instruments if 10,000-point MapKit route rendering becomes a bottleneck.

