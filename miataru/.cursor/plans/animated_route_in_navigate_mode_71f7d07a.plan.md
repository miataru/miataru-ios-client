---
name: Animated route in navigate mode
overview: Integrate AnimatedPolylineKit so the navigation route shows a default moving-highlight animation along the full route, in the correct routing direction, by adding an overlay MKMapView that stays in sync with the SwiftUI Map and draws only the animated overlay.
todos:
  - id: animated-overlay-config
    content: "Define AnimatedPolylineConfiguration (demo-style: RouteStyle.remaining, patchLength 0.1, duration 2.5, easeIn/easeOut, .startToEnd) in the new representable or shared helper."
    status: pending
  - id: create-overlay-representable
    content: "Create AnimatedRouteOverlayView (UIViewRepresentable): MKMapView with isUserInteractionEnabled = false, region from parent, AnimatedPolylineOverlay + AnimatedPolylineAnimationDriver (loop true), coordinator as delegate with rendererFor returning AnimatedPolylineRenderer; add/remove overlay and driver when routePolyline changes."
    status: pending
  - id: integrate-navigation-view
    content: In iPhone_DeviceNavigationView wrap baseMapView in ZStack; add overlay representable on top passing currentRegion and route?.polyline (and map type if needed); ensure overlay covers map frame.
    status: pending
  - id: edge-cases-lifecycle
    content: "Handle route/direction change: overlay receives new routePolyline or nil; tear down previous driver/overlay and create new one when route changes. Verify AnimatedPolylineKit import and app target link."
    status: pending
isProject: false
---

# Animated polyline on navigation route (full route)

## Goal

- When a route exists in navigate mode, show the same style of animation as the [AnimatedPolylineKit demo](https://github.com/bietiekay/AnimatedPolylineKit) (moving highlight along the route).
- Animate along the **full route** (the whole route is already drawn; the overlay shows the moving highlight on that same path).
- Animate in the **correct routing direction** (start → end; the route polyline is already in source→destination order).

## Constraint

AnimatedPolylineKit uses `MKOverlay` and `MKOverlayRenderer`, which require **MKMapView**. SwiftUI’s `Map` does not support custom overlay renderers, so the animated overlay cannot be drawn directly on the existing SwiftUI Map.

## Recommended approach: overlay MKMapView (non-interactive, synced)

Keep the existing SwiftUI `Map` as the main, interactive map. Add a **second** map via a new `UIViewRepresentable` that:

- Renders the same region/style as the main map and draws only the animated overlay on top (so it looks like one map).
- Is **non-interactive** (`isUserInteractionEnabled = false`) so all gestures go to the SwiftUI Map.
- Receives **region** from the parent (already available as `currentRegion` from `.onMapCameraChange`) and applies it in `updateUIView` so the overlay map stays aligned with the main map.

Flow:

1. User interacts with the SwiftUI Map → `mapPosition` and `currentRegion` update.
2. Parent passes `currentRegion` (and map style if needed) into the overlay representable.
3. Overlay representable updates the overlay MKMapView’s region and adds/removes the `AnimatedPolylineOverlay` for the **full route** polyline; it uses `AnimatedPolylineRenderer` and `AnimatedPolylineAnimationDriver` (same config as the demo).

Result: one logical map (SwiftUI Map) with a thin overlay layer that only draws the animated overlay. No change to annotations, route progress (done/todo/ghost), or mutual navigation drawing on the main Map.

## Implementation todos

- **animated-overlay-config**: Define AnimatedPolylineConfiguration (demo-style: RouteStyle.remaining, patchLength 0.1, duration 2.5, easeIn/easeOut, .startToEnd) in the new representable or shared helper.
- **create-overlay-representable**: Create AnimatedRouteOverlayView (UIViewRepresentable): MKMapView with isUserInteractionEnabled = false, region from parent, AnimatedPolylineOverlay + AnimatedPolylineAnimationDriver (loop true), coordinator as delegate with rendererFor returning AnimatedPolylineRenderer; add/remove overlay and driver when routePolyline changes.
- **integrate-navigation-view**: In iPhone_DeviceNavigationView wrap baseMapView in ZStack; add overlay representable on top passing currentRegion and route?.polyline (and map type if needed); ensure overlay covers map frame.
- **edge-cases-lifecycle**: Handle route/direction change: overlay receives new routePolyline or nil; tear down previous driver/overlay and create new one when route changes. Verify AnimatedPolylineKit import and app target link.

## Implementation steps

### 1. Animated overlay configuration

- Reuse the demo's configuration (e.g. in the new representable or a shared helper): same `AnimatedPolylineConfiguration` as [ContentView.swift](Libraries/AnimatedPolylineKit-main/Sample/AnimatedMapPolyline/ContentView.swift) (blue `underlyingColor`, `patchLength: 0.1`, `patchWhiteBandFraction: 0.55`, `patchHighlightBlend: 0.7`, `direction: .startToEnd`, `duration: 2.5`, `startEasing: .easeIn`, `endEasing: .easeOut`, `lineWidth`, `lineCap`, `lineJoin`). Prefer `RouteStyle.remaining` for `underlyingColor` so it matches the app's route color.

### 2. New UIViewRepresentable: animated route overlay

- **Inputs**: `region: MKCoordinateRegion?`, `routePolyline: MKPolyline?` (the full route polyline), and optionally map type (so the overlay map matches the main map's style)

’s [ContentView.swift](Libraries/AnimatedPolylineKit-main/Sample/AnimatedMapPolyline/ContentView.swift) (blue `underlyingColor`, `patchLength: 0.1`, `patchWhiteBandFraction: 0.55`, `patchHighlightBlend: 0.7`, `direction: .startToEnd`, `duration: 2.5`, `startEasing: .easeIn`, `endEasing: .easeOut`, `lineWidth`, `lineCap`, `lineJoin`). Prefer `RouteStyle.remaining` for `underlyingColor` so it matches the app’s route color.
 “animated route overlay”

- **Inputs**: `region: MKCoordinateRegion?`, `routePolyline: MKPolyline?` (the full route polyline), and optionally map type (so the overlay map matches the main map’s style).
- **Behavior**:
  - When `routePolyline` is non-nil: create `AnimatedPolylineOverlay(polyline: routePolyline, configuration: config)`, add it to the overlay MKMapView, and start `AnimatedPolylineAnimationDriver` (loop: true), binding `driver.$progress` to `overlay.progress` on the main queue (same pattern as the demo).
  - When `routePolyline` is nil or route is cleared: remove the overlay and stop the driver.
  - In `updateUIView`, set the overlay map’s `region` from `region` and add/remove the animated overlay as above; avoid recreating the driver every update (e.g. keep driver/overlay in the coordinator and only recreate when the polyline identity or route changes).
- **Renderer**: In the delegate, `rendererFor overlay` → if `overlay is AnimatedPolylineOverlay`, return `AnimatedPolylineRenderer(overlay: overlay)`; otherwise fall back to a default renderer (you only add the animated overlay from this view, so this is sufficient).
- **Interaction**: Set the overlay MKMapView’s `isUserInteractionEnabled = false` so touches pass through to the SwiftUI Map underneath.
- **Lifecycle**: On disappear or when the route is cleared, stop the driver and remove the overlay to avoid leaks and unnecessary work.

### 3. Integrate into [iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)

- **State**: No extra state needed; pass `route?.polyline` when the overlay is shown.
- **Layout**: In the same place where `baseMapView` is used (inside `mapWithModifiers`), wrap the map in a `ZStack`: bottom layer = current `baseMapView` (unchanged); top layer = the new overlay representable with the same frame (e.g. `.background` or overlay alignment so it exactly covers the map). Pass `currentRegion` and `route?.polyline` (and map type if the overlay map is styled).
- **When to show**: Pass a non-nil polyline when `route != nil` (e.g. `route?.polyline`). Direction is already encoded in the polyline (start→end), so use `direction: .startToEnd` in the config.

### 4. Edge cases

- **Route or direction change**: When `route` or `isRouteReversed` changes, the overlay representable receives the new `routePolyline` (or nil); ensure it tears down the previous driver/overlay and creates a new one for the new route.
- **Package**: The app already depends on AnimatedPolylineKit via SPM ([project.pbxproj](miataru.xcodeproj/project.pbxproj)); ensure the new representable imports `AnimatedPolylineKit` and that the overlay view is linked to the same target that has the dependency.

## Files to add or touch


| File                                                                                                      | Change                                                                                             |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| New file (e.g. `AnimatedRouteOverlayView.swift` under the same Views/Map or Devices folder)               | UIViewRepresentable for the overlay MKMapView + coordinator (delegate, driver, overlay lifecycle). |
| [iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift) | Add ZStack with overlay representable; pass `currentRegion` and `route?.polyline`.                 |


## Alternative (not recommended here): full MKMapView replacement

Replace the SwiftUI `Map` entirely with one MKMapView-based representable that draws the route (including done/todo/ghost and mutual navigation) and the animated overlay. This would avoid two map layers but would require reimplementing all map content (annotations, polylines, camera/position sync with `MapCameraPosition`) and re-testing gestures, follow mode, and compass/scale bar. Prefer the overlay approach unless you later need to consolidate onto a single map for performance or simplicity.

## Summary

- Add a non-interactive, region-synced overlay `UIViewRepresentable` that draws the animated overlay for the **full route** polyline with AnimatedPolylineKit (demo-style config, `.startToEnd`).
- In the navigation view, show this overlay on top of the existing Map when a route exists (`route?.polyline`), and keep the overlay’s region in sync with `currentRegion`.

