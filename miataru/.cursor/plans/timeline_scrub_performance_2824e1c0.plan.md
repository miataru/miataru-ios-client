---
name: Timeline Scrub Performance
overview: Reduce scrubbing lag in history map with 1000+ items by cutting per-gesture work and limiting map/UI recomputations.
todos:
  - id: vm-caching
    content: Add view model with cached slices/binary search for history data
    status: completed
  - id: debounce-side-effects
    content: Debounce scrub/selection changes before region updates and disable animations while dragging
    status: completed
    dependencies:
      - vm-caching
  - id: map-downsample
    content: Draw path overlay and downsample annotations to selected + sparse points
    status: completed
    dependencies:
      - vm-caching
---

# Improve Timeline Scrub Performance



- Tighten data access in `[miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryMapView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryMapView.swift) `by introducing a small view model that precomputes sorted timestamps, provides binary-search slicing for the selected range, and replaces `entryClosest`/`visibleHistory` O(n) scans with O(log n) + slice caching.
- Throttle expensive side effects during scrubbing: debounce `scrubTimestamp`/`selectedRange` reactions before calling `updateRegion`/`focusOnScrubbedEntry`, and skip animations while dragging to avoid repeated camera jumps.