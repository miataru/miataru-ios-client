# Focused Navigation Local Location + Heading Refresh Fix (2026-03-03)

## Problem
In focused navigation mode (double-tap, reversed route `user -> selected device`), two issues were visible, especially in Simulator:

1. The own-device marker/camera updates could feel stale and appear tied to server-driven updates.
2. The heading arrow updated, but often jittered noticeably.

## Root Cause
Two implementation details combined:

1. The navigation view primarily reacted to `currentLocation` and cache updates.  
   `currentLocation` is sensitivity-filtered, so small/rapid foreground movement updates could be dropped.
2. Heading fallback behavior could still switch too often to raw course behavior when heading quality was poor, causing visible jitter.

## Changes
### 1) Raw local location stream for immediate UI updates
File: `miataru/miataru/LocationManagers/LocationManager.swift`

- Added `latestRawLocation` as a published property carrying the newest CLLocation update without sensitivity filtering.
- Set `latestRawLocation` immediately in `didUpdateLocations`.

### 2) Focused navigation now consumes local raw location first
File: `miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`

- Added `effectiveUserLocation = latestRawLocation ?? currentLocation`.
- Rewired focused-navigation camera, speed, step/ETA overlay, and marker updates to use `effectiveUserLocation`.
- Added `.onReceive(locationManager.$latestRawLocation)` so focused navigation updates on every local raw update.

### 3) Smoother heading behavior
File: `miataru/miataru/LocationManagers/LocationManager.swift`

- In `didUpdateHeading`, if heading accuracy is valid: continue using smoothed blended heading.
- If heading accuracy is invalid: fall back to **smoothed** course only (no abrupt unsmoothed heading behavior).
- Removed setting `isHeadingValid = true` from course-only fallback in `didUpdateLocations`; validity now reflects actual heading sensor quality.

File: `miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`

- `currentFollowHeading()` now prioritizes smoothed `userHeading` consistently, using course as a fallback.
- Arrow visibility in `UserHeadingAnnotationView` is now based on the same reliability model used by follow-camera heading decisions.

## Expected Behavior
- In focused navigation, own-device motion should follow local updates immediately instead of appearing server-timed.
- The heading arrow should update continuously and more smoothly, with reduced simulator jitter.

## Verification
- Build check:
  - `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Result: `BUILD SUCCEEDED`
