---
name: low-power-gate-effects
overview: Add a shared Low Power/scene-phase gate so shimmer and pulsing map effects only render when enabled in settings and not in Low Power Mode.
todos:
  - id: add-animation-gate
    content: Add shared animationsAllowed environment gate.
    status: completed
  - id: gate-shimmer-pulse
    content: Gate shimmer and pulsing via animationsAllowed.
    status: completed
  - id: audit-other-animations
    content: Disable remaining animations/transitions in LPM.
    status: completed
  - id: verify-behavior
    content: Verify LPM disables all animations.
    status: completed
isProject: false
---

# Low Power Mode Gating Plan

## Summary

Implement a shared animation-permission gate (based on Low Power Mode + scene phase) and apply it to shimmer, pulsing, and all other animations/transitions. Keep existing settings checks (e.g., `settings.pulsingMapMarkers`) so effects only render when enabled and the device is not in power save.

## Key Files

- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/Shimmer.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/Shimmer.swift)`
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/PulsingAccuracyCircle.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/PulsingAccuracyCircle.swift)`
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/MapHelpers.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Common/Map/MapHelpers.swift)` (or another shared file for the global animation gate)
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceMapView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices%20Views/iPhone_DeviceMapView.swift)` and all other map views using animations

## Plan

1. **Create a shared “animations allowed” environment gate**
  - Extend the existing Low Power Mode listener (currently in `ShimmerGate`) into a reusable environment value such as `animationsAllowed` that encodes: `scenePhase == .active && !isLowPowerMode`.
  - Keep user settings checks separate so per-feature toggles still work.
  - Place the environment key in a shared location (either `Shimmer.swift` or a small helper file under `views/Common/Map/`) so any view can access it.
2. **Wire pulsing to the gate**
  - In `PulsingAccuracyCircle`, read `animationsAllowed` and skip rendering entirely when false (as requested).
  - This ensures pulsing never animates during Low Power Mode even if the settings toggle is on.
3. **Keep settings as the primary toggle**
  - Leave existing settings checks (`settings.pulsingMapMarkers`) intact at call sites in:
    - `iPhone_DeviceMapView`, `iPad_DeviceMapView`, `iPhone_GroupMapView`, `iPad_GroupMapView`, `iPhone_DeviceNavigationView`, and debug view.
  - Combine the settings check with `animationsAllowed` so effects render only when both are true.
4. **Update shimmer to use the shared gate**
  - Replace or refactor `ShimmerGate` so it sets `animationsAllowed`.
  - Ensure `shimmering(active:)` still respects `active` and the global gate.
5. **Gate all other animations and transitions**
  - Audit view files for `.animation(..., value:)`, `.transition(...)`, and `withAnimation { ... }`.
  - Replace `withAnimation` blocks with conditional logic: animated when `animationsAllowed`, immediate state change otherwise.
  - For `.animation`, set it to `nil` when `animationsAllowed == false` to disable the transition.
  - For repeating animations (e.g., pulsing, shimmer), conditionally render or provide a static fallback.
6. **Verify behavior**
  - With Low Power Mode on: all animations/transitions are disabled; pulsing/shimmer are hidden.
  - With Low Power Mode off and `pulsingMapMarkers` enabled: pulsing/shimmer return.
  - With `pulsingMapMarkers` disabled: no pulsing/shimmer regardless of Low Power Mode.

## Implementation Todos

- Define shared environment key for `animationsAllowed` (Low Power + scene phase).
- Use the shared gate inside `Shimmer` and `PulsingAccuracyCircle`.
- Audit all SwiftUI animations/transitions and conditionally disable them.
- Confirm all pulsing call sites still guard by `settings.pulsingMapMarkers` and now respect the gate.

