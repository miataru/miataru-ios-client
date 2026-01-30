---
name: Navigation Overlay Mode
overview: Add NavigationOverlayKit to show turn-by-turn instructions when navigation is switched to “from current device → other device”, updating the overlay in sync with route recalculation and live location updates, and document the change.
todos:
  - id: overlay-wireup
    content: Wire overlay view/model into iPhone_DeviceNavigationView
    status: pending
  - id: sync-updates
    content: Update overlay on route and location changes
    status: pending
  - id: docs-changelog
    content: Update CHANGELOG and feature docs
    status: pending
isProject: false
---

## Implementation plan

### 1) Wire the overlay into the navigation view

- In `iPhone_DeviceNavigationView` add a `NavigationOverlayViewModel` state object and create/update it when a route is calculated and the mode is “current device → other device” (`isRouteReversed == false`).
- Place the overlay at the top of the map overlay stack in `mapWithModifiers` so it appears above the map but below other system overlays. This lines up with the existing overlay structure and your UI preference.
- Ensure the overlay is hidden when:
  - `isRouteReversed == true` (device → user mode)
  - `route == nil` (no route)
  - Navigation has been auto-stopped (route cleared)

### 2) Keep instructions in sync with live location

- On each location update (`locationManager.$currentLocation`) update the overlay view model’s current step based on the user’s position on the route.
- When the route is recalculated (manual reload, auto-update, or transport type change), reset the overlay view model with the new `MKRoute` and restart at step 0.
- If the route is swapped via the toolbar button, recreate the overlay view model only when switching to `isRouteReversed == false`.

### 3) Handle edge cases and side effects

- Ensure that cached routes still populate the overlay view model when the cached route is applied, not only when a new network route is fetched.
- When `stopNavigation()` clears the route, also clear/hide the overlay to avoid stale instructions.
- Confirm the overlay responds correctly to `mapUpdateInterval` auto-updates and to mutual navigation changes (no changes required, but verify no overlay conflicts).

### 4) Documentation and changelog

- Update `[CHANGELOG.md](/Users/bietiekay/code/miataru-ios-app/miataru/CHANGELOG.md)` with the new “navigation instructions overlay in user→device mode”.
- Update `[APP_FEATURES.md](/Users/bietiekay/code/miataru-ios-app/miataru/APP_FEATURES.md)` (and/or `[APP_STORE_DESCRIPTION.md](/Users/bietiekay/code/miataru-ios-app/miataru/APP_STORE_DESCRIPTION.md)` if you want it marketed) with a short note about in-app navigation instructions when routing from the current device to the selected device.

### Key code touchpoints

- `iPhone_DeviceNavigationView`: add overlay view model, show overlay conditionally, update it when route changes, and update instruction step on location changes.
  - Current route direction toggle and routing logic are already in place and will be reused:

```
640:648:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
        if isRouteReversed {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: device))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: user))
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: user))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: device))
        }
```

## Assumptions

- The overlay should only show for “current device → other device” mode (`isRouteReversed == false`).
- NavigationOverlayKit is already added via SPM and available to the app target.

## Testing

- Manual test: start navigation to a device, switch direction to “current device → other device”, confirm overlay appears with instructions and updates as you move.
- Verify: switch back to device→user hides overlay; route recalculation updates instructions; cached routes show overlay without requiring a fresh fetch.

