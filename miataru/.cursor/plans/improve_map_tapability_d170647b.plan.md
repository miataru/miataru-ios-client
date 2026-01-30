---
name: Improve Map Tapability
overview: Add tap-friendly device action UI and overlapping-device picker on maps for iPhone/iPad.
todos:
  - id: tap-hook
    content: Add tap gesture to annotation hit area and show action sheet
    status: completed
  - id: overlap-picker
    content: Detect nearby devices and show picker when overlapping
    status: completed
    dependencies:
      - tap-hook
  - id: hitbox-tuning
    content: Enlarge/adjust transparent hitbox around markers
    status: completed
  - id: state-wiring
    content: Add selection/action sheet state and reuse handlers
    status: completed
    dependencies:
      - tap-hook
  - id: a11y-polish
    content: Add accessibility labels/hints for tappable areas and picker
    status: completed
    dependencies:
      - tap-hook
      - overlap-picker
---

# Make Device Map Annotations Tap-Friendly

## Summary

Implement tap-driven device action UI on map annotations, keep long-press context menus as fallback, and add a nearby-device picker when multiple markers overlap. Touch targets will be enlarged and consistent across iPhone/iPad map views.

## Scope & Files

- iPhone device map: [`miataru/views/iPhone/Devices Views/iPhone_DeviceMapView.swift`](miataru/views/iPhone/Devices%20Views/iPhone_DeviceMapView.swift)
- iPad device map: [`miataru/views/iPad/Devices Views/iPad_DeviceMapView.swift`](miataru/views/iPad/Devices%20Views/iPad_DeviceMapView.swift)
- (If shared helper needed) Common map helpers folder, or a small utility in the same files for distance-based grouping.

## Plan

1. Add tap entry point

- On each device annotation wrapper, add `.onTapGesture` to the existing transparent hit area to open a new action surface (confirmationDialog or bottom sheet) mirroring current context menu actions (edit, navigation, history).
- Keep `.contextMenu` for iPad/Mac as fallback/secondary.

2. Resolve overlapping devices

- Detect nearby annotations within a small distance threshold when a tap occurs (using coordinate distance on the map region). If more than one device is within threshold, present a selection sheet/list of device names to disambiguate; otherwise go straight to actions for the single device.

3. Enlarge and align tap targets

- Increase the transparent hit area around each marker (e.g., from 80x120 to ~120x160) and center it over the marker while preserving `.contentShape(Rectangle())` for reliable taps.

4. Action surfaces and localization

- Use `confirmationDialog` (iPhone) and `popover/sheet` (iPad) to show actions with existing localized strings; no new strings expected. Reuse the same action handlers currently in the context menus.

5. State & data plumbing

- Add lightweight state: `selectedDeviceID`, `overlappingDevices` list, booleans for showing action sheet and selection sheet. Ensure state resets on dismiss.

6. Accessibility & UX polish

- Add accessibility labels/hints to the hit areas and selection list entries. Ensure focus order is intact and actions are reachable via VoiceOver.

## Implementation Todos

- `tap-hook`: Add tap gesture to device annotation hit area and show action sheet.