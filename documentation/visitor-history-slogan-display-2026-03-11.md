# Visitor History Device Slogan Display (2026-03-11)

## Problem
Unknown visitor rows in the device list already display a device slogan (when available), but the visitor history rows did not consistently show slogans in the `this-device` context.

## Change
Updated visitor history row rendering and slogan fetching in:

- `miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift`

Implementation details:

- Added slogan rendering for known-device visitor rows when a cached slogan exists.
- Removed the unknown-device-only guard in `fetchSloganIfNeeded()`, so visitor rows can refresh slogans for all visitor entries.
- Kept existing refresh throttling via `DeviceSloganCacheStore.refreshSloganIfStale(..., minimumRefreshInterval: 300)`.

## Expected Behavior
- Visitor history entries in `this-device` now show the device slogan when available.
- Unknown visitor behavior remains unchanged (slogan still preferred as primary subtitle).
- Known visitor rows now also surface slogan information without losing existing last-seen/distance/location details.

## Verification
- Build succeeded with:
  - `xcodebuild -project miataru.xcodeproj -scheme miataru -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO`
- Confirmed the slogan line is rendered in known visitor rows and slogan fetch is no longer restricted to unknown visitors.
