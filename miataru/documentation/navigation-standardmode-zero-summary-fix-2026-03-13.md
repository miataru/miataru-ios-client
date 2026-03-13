# Navigation Standard Mode Zero Summary Fix (2026-03-13)

## Problem
In standard navigation (`device -> user`), the route summary briefly showed the correct values after route calculation and then immediately collapsed to `0 km / 0 min`.

The issue was visible on both iPhone and iPad. Focused double-tap navigation was unaffected because it uses the reversed-route (`user -> device`) live-summary path.

## Root Cause
`updateLiveNavigationRouteSummary()` estimated remaining time for standard navigation from `lastRouteDeviceTimestamp` / `lastRouteUserTimestamp`.

When the selected device's last server sample was already older than the route ETA, the next per-second live refresh treated the route as already "finished" and clamped remaining duration and distance to zero, even though the route had just been calculated and rendered.

## Changes
Updated `miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`:

- Added `routeSummarySeedDate` as dedicated state for the currently displayed standard-navigation route summary.
- Set `routeSummarySeedDate = Date()` whenever a fresh route or a valid cached route is applied to the view.
- Cleared `routeSummarySeedDate` when navigation state is reset, direction changes, or navigation is stopped.
- Changed the standard-navigation branch in `updateLiveNavigationRouteSummary()` to count down from `routeSummarySeedDate` first, falling back to legacy timestamps only if needed.

## Resulting Behavior
- Standard navigation on iPhone and iPad keeps the initially correct ETA/distance instead of snapping to zero on the next live tick.
- Cached routes behave consistently with freshly calculated routes.
- Focused/double-tap navigation remains unchanged.

## Verification
- Built app target successfully:
  - `xcodebuild -project miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS' build`
  - Result: `** BUILD SUCCEEDED **`
