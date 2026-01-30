---
name: Playback respects manual zoom
overview: "During device-history playback, if the user manually zooms the map, that zoom level (span) becomes the locked playback span: playback continues to animate the map center to each timeline entry, but no longer auto-zooms to the previous/current/next points until playback stops/pauses."
todos:
  - id: detect-user-zoom
    content: Add region tracking + suppression window + user zoom detection via `.onMapCameraChange` in `iPhone_DeviceHistoryMapView`.
    status: completed
  - id: lock-span-during-playback
    content: Store `playbackLockedSpan` when user zooms during playback; clear it when playback starts/stops/pauses.
    status: completed
  - id: follow-center-only
    content: Update `focusOnEntry` to keep animating the center while using the locked span (skip fit-to-bounds zoom) when `playbackLockedSpan` is set.
    status: completed
---

# Playback respects manual zoom (history map)

## Goal

- While **playback is running** in the device history map, if the user **pinch-zooms** the map, that **span is adopted** and playback should **stop auto-zooming**.
- Playback should still **follow/center** (animated) on each new timeline location.
- The override is **local to the history view** and **resets when playback stops/pauses**.

## Where the current auto-zoom happens

- In [`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices%20Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift):
- `startPlayback()` calls `focusOnEntry(entry, within: entries)` every step.
- `focusOnEntry` currently builds `contextEntries = previous/current/next` and calls `updateRegion(... useDefaultZoom: false)` which computes a fit-to-bounds span.

## Implementation approach

- Add a **playback span lock** that is set when the user zooms during playback.
- Detect user zoom via `.onMapCameraChange(frequency: .continuous)` on the SwiftUI `Map(position: $cameraPosition)`.
- Prevent false positives from our own `updateRegion` animations by introducing a short **suppression window** whenever we set `cameraPosition` programmatically.

## Concrete changes

- Update [`iPhone_DeviceHistoryMapView.swift`](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices%20Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift):
- **State**:
- `@State private var currentRegion: MKCoordinateRegion?` (last observed region from camera changes)
- `@State private var playbackLockedSpan: MKCoordinateSpan?` (nil unless user zoomed during playback)
- `@State private var suppressUserCameraChangeDetectionUntil: Date?` (ignore camera change events until this time)
- **Camera change handler** (`.onMapCameraChange`):
- Always update `currentRegion`.
- Detect `zoomChanged` by comparing `currentRegion?.span` vs `context.region.span` with small deltas.
- If `isPlaying && zoomChanged` and **not** within suppression window, set `playbackLockedSpan = context.region.span`.
- **Programmatic update suppression**:
- In `updateRegion(animated:using:useDefaultZoom:)`, before writing `cameraPosition`, set `suppressUserCameraChangeDetectionUntil = Date().addingTimeInterval(...)` (slightly longer for animated).
- **Use locked span during playback**:
- In `focusOnEntry(_:within:)`: if `isPlaying` and `playbackLockedSpan != nil`, set the region to:
- `center = entry.coordinate`
- `span = playbackLockedSpan`
- and animate the camera update
- (skip the previous/current/next fit-to-bounds span computation)
- **Reset behavior**:
- In `startPlayback()`: clear `playbackLockedSpan = nil`.
- In `stopPlayback()` / `togglePlayback()` pause path: clear `playbackLockedSpan = nil`.

## Test plan (manual)

- Start playback and observe current behavior (auto-zoom to prev/current/next).
- While playback is running:
- Pinch-zoom in/out.
- Confirm subsequent playback steps:
- **Center continues to animate** to each new pin.
- **Zoom level stays fixed** at the user-selected span.
- Pause playback:
- Confirm `playbackLockedSpan` resets (next playback start resumes auto-zoom until user zooms again).

## Notes / non-goals

- Do **not** update `SettingsManager.shared.mapZoomLevel` from this interaction (local only).
- This change targets the history map view (there is no separate iPad history map view in the current codebase).