# AnimatedPolylineKit – Changes and Decisions

## Overview

Implemented a configurable animated polyline component for MapKit that draws a route with a moving highlight (patch) along the path. The Sample app uses it to display driving routes with an animated “patch” that moves from start to end.

---

## 1. Package and API

- **Package.swift**: Added `platforms: [ .iOS(.v15) ]` so the package builds for iOS (MapKit/SwiftUI/UIKit).
- **Public API**: New types in `Sources/AnimatedPolylineKit/`:
  - **AnimatedPolylineConfiguration** – Colors, patch size, direction, duration, easing, line style.
  - **AnimatedPolylineOverlay** – Custom `MKOverlay` holding route coordinates, config, and progress (0…1).
  - **AnimatedPolylineRenderer** – Draws full route + moving patch with gradient.
  - **AnimatedPolylineAnimationDriver** – Drives progress with `CADisplayLink`, optional looping, easing.
  - **AnimatedPolylineEasingHelper** – Eased progress for manual animation.

---

## 2. Configuration Model

- **Underlying color**: Full polyline is drawn in one color (e.g. blue); configurable via `underlyingColor`.
- **Moving patch**: Short segment (e.g. 10% of path length) defined by `patchLength` and `patchWhiteBandFraction` (wider band in the middle).
- **Gradient**: Patch uses **route color → light tint of route color → route color**. Light tint = 70% blend toward white (configurable in code as `blend` in the renderer).
- **Direction**: `startToEnd` or `endToStart` for patch movement.
- **Animation**: `duration`, `startEasing`, `endEasing` (e.g. easeIn / easeOut).
- **Line style**: `lineWidth`, `lineCap`, `lineJoin` (defaults: 8pt, round, round).

---

## 3. Overlay and Thread Safety (Swift 6)

- **AnimatedPolylineOverlay**: Conforms to `MKOverlay` only (no `@MainActor`) so MapKit can use it from any thread without “crosses into main actor” warnings.
- **Progress**: `progress` is thread-safe (lock); when set off the main thread we dispatch to main to invalidate the renderer.
- **Renderer invalidation**: To avoid “Sending 'self' risks causing data races”, we do **not** capture the overlay in the main-queue closure. Instead:
  - **AnimatedPolylineOverlayRegistry** maps `ObjectIdentifier(overlay)` → weak renderer.
  - Renderer registers in `init`, unregisters in `deinit`.
  - Overlay progress setter (off main) uses `ObjectIdentifier(self)` and dispatches that value; the closure calls `Registry.invalidateRenderer(for: id)` so no overlay reference is sent.
- **Registry**: Static `renderers` dictionary is marked `nonisolated(unsafe)` with all access protected by an `NSLock` to satisfy concurrency checking.

---

## 4. Rendering

- **Draw order**:
  1. Full polyline in `underlyingColor` (entire route).
  2. Moving patch: a short segment centered at current progress, with gradient **route → light route tint → route**.
- **Patch gradient**: Three zones:
  - Start: route color → light tint.
  - Middle: solid light tint (width = `patchWhiteBandFraction`, default 55%).
  - End: light tint → route color.
- **Light tint**: 70% blend of route color toward white (`route * 0.3 + 0.7`) so the highlight stays a light version of the route color.
- **Path math**: Cumulative normalized length along the polyline; patch and segments are computed in normalized [0,1] then clipped to the path.

---

## 5. Animation Driver

- **AnimatedPolylineAnimationDriver**: Uses `CADisplayLink` on the main run loop; publishes `progress` in [0,1] with configurable duration and start/end easing (blended over the run).
- **Looping**: Optional; when not looping, driver stops at progress 1.
- **Lifecycle**: `start()` / `stop()` / `reset(andRestart:)`; `deinit` calls `stop()` to break the display link retain cycle.

---

## 6. Sample App Integration

- **MapViewModel**:
  - Builds **AnimatedPolylineOverlay** from `MKPolyline` when a route is received.
  - Uses **AnimatedPolylineAnimationDriver** and subscribes to `$progress` to set `overlay.progress` on the main thread.
  - On “Generate new route”: clears overlay and driver, then requests a new route.
- **MapView**: Takes `animatedOverlay: AnimatedPolylineOverlay?`; in `rendererFor overlay` returns **AnimatedPolylineRenderer** for that overlay type.
- **Package reference**: Local package path set to `..` (parent of `Sample/`) so the package at repo root is used; app target links product **AnimatedPolylineKit**.

---

## 7. Demo App Fixes and UX

- **Route visibility**: Only apply a route when `route.polyline.pointCount >= 2`.
- **Region framing**: When a route is received, the visible region is set from the route’s `boundingMapRect` (with 20% padding) instead of only start/end markers, so the full route (including detours) stays in view and the “wrong fraction” issue is avoided.
- **Line width**: Default and sample use a wider line (e.g. 8pt package default, 10pt in the sample).

---

## 8. File Layout

- **Sources/AnimatedPolylineKit/**  
  `AnimatedPolylineKit.swift`, `AnimatedPolylineConfiguration.swift`, `AnimatedPolylineOverlay.swift`, `AnimatedPolylineRenderer.swift`, `AnimationDriver.swift`
- **Sample**: `ContentView.swift` and project updated to use the overlay, renderer, and driver; package product dependency and path fixed in `project.pbxproj`.

---

## 9. Design Decisions Summary

| Decision | Reason |
|----------|--------|
| Custom `MKOverlay` instead of subclassing `MKPolyline` | Clear ownership of coordinates and config; no reliance on MapKit polyline subclassing. |
| Registry for renderer invalidation | Avoids capturing overlay in async closures and satisfies Swift 6 sendability. |
| Patch as short segment (not full-line gradient) | Matches “small moving patch” requirement; full line stays one color. |
| Route color → light tint → route color | Keeps the patch in the same hue as the route (e.g. light blue on blue). |
| 70% blend toward white for light tint | Balances visibility and route-color tint. |
| Region from route bounding rect | Ensures full route is visible and fixes incorrect framing. |
