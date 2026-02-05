---
name: Turn Feedback Cues
overview: Add turn-by-turn haptic and sound feedback during reversed-route navigation mode, using NavigationOverlayKit symbols and the existing sound player so system silent mode is respected.
todos:
  - id: bind-symbol-feedback
    content: Bind NavigationOverlayViewModel.$symbol to feedback
    status: in_progress
  - id: add-haptic-helpers
    content: Expose light/heavy haptic helpers in Haptics
    status: pending
  - id: map-symbols-to-feedback
    content: Map NavigationInstruction.Symbol to left/right/straight cues
    status: pending
isProject: false
---

# Turn Feedback Cues Plan

## Scope and assumptions

- Feedback should only fire when the route is reversed and navigation mode is ON (double-tap enabled).
- We will map NavigationOverlayKit symbols to left/right/straight and use the existing `SoundEffectPlayer` so silent mode is respected.
- Sound file defaults (can be renamed later): `nav_left.caf`, `nav_right.caf`, `nav_straight.caf` under `miataru/Assets/sounds/`.

## Approach

- Bind to `NavigationOverlayViewModel.$symbol` with Combine and trigger feedback when the symbol changes.
- Gate feedback so it only fires when `isRouteReversed && isNavigationMode && isViewActive`.
- Add public haptic helpers for light/heavy impacts to differentiate left/right/straight.

## Files to update

- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices%20Views/iPhone_DeviceNavigationView.swift)`
  - Add feedback sound name constants.
  - Add a Combine subscription to `viewModel.$symbol` and store in `cancellables`.
  - In the sink, emit feedback only when `isRouteReversed && isNavigationMode && isViewActive`.
  - Map `NavigationInstruction.Symbol` to cues:
    - Left: `.slightLeft`, `.left`, `.sharpLeft`, `.uTurn`
    - Right: `.slightRight`, `.right`, `.sharpRight`
    - Straight: `.straight`, `.start`, `.arrive`, `.cross`, `.tunnel`, `.bridge`, `.stairs`, `.escalator`
  - Use `SoundEffectPlayer.shared.play(named:fileExtension:)` for the corresponding sound, and haptic impact per direction.
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/Haptic/Haptics.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/Haptic/Haptics.swift)`
  - Add `impactLight()` and `impactHeavy()` public helpers (reuse `performImpact`).

## Haptic mapping (initial default)

- Left: `impactLight()`
- Right: `impactMedium()`
- Straight: `impactHeavy()`

## Testing/verification

- Run the app, reverse a route, double-tap to enable navigation mode, and move along the route to verify:
  - Step change triggers exactly one sound + haptic.
  - Sounds respect silent mode (ambient session).
  - Forward (non-reversed) navigation remains unchanged.

## Notes

- If you prefer different sound names, we can replace the constants without changing logic.
- If you want more granular haptics (e.g., slight vs sharp), we can extend the mapping later.

