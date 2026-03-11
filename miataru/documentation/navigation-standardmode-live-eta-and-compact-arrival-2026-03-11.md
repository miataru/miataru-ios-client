# Navigation Standard Mode Live ETA + Compact Arrival Display (2026-03-11)

## Problem
In reversed navigation (`user -> selected device`), the route summary behaved inconsistently:

- In focused double-tap mode, ETA/arrival was continuously updated.
- In non-focused/normal navigation mode, ETA/arrival was not continuously refreshed.
- On compact iPhones, the bottom accessory text became too long because it included both a localized prefix (`ETA:`/`Ankunft:`) and, in short routes, second-level duration granularity.

## Changes
Updated `miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`:

- Relaxed live-summary guard in `updateLiveNavigationRouteSummary()`:
  - Before: live updates only when `isNavigationMode == true`.
  - After: live updates for all reversed navigation (`!isRouteFromDeviceToUser`), including normal mode.
- Simplified duration formatting in `formattedDuration(_:)`:
  - Before: `< 1h` used `.minute + .second`.
  - After: always `.hour + .minute` (no seconds).

Updated `miataru/views/Common/BottomAccessoryModifier.swift`:

- Simplified arrival segment rendering in `routeSummaryText()`:
  - Before: `<arrival prefix>: <time>` (for example `ETA: 14:32` / `Ankunft: 14:32`).
  - After: `<time>` only (for example `14:32`).

## Resulting Behavior
- Reversed navigation now keeps ETA/distance/arrival time in sync in both normal and focused modes.
- Route duration text is shorter and no longer shows seconds.
- Bottom accessory route info is more compact on small iPhones because arrival time is displayed without `ETA:`/`Ankunft:` prefix.

## Verification
- Built app target successfully:
  - `xcodebuild -project miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS' build`
  - Result: `** BUILD SUCCEEDED **`
