# Device List, Cache, Slogans, And Settings

## Summary

This document consolidates device-list refresh behavior, device-location cache ingest, DeviceID/name ambiguity handling, device slogan ingestion/cleansing/fetch strategy, and the settings refactor that moved advanced controls out of the root settings screen.

## Source Notes Consolidated

This document consolidates:

- `device-list-refresh-flicker-fix-2026-03-13.md`
- `device-location-cache-ingest-2026-05-09.md`
- `device-slogan-cleansing-and-error-message-2026-03-12.md`
- `getlocation-device-slogan-integration-2026-03-12.md`
- `settings-refactor-and-slogan-fetch-paths-2026-03-14.md`
- `device-id-name-ambiguity-handling-2026-05-27.md`

## Device List Refresh Flicker

Device rows previously lost supplemental data briefly during refreshes because overlapping requests and incremental cache publishes rendered partial states.

Root causes:

- Multiple refresh triggers could start competing `getLocation` requests.
- Cache updates were published one device at a time.
- Transient failures cleared cached locations.

Current behavior:

- `DeviceLocationRefresher` is `@MainActor`.
- `inFlightRefreshTask` coalesces overlapping refreshes.
- Failed refreshes no longer clear all cached device locations.
- The refresh path builds a full snapshot first and applies it in one publish pass.
- `DeviceLocationCacheStore.DeviceLocationSnapshot` is a lightweight refresh payload.
- `applyLocationSnapshots(...)` replaces cache contents in one consolidated publish.
- Existing placemark/time-zone data is preserved while fresh coordinates apply.
- Stored speed is preserved when incoming data only has position/timestamp.
- Devices explicitly missing from a full response can be removed.

Tradeoff:

- A failed refresh keeps stale data visible longer instead of blanking rows.
- A manual refresh during an automatic refresh reuses the active request.

## Device Location Cache Ingest

Network responses that already include location data feed a central cache-ingest path. This keeps lists, maps, widgets, and recent-visitor indicators fresh without extra server requests.

`DeviceLocationCacheStore` owns:

- `ingestServerLocations(_:removingMissingDeviceIDs:forceGeocoding:)`
- `ingestLatestHistoryEntry(_:for:)`
- `updateRecentVisitors(from:ownDeviceID:window:)`
- timestamp-aware `setLocation(...)`
- timestamp-aware `applyLocationSnapshots(...)`

Rules:

- Older timestamps are rejected.
- Optional metadata is preserved when incoming data omits it.
- Missing-device removal is opt-in so partial/history responses do not delete unrelated cache entries.
- Visitor IDs are normalized for recent-visitor signals.

`MiataruAppAPI` cache side effects:

- `getLocation` updates device slogans and locations on the main actor.
- `getLocationHistory` promotes the newest matching history entry.
- Visitor-history wrappers update `recentVisitorDeviceIDs` when the response is for the current device.

Widget synchronization:

- App startup and foreground activation import newer App Group widget locations into the app cache.
- `syncAllDevices()` preserves newer widget entries instead of overwriting them with older app-cache data.

Removed view-specific cache loops from device maps, group maps, navigation, device-list fallback paths, and unknown-visitor enrichment where the API wrapper already ingests the data.

## Device Slogan Ingest And Cleansing

Server `GetLocation` payloads include `DeviceSlogan` for list requests.

Client/library support:

- `MiataruLocationData` includes `DeviceSlogan`, with fallback decoding from `Slogan` for compatibility.
- `MiataruGetLocationResponse` tolerates `null` entries.
- Package version was raised to `1.1.1`.
- MiataruClientSwift README was updated for `DeviceSlogan`.
- Example app was adjusted for current `Double` update payload types.

App behavior:

- `DeviceSloganCacheStore.ingestGetLocationResults(_:requestedDeviceIDs:)` centrally caches slogans after `MiataruAppAPI.getLocation(...)`.
- The store moved from active per-device refresh to passive ingest for normal flows.
- Per-row/per-device `getDeviceSlogan` refresh paths were removed where `GetLocation` provides slogans.
- Add/Edit/My Device QR slogan reloads use `GetLocation` where appropriate.
- Unknown visitor notification best-effort slogan lookup uses `GetLocation`.

Later fetch strategy split:

- Add Device fetches via `getDeviceSlogan`.
- Edit Device fetches via `getDeviceSlogan`.
- Unknown devices in iPhone/iPad lists refresh locations via `getLocation`, then request missing slogans individually with `getDeviceSlogan`.
- All other cases continue using `getLocation`.

This avoids unnecessary individual lookups for normal list/device refreshes while still supporting cases where a slogan exists but no location payload is available.

Slogan input cleansing:

- `MiataruAppAPI.cleanseDeviceSlogan(...)` removes control characters, trims leading/trailing whitespace/newlines, and enforces max length 40.
- Applied in `MiataruAppAPI.setDeviceSlogan`.
- Applied in My Device slogan editor live input and save path.
- Applied in Edit Device slogan editor live input and save path.
- Applied in `DeviceSloganCacheStore`.
- While editing, normal spaces are preserved; final save still cleanses.
- Slogan-save failures show `device_slogan_set_failed_try_again_later` instead of raw backend/system text.
- All supported locales include the friendly error message.

## Settings Refactor

Settings were reorganized around centralized defaults and a shorter root screen.

Defaults:

- Runtime defaults live in `SettingsConfiguration.swift`.
- `SettingsManager` registers defaults mirrored in `Settings.bundle/Root.plist`.
- Fresh installs use requested defaults, including default location update mode, map update interval 30s, outside-map interval 60s, map zoom 5 km, route auto-update on, and route progress on.
- Existing installs receive a one-time migration before first `SettingsManager.shared` access so requested existing-user booleans are force-enabled once.

Screen structure:

- Root settings screen is shorter.
- Advanced toggles moved into `Advanced Options`.
- Former status section became `Advanced Options and Tracking Status`.
- `Device Access Control` is shown in root settings only while ACL is disabled; once ACL is active, it moves to `Location Tracking Details`.

Copy/localization:

- Labels and descriptions use direct, neutral phrasing.
- Missing setting descriptions were added.
- `Localizable.xcstrings` and `Settings.bundle/*.lproj/Root.strings` were aligned across supported locales.
- Runtime defaults and Settings.bundle defaults are covered by regression tests.

Related localization fix:

- Missing `frequent_background_location_updates_central_explanation` was added for all app locales.
- Central Settings uses the shorter explanation; Advanced Options keeps the detailed frequent-background explanation.

## Device ID And Name Ambiguity

Preserving DeviceID casing revealed ambiguity cases because routing, cache keys, unknown visitor filtering, and matching intentionally compare case-insensitively.

Rules:

- Device IDs are unique case-insensitively.
- Original DeviceID casing is stored and displayed.
- Add Device rejects a new DeviceID if the trimmed uppercase comparison key already exists.
- Device names may duplicate case-insensitively, but Add/Edit show a localized warning.
- Device list rows show a shortened DeviceID under the name when a row is ambiguous due to duplicate display name or same-ID-different-case conflict.

`KnownDeviceStore` owns duplicate logic:

- `device(matchingDeviceIDCaseInsensitive:excluding:)`
- `hasCaseInsensitiveDeviceIDDuplicate(for:)`
- `hasCaseInsensitiveNameDuplicate(...)`

UI behavior:

- `iPhone_AddDeviceView` trims name/ID before saving, blocks DeviceID conflicts, and shows duplicate-name warning.
- `iPhone_EditDeviceView` shows the warning without blocking save.
- `DeviceRowView` observes the store and renders short DeviceID only for ambiguous rows.
- New strings are localized in all app locales.

## Validation History

Validation included:

- App builds with `xcodebuild`.
- MiataruClientSwift `swift build`.
- `DeviceLocationCacheStoreTests`.
- `SettingsConfigurationTests`.
- Full `miataruTests` run with 115 unit tests at the time of cache-ingest validation.
- `DeviceLinkResolverTests` for DeviceID/name ambiguity.
- JSON/string catalog validation.

Regression coverage verifies:

- Snapshot application publishes one consolidated cache update.
- Placemark data is preserved across snapshot refreshes.
- Explicitly missing devices are removed from cache.
- Newer timestamps win across app/widget cache synchronization.
- Case-insensitive DeviceID duplicates are rejected.
- Case-insensitive device-name duplicates are detected but allowed.
- Legacy same-ID-different-case rows are detected for row disambiguation.
- Case-preserving unknown-device routing remains covered.

