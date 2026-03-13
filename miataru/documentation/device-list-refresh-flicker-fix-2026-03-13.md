# Device List Refresh Flicker Fix (2026-03-13)

## Problem
In the Devices list, rows could briefly lose nearly all supplemental information during periodic refreshes when many devices were being updated at once.

The visible symptom was a short "flash" where rows temporarily showed only the device name, followed by battery, last-seen, distance, and place information reappearing step by step.

## Root Cause
Two behaviors combined to create the flicker:

1. Device-list refreshes could overlap. When multiple triggers fired close together, more than one `getLocation` request could be in flight for the same list.
2. Cache updates were published incrementally. Each server response updated or removed devices one by one, so SwiftUI could render intermediate partial states while the list was still being rebuilt.

In addition, transient refresh failures previously cleared cached device locations completely, which made the brief empty-row state even more noticeable.

## Changes
Updated [miataru/LocationManagers/DeviceLocationRefresher.swift](../miataru/LocationManagers/DeviceLocationRefresher.swift):

- Marked the refresher as `@MainActor` to keep refresh coalescing state consistent.
- Added `inFlightRefreshTask` so overlapping device-list refresh triggers now await the same running request instead of starting competing network calls.
- Stopped clearing all cached device locations when a refresh request fails.
- Switched the refresh path to build a full location snapshot first and apply it to the cache in one step.

Updated [miataru/SettingsManagers/App Settings/Devices/DeviceLocationCacheStore.swift](../miataru/SettingsManagers/App%20Settings/Devices/DeviceLocationCacheStore.swift):

- Added `DeviceLocationSnapshot` as a lightweight refresh payload model.
- Added `applyLocationSnapshots(...)` to replace the cache contents in one consolidated publish pass.
- Preserved existing placemark/time-zone data while fresh coordinates are applied, so rows keep their last known place text until reverse geocoding catches up.
- Preserved stored speed when only position/timestamp data is refreshed.

Added [miataruTests/DeviceLocationCacheStoreTests.swift](../miataruTests/DeviceLocationCacheStoreTests.swift):

- Verifies that snapshot application publishes one consolidated cache update.
- Verifies that placemark data is preserved across snapshot refreshes.
- Verifies that devices explicitly missing from a response are removed from the cache.

## Resulting Behavior
- Device rows keep showing the last complete data set while a refresh is in progress.
- Fresh data replaces old data in place once the response is ready.
- Periodic refreshes no longer fight each other and produce transient partial list states.
- Short-lived server/network failures leave the last successful device state visible instead of blanking the list.

## Tradeoffs
- A failed refresh now keeps stale data visible for a bit longer instead of showing an obviously empty state.
- A manual refresh that starts while an automatic refresh is already running will reuse the active request instead of forcing a second concurrent one.

## Verification
- Built app target successfully:
  - `xcodebuild build -project miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,id=845BE152-763F-4E65-840A-CBA1018645C1'`
  - Result: `** BUILD SUCCEEDED **`
- Added focused unit tests for the snapshot cache path.
- Attempted a targeted `xcodebuild test` run for `miataruTests/DeviceLocationCacheStoreTests`; compilation completed, but the simulator test runner stalled before producing a final test result.
