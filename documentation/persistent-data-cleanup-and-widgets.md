# Persistent Data Cleanup And Widgets

## Summary

This document consolidates app-owned persistent cleanup behavior and the widget device selection fix. Both topics revolve around keeping shared app/widget state bounded, timestamp-aware, and stable across app and WidgetKit lifecycles.

## Source Notes Consolidated

This document consolidates:

- `app-data-cleanup-2026-05-21.md`
- `widget-device-selection-fix-2026-05-21.md`

## App Data Cleanup

iOS can report several megabytes of app data after normal use. The larger footprint mostly comes from cache data:

- map and widget snapshot PNGs
- stale `.png.sb-*` files from atomic writes
- `URLSession` and system caches
- OS-managed Metal, MapKit, and SplashBoard caches

`Library/Caches` can be reclaimed by iOS, but earlier widget snapshots in the App Group root were not in a cache directory and were not garbage-collected by the app.

Cleanup goals:

- Keep long-lived app stores bounded.
- Move widget snapshots into an OS-cacheable App Group cache path.
- Remove orphaned legacy snapshot files from the App Group root.
- Retain known devices, the user's own device, and widget-referenced devices.
- Expire unknown visitor and supplemental cache entries after a conservative TTL.
- Avoid disk caching for Miataru JSON POST responses.

## Cleanup Coordinator

`PersistentDataCleanup` is the app-side cleanup coordinator. It collects retained DeviceIDs from:

- `KnownDeviceStore.shared.devices`
- `thisDeviceIDManager.shared.deviceID`
- current shared widget payload, including cached devices, own-device metadata, and widget selections

Cleanup runs after startup widget sync and after device removal. DeviceIDs are normalized before comparison so casing or whitespace does not keep duplicate cache entries alive.

## Widget Snapshot Cleanup

App and widget snapshot paths now resolve below the App Group container at:

```text
Library/Caches/WidgetSnapshots/
```

Snapshots are safe to delete because widgets tolerate missing images and regenerate map snapshots as needed.

Cleanup scans both the new cache directory and legacy App Group root. It removes:

- orphaned `MapSnapshot-*` files in the new cache directory
- orphaned `WidgetMapSnapshot-*` files in the new cache directory
- all root-level legacy `MapSnapshot-*` and `WidgetMapSnapshot-*` files
- matching `.png.sb-*` atomic-write leftovers

## Location And Slogan Cache Pruning

`DeviceLocationCacheStore.prune(...)`:

- Retains known/current/widget-selected devices.
- Removes unknown device locations older than seven days by default.
- Removes matching reverse-geocode queue entries.
- Resyncs widget data when stale locations are removed.

`DeviceSloganCacheStore.prune(...)`:

- Uses the same retained-device and seven-day unknown-device policy.
- Removes unknown IDs without a fetch timestamp because recency cannot be proven.
- Supports injected dates through `markFreshNow(for:at:)` for deterministic tests.

## Network Cache Policy

`MiataruAPIClient` uses an ephemeral `URLSession` with `urlCache = nil` and `.reloadIgnoringLocalCacheData`.

Miataru API calls are POST-based JSON requests, so response disk caching is not useful for app behavior.

The cleanup intentionally does not manually delete Metal, MapKit, SplashBoard, or other system-managed caches. Those remain under iOS control.

## Widget Device Selection

Configurable Miataru widgets could show stale device content after the user selected a different device. The configuration UI persisted the new selected entity, but timeline rendering depended on resolving that entity against a shared payload that sometimes contained only cached location entries for some devices.

Root cause:

- `WidgetSharedPayload.devices` was both the selectable device list and the cached-location list.
- These lists have different lifecycles; a device should be selectable even without a cached location.
- WidgetKit could reuse older timeline entries.

Fix:

- `WidgetSharedPayload` carries a separate `deviceSelections` list in app and widget extension.
- App-side sync writes all known devices into `deviceSelections` in `KnownDeviceStore` order, independent of cached locations.
- `DeviceSelectionIntent.device` stores a raw `String` DeviceID with a `DynamicOptionsProvider`.
- Options still display friendly device names, but the timeline provider receives the exact selected DeviceID.
- `WidgetTimelineDataLoader` starts from the configured DeviceID, canonicalizes IDs case-insensitively, preserves configured IDs with no cached entry yet, keeps location entries ordered by the stable selection list, and preserves selection metadata when merging fresh widget-fetched locations.
- `KnownDeviceStore` normalizes table positions after load, add, move, and removal.
- The iPhone device list routes drag reordering through `KnownDeviceStore.move(...)`, which persists positions and resyncs widget data.

## Validation History

Cleanup validation covered:

- snapshot cleanup retaining current files while removing orphaned and atomic-write leftovers
- slogan cache pruning of unknown IDs older than seven days
- location cache pruning of unknown IDs older than seven days
- retry outbox defaults staying at 500 items and 24 hours
- unit tests
- simulator App Group inspection showing no root-level `MapSnapshot-*`, `WidgetMapSnapshot-*`, or `.png.sb-*` files after cleanup

Widget validation covered:

- `miataruWidgets` build and AppIntents metadata generation
- focused `WidgetDataSyncCoordinatorTests`
- `git diff --check`

