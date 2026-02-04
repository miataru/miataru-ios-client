---
name: Route Request Optimization
overview: Optimize route calculation requests by adding off-route detection and transport-type-aware dynamic thresholds, maintaining accuracy while reducing unnecessary API calls.
todos:
  - id: off-route-detection
    content: Implement isUserOffRoute() function using MKRoute polyline distance calculation
    status: completed
  - id: transport-thresholds
    content: "Add transport-type-aware threshold properties (walking: 15m, transit: 50m, auto: 25m)"
    status: completed
  - id: integrate-off-route
    content: Replace hasSignificantMovementSinceLastRoute() with isUserOffRoute() in auto-update logic
    status: completed
  - id: fix-transport-change
    content: Add cache check to transport type onChange handler
    status: completed
  - id: update-cache-store
    content: Update RouteCacheStore.isValid() to support route-based validation
    status: completed
  - id: testing
    content: Test with all transport types to verify threshold behavior
    status: completed
isProject: false
---

# Route Request Optimization Plan

## Current State Analysis

The route calculation system in [iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift) uses these mechanisms:

- **Fixed 100m threshold** for cache reuse and significant movement detection
- **Timer-based updates** (5-60s interval, default 30s)
- **Daily limit** of 17,000 requests
- **Change detection** comparing timestamps and coordinates

**Problem**: Routes recalculate based on distance from last calculation point, not deviation from the actual route. A user could move 150m along the correct route and trigger an unnecessary recalculation.

## Optimization Strategy

### 1. Add Off-Route Detection

Instead of "has user moved 100m from where route was calculated", detect "is user 25m+ away from the calculated route polyline".

**Implementation in `iPhone_DeviceNavigationView.swift`:**

```swift
private func isUserOffRoute(threshold: CLLocationDistance = 25) -> Bool {
    guard let route = route,
          let userLocation = userCoordinate else { return false }
    
    let userPoint = MKMapPoint(userLocation)
    let polyline = route.polyline
    let points = polyline.points()
    
    var minDistance = CLLocationDistance.greatestFiniteMagnitude
    for i in 0..<polyline.pointCount {
        let distance = userPoint.distance(to: points[i])
        minDistance = min(minDistance, distance)
    }
    return minDistance > threshold
}
```

**Integration point** (line ~902):

```swift
// BEFORE:
if isAutoRouteUpdateLocked && hasSignificantMovementSinceLastRoute() {

// AFTER:
if isAutoRouteUpdateLocked && isUserOffRoute(threshold: offRouteThreshold) {
```

### 2. Transport-Type-Aware Thresholds

Define different thresholds based on transport mode:

```swift
private var offRouteThreshold: CLLocationDistance {
    switch settings.navigationTransportType {
    case 0:  // Walking
        return 15  // Tighter tolerance for pedestrians
    case 3:  // Transit
        return 50  // More tolerance (fixed routes)
    default: // Automobile
        return 25  // Default threshold
    }
}

private var cacheReuseThreshold: CLLocationDistance {
    switch settings.navigationTransportType {
    case 0:  return 50   // Walking: smaller movements matter
    case 3:  return 150  // Transit: larger tolerance
    default: return 100  // Automobile: current default
    }
}
```

### 3. Fix Transport Type Change

Currently bypasses cache check. Add cache check:

```swift
// Line 356-358, BEFORE:
.onChange(of: settings.navigationTransportType) { _, _ in
    calculateRoute()
}

// AFTER:
.onChange(of: settings.navigationTransportType) { _, _ in
    if !useCachedRouteIfValid() {
        calculateRoute()
    }
}
```

### 4. Skip Timer Callback When No Location Update

Add a guard to skip processing when location hasn't actually changed:

```swift
// In startAutoUpdate() timer callback, add:
guard locationActuallyUpdated else { return }
```

Track with a simple flag that resets after processing.

## Files to Modify


| File                                                                                                      | Changes                                                                          |
| --------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| [iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift) | Add `isUserOffRoute()`, transport-aware thresholds, fix transport change handler |
| [RouteCacheStore.swift](miataru/LocationManagers/RouteCacheStore.swift)                                   | Add `isValid(cached:currentUserCoordinate:route:offRouteThreshold:)` overload    |


## Expected Impact

- **Reduced requests**: Users traveling along route won't trigger recalculations
- **Maintained accuracy**: Off-route detection ensures timely recalculation when needed
- **Transport-appropriate behavior**: Walking gets tighter tolerances, transit gets looser
- **No breaking changes**: Existing daily limit and cache mechanisms remain intact

## Rollback Safety

All changes are additive. Existing thresholds can be restored by setting transport-type thresholds to current fixed values (100m/25m).