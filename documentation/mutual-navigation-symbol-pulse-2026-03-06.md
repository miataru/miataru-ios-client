# Mutual Navigation Symbol Pulse (2026-03-06)

## Problem
The mutual-navigation indicator was visible but static, making the active reciprocal-navigation state less noticeable in compact route-info overlays.

## Change
Added a repeating pulse animation to the mutual-navigation SF Symbol in both UI locations:

- `miataru/miataru/views/Common/BottomAccessoryModifier.swift`
- `miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`

Implementation details:

- Applied `.symbolEffect(.pulse, options: .repeating, isActive: ...)` to `person.line.dotted.person.fill`.
- Added a shared activation gate in each view:
  - animation only runs when `animationsAllowed` is `true`
  - and `settings.pulsingMapMarkers` is enabled
- Kept existing accessibility label (`mutual_navigation_active`) unchanged.

## Expected Behavior
- During mutual navigation, the indicator symbol pulses continuously.
- If app-wide animations are disabled (e.g., low power/background gating) or pulsing markers are disabled, the symbol remains static.
- Accessibility behavior remains unchanged.

## Verification
- Confirmed pulse effect is present in top route-info overlay (non-iOS-26 path).
- Confirmed pulse effect is present in bottom accessory route-info (iOS 26 path).
- Confirmed both use the same activation gate (`animationsAllowed && settings.pulsingMapMarkers`).
