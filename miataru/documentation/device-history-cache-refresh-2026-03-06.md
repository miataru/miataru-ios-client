# Device History Cache Refresh Behavior (2026-03-06)

## Problem
Device history could remain stale after a newer location was already known for the same device. Users often had to close and reopen the app to see updated history data.

## Change
Adjusted history loading and cache policy for device-history flows:

- Added richer cache entries in `DeviceHistoryCacheStore`:
  - cached history payload
  - fetch timestamp
  - newest history timestamp
- Added cache refresh decision helper:
  - `shouldRefreshHistory(for:latestKnownLocationTimestamp:maxAge:)`
  - refreshes when cache is too old or known device location is newer than cached history (with tolerance)
- Added explicit cache invalidation:
  - `removeHistory(for:)` clears stale/invalid entries.
- Updated iPhone/iPad map history entry points to always fetch before opening history instead of short-circuiting on cached results.
- Updated iPhone history map behavior:
  - reuse cache for fast display
  - trigger background refresh when needed (short active reuse window)
  - observe known device-location timestamp changes and refresh while the history view is active (throttled)
  - keep currently visible history on refresh failure when refresh was location-triggered
- If server returns empty history, local history cache is now removed for that device.

## Expected Behavior
- Opening location history fetches fresh data.
- While actively using history, cache is reused briefly for responsiveness.
- New location updates can refresh history only within active history usage.
- Empty/unauthorized-like history responses no longer leave stale local history behind.

## Verification
- Built app target successfully with:
  - `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build`
