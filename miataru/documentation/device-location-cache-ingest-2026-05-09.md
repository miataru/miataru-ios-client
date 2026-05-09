# Device Location Cache Ingest

Date: 2026-05-09

## Summary

Network responses that already contain device location information now feed a central cache-ingest path. This keeps the device list, maps, widgets, and recent-visitor indicator fresher without introducing additional server requests.

## Problem

Several flows fetched useful device data but only updated their own local view state. Other flows manually wrote to `DeviceLocationCacheStore`, sometimes one device at a time. That left gaps where the device list could miss fresh battery, altitude, speed, or timestamp data until a later list refresh. It also meant older background, history, or widget data could race against newer cache entries.

## Changes

`DeviceLocationCacheStore` now owns the shared ingest behavior:

- `ingestServerLocations(_:removingMissingDeviceIDs:forceGeocoding:)` converts `MiataruLocationData` into cache snapshots.
- `ingestLatestHistoryEntry(_:for:)` promotes the newest matching history entry only when it is not stale.
- `updateRecentVisitors(from:ownDeviceID:window:)` normalizes visitor IDs and keeps the recent-visitor signal in one place.
- `setLocation(...)` and `applyLocationSnapshots(...)` reject older timestamps and preserve existing optional metadata when the incoming response omits it.
- Missing-device removal remains opt-in, so partial or history responses cannot delete unrelated cache entries.

`MiataruAppAPI` now updates app caches after successful read responses:

- `getLocation` updates device slogans and device locations on the main actor.
- `getLocationHistory` promotes the newest history location for the requested device.
- Visitor-history wrappers update `recentVisitorDeviceIDs` when the response is for the current device.

Widget synchronization is timestamp-aware:

- App startup and foreground activation import newer App Group widget locations into the app cache.
- `syncAllDevices()` preserves newer widget entries instead of overwriting them with older app-cache data.

View-specific cache loops were removed from iPhone/iPad device maps, group maps, navigation, device-list fallback paths, and unknown-visitor enrichment where the API wrapper already performs the cache ingest.

## Resulting Behavior

- Device rows can pick up fresh location, battery, altitude, speed, and place data from map, group-map, history, widget, and background responses.
- History views can improve the live cache when their newest entry is fresher than the existing location.
- Recent-visitor indicators react to any successful visitor-history response for the current device.
- Widget and app cache synchronization no longer downgrades newer location data.
- The change does not add any new server requests; it only reuses data already returned by existing requests.

## Localization Fix

The missing `frequent_background_location_updates_central_explanation` key was added to `Localizable.xcstrings` for all supported app locales. The central Settings toggle now uses this shorter explanation, while Advanced Options keeps the detailed frequent-background update explanation.

## Verification

Validated with:

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:miataruTests/DeviceLocationCacheStoreTests
```

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:miataruTests/SettingsConfigurationTests
```

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:miataruTests
```

Result: all 115 unit tests in `miataruTests` passed.
