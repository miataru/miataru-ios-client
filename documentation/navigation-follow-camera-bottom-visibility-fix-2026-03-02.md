# Navigation Follow Camera Bottom Visibility Fix (2026-03-02)

## Problem
In focused navigation mode (double-tap, reversed route `user -> selected device`), the own-device marker could end up on the very bottom edge or briefly outside the visible map area after the initial route overview zoom.

This was most visible at low speed or standstill. At higher speed the marker usually moved back into a better position.

## Root Cause
Two effects combined:

1. Follow-camera look-ahead in `iPhone_DeviceNavigationView` was relatively aggressive for low-speed scenarios.
2. Heading selection could still push the camera center forward even when heading quality was not reliable enough for stable low-speed framing.

## Change
File: `miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`

- Reduced look-ahead bounds:
  - `navigationLookAheadMinDistance`: `70 -> 50`
  - `navigationLookAheadMaxDistance`: `360 -> 320`
- Improved follow-heading fallback selection:
  - Prefer `userHeading` only when `isHeadingValid`.
  - Prefer `course` only when `course >= 0` and `speed >= 1.0`.
  - Use safer fallbacks when neither is reliable.
- Made look-ahead adaptive to heading reliability:
  - Reliable heading: use moderate ratio.
  - Unreliable heading: clamp look-ahead significantly harder.

## Expected Behavior After Fix
- In focused navigation mode, the own-device marker stays visible and stable in the lower map area directly after zoom-in.
- Manual re-centering should no longer be needed to recover from bottom-edge/off-screen placement in low-speed cases.
- At higher speed, forward visibility still increases, but with less abrupt bottom displacement.

## Verification
- Build check:
  - `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Result: `BUILD SUCCEEDED`

