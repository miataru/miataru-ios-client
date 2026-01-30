---
name: Deduplicate Device Location Refresh
overview: Extract the duplicated `refreshAllDeviceLocations` method and throttling logic from iPhone and iPad device views into a shared `DeviceLocationRefresher` service in the LocationManagers directory.
todos:
  - id: create-refresher
    content: Create DeviceLocationRefresher.swift in LocationManagers directory with refresh logic and throttling
    status: completed
  - id: update-iphone-view
    content: Update iPhone_DevicesView.swift to use DeviceLocationRefresher and remove duplicate code
    status: completed
  - id: update-ipad-view
    content: Update iPad_DevicesView.swift to use DeviceLocationRefresher and remove duplicate code
    status: completed
---

# Deduplicate Device Location Refresh Pipeline

## Current State

Both `iPhone_DevicesView.swift` and `iPad_DevicesView.swift` contain nearly identical:

- `refreshAllDeviceLocations(forceGeocoding:)` method (lines 242-283 in iPhone, 294-334 in iPad)
- NotificationCenter handlers for `.didSendOwnLocationUpdate` and `UIApplication.didBecomeActiveNotification` with identical throttling logic (lines 172-211 in iPhone, 163-202 in iPad)

The only difference is iPhone includes a debugLog statement.

## Solution

Create a shared `DeviceLocationRefresher` service that centralizes:

1. The refresh logic (API calls, cache updates, geocoding)
2. Throttling based on `mapUpdateInterval` and last refresh time
3. Conditional refresh checks (visibility, app state, auto-refresh settings)

## Implementation Steps

### 1. Create DeviceLocationRefresher

**File**: `miataru/LocationManagers/DeviceLocationRefresher.swift`

- Singleton pattern (like `LocationManager`)
- Properties:
- `lastRefresh: Date?` - shared throttle state
- `settings: SettingsManager.shared`
- `store: KnownDeviceStore.shared`
- `cache: DeviceLocationCacheStore.shared`
- Methods:
- `refreshAllDeviceLocations(forceGeocoding: Bool = false) async -> Bool` - core refresh logic
- `shouldRefresh(isVisible: Bool) -> Bool` - checks throttle, visibility, app state, and auto-refresh setting
- `refreshIfNeeded(isVisible: Bool, forceGeocoding: Bool = false) async -> Bool` - convenience method that combines checks and refresh

### 2. Update iPhone_DevicesView.swift

- Remove `refreshAllDeviceLocations` method (lines 242-283)
- Remove `@State private var lastDeviceListRefresh: Date? = nil` (line 22)
- Replace refresh calls:
- Line 155: `await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)`
- Lines 172-184: Replace notification handler with call to `DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)`
- Lines 186-198: Same replacement for `didBecomeActiveNotification` handler

### 3. Update iPad_DevicesView.swift

- Remove `refreshAllDeviceLocations` method (lines 294-334)
- Remove `@State private var lastDeviceListRefresh: Date? = nil` (line 21)
- Replace refresh calls:
- Line 142: `await DeviceLocationRefresher.shared.refreshAllDeviceLocations(forceGeocoding: true)`
- Lines 163-175: Replace notification handler with call to `DeviceLocationRefresher.shared.refreshIfNeeded(isVisible: isVisible)`
- Lines 177-189: Same replacement for `didBecomeActiveNotification` handler

## Design Decisions

1. **Shared Throttling**: The refresher manages a single `lastRefresh` timestamp, so both views share the same throttle. This prevents redundant API calls when both views are visible.

2. **Visibility Parameter**: Views pass their `isVisible` state to the refresher, keeping view-specific concerns local while centralizing refresh logic.

3. **Force Geocoding**: Manual refresh (pull-to-refresh) still uses `forceGeocoding: true` to ensure fresh geocoding data.

4. **Error Handling**: Maintain existing behavior - on error, remove all device locations from cache and return `false`.

## Files to Modify

- `miataru/LocationManagers/DeviceLocationRefresher.swift` (new file)
- `miataru/views/iPhone/iPhone_DevicesView.swift`
- `miataru/views/iPad/iPad_DevicesView.swift`