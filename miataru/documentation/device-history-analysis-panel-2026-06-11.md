# Device History Analysis Panel - 2026-06-11

## Summary

The iPhone device history map now keeps the existing route, annotation, playback, selected range, and timeline behavior, and extends the lower history panel with compact speed and altitude analysis. The analysis is deliberately secondary to the map: speed is rendered as a small histogram, altitude as a sparkline, and the existing timeline remains the main interaction control.

The panel can be hidden with a downward swipe on its handle. While hidden, a small restore pill remains at the bottom of the map. Tapping the pill or swiping it upward restores the full panel. Playback continues while the panel is hidden and does not force the panel open again.

## Data Flow

- `HistoryMetricSample` maps existing `MiataruLocationData` into a neutral analysis input with timestamp, coordinates, optional altitude, horizontal accuracy, and optional speed.
- `HistoryAnalyzer` is pure Swift and has no MapKit, SwiftUI, SwiftData, or network dependency.
- `HistoryAnalysisSource` prepares sorted samples once for a loaded history and keeps timestamps, derived speed, altitude, segment distance, and distance prefix sums for fast per-range analysis.
- `HistoryAnalysis` exposes time buckets, distance, max speed, altitude min/max, and valid bucket counts for the UI.

Stored history data currently does not include vertical accuracy. Altitude values are therefore used when present; the upload path already stores altitude only when Core Location provided a valid altitude sample.

## Rendering

- `HistoryHistogramView` renders bucketed speed values with `Canvas`.
- `HistorySparklineView` renders bucketed altitude values with `Canvas`.
- Both views tolerate empty arrays and `nil` bucket values without crashing.
- The current playhead index is mapped through the analysis bucket time range, so histogram, sparkline, and timeline share the same timestamp-driven playhead.
- The histogram uses a display range derived from the current selected range so isolated speed spikes do not flatten normal movement.

## Interaction

The hide gesture is attached to the panel handle only. It no longer performs live panel dragging; the swipe is recognized on gesture end and then hides the panel. This avoids per-frame SwiftUI state updates while the map and analysis graphs are visible.

The restore pill is implemented as a direct SwiftUI view with an explicit capsule hit shape, tap gesture, upward drag gesture, and accessibility action. It is not a nested `Button` plus competing drag gesture, which keeps the hidden-state restore path reliable inside the map overlay.

## Performance Guardrails

History loads can contain up to 10,000 points. The implementation avoids touching all raw points during normal panel updates:

- Analysis preparation runs off the main actor after history load.
- Per-range analysis is cached by selected time range and bucket count.
- Visible-history count uses timestamp index bounds instead of constructing an array.
- Downsampled map annotations are cached by display range and limit.
- Polyline segments are cached by display range and maximum gap.
- Marker color ratios use the cached global timestamp range instead of scanning the full history per annotation.
- Polyline gap detection uses a local Haversine calculation instead of allocating `CLLocation` objects for every point.

The map still renders full route geometry for the selected range. Only point annotations are downsampled when many history entries are visible.

## Validation

- `xcodebuild build -project miataru/miataru.xcodeproj -scheme miataru -destination id=9701FE64-5BE0-4377-8E82-14C43F80E6C9`
- `xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination id=9701FE64-5BE0-4377-8E82-14C43F80E6C9 -only-testing:miataruTests/HistoryAnalyzerTests`

The focused analyzer suite covers empty history, one-point history, duplicate timestamps, derived speed, provided speed, speed outliers, bad horizontal accuracy, missing altitude, and 10,000-sample bucketing.

## Remaining Follow-Up

- Add UI coverage for graph rendering and missing-data visual states.
- Add UI coverage for timeline, graph playhead sync, panel hide, and restore pill behavior.
- Profile on a real device with Instruments if further 10,000-point route rendering bottlenecks appear in MapKit itself.
