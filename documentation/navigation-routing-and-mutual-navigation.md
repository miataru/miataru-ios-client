# Navigation, Routing, And Mutual Navigation

## Summary

This document consolidates Miataru navigation fixes and route rendering behavior across focused navigation, standard navigation, mutual-navigation indicators, route summaries, and the route-progress ghost.

## Source Notes Consolidated

This document consolidates:

- `navigation-follow-camera-bottom-visibility-fix-2026-03-02.md`
- `navigation-focused-local-heading-refresh-fix-2026-03-03.md`
- `mutual-navigation-indicator-symbol-update-2026-03-04.md`
- `mutual-navigation-bottom-accessory-separator-fix-2026-03-06.md`
- `mutual-navigation-symbol-pulse-2026-03-06.md`
- `navigation-standardmode-live-eta-and-compact-arrival-2026-03-11.md`
- `navigation-standardmode-zero-summary-fix-2026-03-13.md`
- `navigation-ghost-update-stabilization-2026-05-22.md`

## Focused Navigation Location And Camera

Focused navigation is the double-tap reversed route mode from the user device to the selected device.

Two early fixes made the focused navigation map more stable:

- The own-device marker and camera now react to `latestRawLocation` before sensitivity-filtered `currentLocation`, so foreground movement feels local and immediate rather than server-timed.
- The follow camera uses safer heading fallback logic and less aggressive low-speed look-ahead.

Details:

- `LocationManager` publishes `latestRawLocation` immediately from `didUpdateLocations`.
- `iPhone_DeviceNavigationView` uses `effectiveUserLocation = latestRawLocation ?? currentLocation`.
- Focused camera, speed, step/ETA overlay, and marker updates use the effective location.
- The view subscribes to `locationManager.$latestRawLocation`.
- Heading smoothing keeps blended heading when heading accuracy is valid.
- Invalid heading falls back to smoothed course only.
- Course-only fallback no longer marks `isHeadingValid = true`.
- Follow-camera heading selection prefers valid `userHeading`, then course only when `course >= 0` and speed is at least 1.0 m/s.
- Look-ahead bounds were reduced from 70-360 m to 50-320 m and are clamped harder when heading reliability is poor.

Expected behavior:

- The user marker stays visible in the lower map area after route overview zoom.
- Low-speed/standstill navigation no longer pushes the marker to the bottom edge.
- Higher-speed navigation still receives forward visibility without abrupt displacement.
- Heading arrow jitter is reduced, especially in Simulator.

## Mutual Navigation Indicator

Mutual-navigation state is represented as a compact SF Symbol rather than appended text in constrained route summary UI.

Current behavior:

- The indicator uses `person.line.dotted.person.fill`.
- It appears in top route-info overlays and the iOS 26 bottom accessory route-info line.
- It keeps the localized `mutual_navigation_active` accessibility label.
- It uses the localized `device_row_separator` visual separator before the symbol in the bottom accessory.
- The separator before the symbol is accessibility-hidden to avoid redundant speech.
- The symbol pulses with `.symbolEffect(.pulse, options: .repeating, isActive: ...)`.
- Pulse animation runs only when `animationsAllowed` is true and `settings.pulsingMapMarkers` is enabled.
- If animations are disabled or pulsing markers are off, the icon remains static.

## Route Summary And ETA

Reversed navigation (`user -> selected device`) now keeps live ETA/distance/arrival values in sync in both focused and normal navigation modes.

Changes:

- `updateLiveNavigationRouteSummary()` updates all reversed navigation, not only focused `isNavigationMode`.
- Duration formatting uses hour/minute without seconds for compactness.
- Bottom accessory arrival segment shows only the time, without `ETA:` or localized arrival prefix.

Standard navigation (`device -> user`) previously calculated the correct route summary then collapsed to `0 km / 0 min` on the next live tick when the selected device's last server sample was older than the route ETA. The fix adds `routeSummarySeedDate`:

- Set when a fresh route or valid cached route is applied.
- Cleared when navigation resets, direction changes, or stops.
- Standard navigation counts down from `routeSummarySeedDate` first and falls back to legacy timestamps only if needed.

Result:

- Standard iPhone/iPad navigation keeps the initially correct ETA/distance.
- Cached and freshly calculated routes behave consistently.
- Focused navigation remains on the reversed-route live-summary path.

## Live Speed And Navigation HUD

The navigation screen shows the user's live speed in both route directions whenever a route is available. Speed is always displayed in metric km/h, independent of the device's regional unit preference. The value comes from `latestRawLocation ?? currentLocation`; an invalid or older-than-15-seconds sample displays a dash. The value changes with a short numeric transition unless Reduce Motion is enabled, and its accessibility value includes the localized unit.

The optional full-screen HUD presents a black background, route geometry, route summary, direction, and turn guidance when navigating from the user to the device. The overview shows both endpoint markers; the focused user-to-device view emphasizes the own-position marker and forward route. Its three palettes are black/white, black/red, and black with a white route plus yellow speed and own-marker emphasis. Mirroring applies to the projected HUD content, including the own-position marker, while the palette and close controls stay unmirrored and usable. Controls hide after inactivity and return on a HUD tap; VoiceOver keeps them available. Closing the HUD restores the previous navigation chrome state. The existing device-autolock setting remains the source of the app-wide idle timer policy, with the HUD session integrated into that policy.

In user-to-device navigation, the HUD opens with a route overview, then transitions to a perspective-focused projection of the current route segment after a short overview interval. It follows the user's current location and uses the route's forward geometry so upcoming turns remain visible. Route recalculation or direction changes restart the overview. Device-to-user mode remains an overview and does not show an incorrect turn instruction. The own-position arrow uses validated compass/course heading when available; a route tangent is only a fallback in user-to-device mode, while device-to-user mode uses a neutral position marker when own heading is unavailable.

Geometry and settings behavior are covered by `NavigationHUDSettingsTests`, including route projection, heading rotation, focus-window distance, and persisted HUD choices. Search navigation has focused UI coverage. There is not yet a simulator UI test that exercises a live route through the HUD in both orientations, so visual behavior with real MapKit routes remains a manual QA item.

## Route Progress Ghost

The route progress ghost appears in standard navigation (`device -> user`) to visualize predicted movement between server updates.

The stabilized implementation uses explicit render state:

- `RouteGhostSnapshot` stores completed polyline, remaining polyline, ghost coordinate, normalized progress, and marker visibility.
- Snapshot refreshes on the one-second navigation clock and when route, coordinates, timestamps, speed, direction, or `showRouteProgress` changes.
- Meaningful snapshot changes increment `routeProgressRenderRevision`.
- `RouteRenderKey` includes route-overlay and progress revisions to force SwiftUI `Map` content rebuilds.
- User, device, and ghost annotations use unique internal `NavigationMapAnnotation` identities.

Visibility:

- `RouteGhostPresentationPolicy` owns marker visibility.
- Standard mode can show the ghost when progress is above the minimum threshold and below completion.
- Reverse mode intentionally hides the ghost.
- Fresh cached routes use `routeSummarySeedDate` instead of stale server sample timestamps so the ghost is not hidden immediately by old cache data.

Calculation:

- `RouteGhostCalculator` uses `isRouteFromDeviceToUser`.
- Standard route uses device speed/timestamp and device coordinate as base.
- Reverse route uses user speed/timestamp and user coordinate as base.
- Geometry length comes from the polyline rather than relying only on `MKRoute.distance`, avoiding nil results for tiny MapKit distance discrepancies.

Concurrency:

- Only one automatic update tick runs at a time.
- Only one target-device fetch runs at a time; pending requests merge.
- `MKDirections` calculations use a generation ID.
- Late route responses are ignored if the view disappeared, the task was cancelled, or a newer calculation started.
- Fetch and route tasks are cancelled when the navigation screen disappears or selected device changes.

Implications:

- Map overlays redraw more often while the ghost moves.
- Poor networks delay automatic updates instead of stacking concurrent fetches.
- Rapid direction/device/screen changes discard late stale route responses.
- Focused double-tap navigation remains a stable base route plus optional mutual-navigation overlay, without ghost segmentation.

## Validation History

Validation included:

- App builds with `xcodebuild` for simulator and generic iOS destinations.
- Confirmation that the mutual-navigation symbol and accessibility label are used in both overlay paths.
- Confirmation that the localized separator is used in the bottom accessory.
- Confirmation that pulse effects use the same activation gate.
- Focused unit validation for `RouteGhostCalculatorTests`, `MKPolylineExtensionsTests`, and `NavigationRouteRefreshPolicyTests`.
- Focused `NavigationHUDSettingsTests` run: 10 tests passed, including HUD projection, focus geometry, and heading behavior.
- Settings search UI tests for root controls and advanced/prerequisite routing passed in the focused simulator lane.

Route ghost coverage verifies:

- Progress moves monotonically across repeated `now` ticks.
- Standard direction uses device speed/timestamp.
- Reverse direction uses user speed/timestamp.
- Fresh `routeSummarySeedDate` keeps cached routes eligible.
- Reported route distance discrepancies still produce a valid ghost.

