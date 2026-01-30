---
name: history-map-refactor
overview: Refactor and modularize the device history map view for clarity and reuse
todos:
  - id: split-viewmodel
    content: Extract DeviceHistoryMapViewModel to its own file
    status: completed
  - id: extract-overlay
    content: Move DeviceHistoryTimelineOverlay to separate file
    status: completed
    dependencies:
      - split-viewmodel
  - id: extract-slider
    content: Move TimelineRangeSlider to separate file
    status: completed
    dependencies:
      - extract-overlay
  - id: clean-main-view
    content: Simplify main view after extractions
    status: completed
    dependencies:
      - extract-slider
---

# Refactor iPhone Device History Map

## Goals

- Improve readability and separation of concerns for the history map screen.
- Extract reusable timeline overlay/slider components and view model into their own files following MVVM and file naming rules.
- Add light simplifications and guards to reduce nested logic.

## Proposed Changes

- **Split view model**: Move `DeviceHistoryMapViewModel` into `[miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryMapViewModel.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryMapViewModel.swift)` and keep it focused on data prep, caching, and helpers (downsampling, segments, bounds).
- **Extract overlay**: Move `DeviceHistoryTimelineOverlay` into `[miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryTimelineOverlay.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceHistoryTimelineOverlay.swift)` so it can be reused and independently tested.
- **Extract slider**: Move `TimelineRangeSlider` into `[miataru/views/iPhone/Devices Views/iPhone_TimelineRangeSlider.swift](miataru/views/iPhone/Devices Views/iPhone_TimelineRangeSlider.swift)` and keep gesture/geometry logic contained.
- **Local helpers**: Keep lightweight helpers (color/date formatters, selection helpers) in the main view or a small extension file if needed, removing duplication and clarifying data flow.
- **Tighten state handling**: Clarify playback/scrub state updates (e.g., guard against redundant playback restarts, cancel tasks on disappear) while preserving behavior.

## Todos

- split-viewmodel: Extract `DeviceHistoryMapViewModel` to its own Swift file with imports and privacy kept consistent.