# Navigation Ghost Update Stabilization (2026-05-22)

## Context

The route progress ghost can be shown while navigating from a selected device back to the current user (`device -> user`). It visualizes predicted movement between server location updates by splitting the active `MKRoute` polyline into completed and remaining segments and placing a marker at the interpolated progress point.

The reported field issue was that the ghost remained visible but stopped moving along the route under some conditions. Existing unit coverage for `RouteGhostCalculator`, `MKPolyline` helpers, and `NavigationRouteRefreshPolicy` was already green, so the likely failure mode was not a pure calculator deadlock. The more plausible cause was SwiftUI `Map` content invalidation combined with overlapping location fetches and route calculations.

## Logic

`iPhone_DeviceNavigationView` now keeps route-progress presentation in an explicit `RouteGhostSnapshot` state instead of deriving all progress map content directly inside the `Map` builder. The snapshot contains:

- completed route polyline
- remaining route polyline
- ghost coordinate
- normalized route progress
- whether the ghost marker should be visible

The snapshot is refreshed on the one-second navigation clock and whenever relevant route inputs change, including route, user/device coordinates, timestamps, speed, route direction, and the `showRouteProgress` setting. When the snapshot changes meaningfully, `routeProgressRenderRevision` is incremented. The map renders route progress through a `RouteRenderKey` that includes both route-overlay and progress revisions, forcing SwiftUI `Map` content to rebuild the polyline, circle, and ghost annotation when progress advances.

User, device, and ghost annotations are rendered through unique internal `NavigationMapAnnotation` identities. This avoids SwiftUI `Map` reusing empty-label annotations across distinct markers.

`RouteGhostPresentationPolicy` owns the visibility rule for the marker. Standard mode (`device -> user`) can show the ghost once progress is above the minimum display threshold and below route completion. Reverse mode (`user -> device`) intentionally keeps the ghost hidden. Fresh cached routes use `routeSummarySeedDate` to decide visibility instead of stale server sample timestamps, so a reused route does not immediately hide the ghost because the cached location timestamp is old.

`RouteGhostCalculator` now names its direction parameter `isRouteFromDeviceToUser` and uses the active traveler as the speed/timestamp source:

- `true`: standard route, device speed/device timestamp, base coordinate = device coordinate
- `false`: reverse route, user speed/user timestamp, base coordinate = user coordinate

The calculator also uses the actual polyline geometry length as its total distance. This avoids returning `nil` when `MKRoute.distance` and `MKRoute.polyline` length diverge slightly.

## Concurrency Guarding

The navigation screen now serializes target-location fetch work and route-refresh work:

- Only one automatic update tick runs at a time.
- Only one target-device fetch runs at a time; pending requests are merged so a later explicit refresh can still request recentering or cache bypass.
- `MKDirections` calculations are protected by a generation ID.
- Old `MKDirections` responses are ignored if the view disappeared, the task was cancelled, or a newer calculation started.
- Fetch and route tasks are cancelled when the navigation screen disappears or when the selected device changes.

The goal is to prefer a later, coherent update over overlapping async work that can render stale route or ghost state.

## Implications

- Map overlays may redraw more often while the ghost moves. This is intentional and should be a small CPU/GPU cost compared with a frozen progress marker.
- On very poor networks, automatic updates can be delayed by an in-flight fetch instead of stacking concurrent requests.
- Quickly switching direction, device, or screen can discard a route response that arrives late. This prevents stale routes from overwriting newer navigation state.
- Cached routes with fresh route summary seed dates can show progress even when their underlying sample timestamps are old.
- Progress is based on polyline geometry while Apple route summaries still use MapKit route distance and travel time, so tiny discrepancies between visual progress and summary text are possible.
- Focused double-tap navigation remains unchanged: it renders the stable base route plus optional mutual-navigation overlay, without ghost/progress segmentation.

## Test Coverage

Updated unit coverage verifies:

- Ghost progress moves monotonically across repeated `now` ticks while server position, speed, and timestamp remain unchanged.
- Standard direction (`device -> user`) uses device speed/timestamp.
- Reverse direction (`user -> device`) uses user speed/timestamp.
- Fresh `routeSummarySeedDate` keeps a cached route eligible for ghost display even when sample timestamps are old.
- Reported route distances that are larger or smaller than the polyline length still produce a valid ghost up to the destination.

Focused validation command:

```sh
TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17' ./scripts/test-unit.sh -only-testing:miataruTests/RouteGhostCalculatorTests -only-testing:miataruTests/MKPolylineExtensionsTests -only-testing:miataruTests/NavigationRouteRefreshPolicyTests
```

Result on 2026-05-22: 28 tests in 3 suites passed.
