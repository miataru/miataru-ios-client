# App Data Cleanup (2026-05-21)

## Context
The app-owned persistent stores are small, but iOS can report several megabytes of app data after normal use. The larger footprint mainly comes from cache data:

- map and widget snapshot PNG files
- stale `.png.sb-*` files left by atomic writes
- `URLSession` and system caches
- OS-managed Metal, MapKit, and SplashBoard caches

`Library/Caches` can be reclaimed by iOS under storage pressure. Snapshot files that were written directly into the App Group root, however, were not in a cache directory and were not garbage-collected by the app.

## Goal
- Keep long-lived app stores bounded.
- Move widget snapshots into an OS-cacheable App Group location.
- Remove orphaned legacy snapshot files from the App Group root.
- Keep known devices, the user's own device, and widget-referenced devices.
- Expire unknown visitor and supplemental cache entries after a conservative default TTL.
- Avoid disk caching for Miataru JSON POST responses that do not need local persistence.

## Implementation
### Central Cleanup
`PersistentDataCleanup` is the app-side cleanup coordinator. It collects retained device IDs from:

- `KnownDeviceStore.shared.devices`
- `thisDeviceIDManager.shared.deviceID`
- the current shared widget payload, including cached devices, own-device metadata, and widget device selections

The cleanup runs after startup widget sync and after device removal. Device IDs are normalized before comparison so casing and incidental whitespace do not keep duplicate cache entries alive.

### Widget Snapshots
App and widget snapshot paths now resolve below the App Group container at:

```text
Library/Caches/WidgetSnapshots/
```

Current snapshots can be deleted without data loss because widgets already tolerate missing images and regenerate map snapshots when needed.

The cleanup scans both the new cache directory and the legacy App Group root. It removes:

- orphaned `MapSnapshot-*` files in the new cache directory
- orphaned `WidgetMapSnapshot-*` files in the new cache directory
- all root-level legacy `MapSnapshot-*` and `WidgetMapSnapshot-*` files
- matching `.png.sb-*` atomic-write leftovers

### Location Cache Pruning
`DeviceLocationCacheStore.prune(...)` keeps retained device IDs and removes unknown device locations older than seven days by default. This bounds supplemental visitor/location data while preserving recent UI context.

When stale locations are removed, matching reverse-geocode queue entries are also removed and widget data is resynced.

### Slogan Cache Pruning
`DeviceSloganCacheStore.prune(...)` applies the same retained-device and seven-day unknown-device policy. Unknown IDs without a fetch timestamp are removed because the cleanup cannot prove they are recent.

`markFreshNow(for:at:)` accepts an injected date so pruning behavior can be tested deterministically.

### Network Cache Policy
`MiataruAPIClient` now uses an ephemeral `URLSession` with `urlCache = nil` and `.reloadIgnoringLocalCacheData`. Miataru API calls are POST-based JSON requests, so response disk caching is not useful for the app's behavior.

## Intentionally Not Cleaned
The cleanup does not manually delete Metal, MapKit, SplashBoard, or other system-managed cache directories. Those caches explain a small baseline of app data and should remain under iOS control.

## Validation
Added regression coverage for:

- snapshot cleanup retaining current files while removing orphaned and atomic-write leftovers
- slogan cache pruning of unknown IDs older than seven days
- location cache pruning of unknown IDs older than seven days
- retry outbox defaults staying at 500 items and 24 hours

Validated with:

```sh
git diff --check
```

Result: no whitespace errors.

```sh
./miataru/scripts/test-unit.sh
```

Result: unit tests passed.

Simulator App Group check after cleanup found no root-level `MapSnapshot-*`, `WidgetMapSnapshot-*`, or `.png.sb-*` files.
