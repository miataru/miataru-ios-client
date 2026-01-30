---
name: Periodic Location Updates
overview: Add time-based periodic location updates to the Miataru server. Currently, updates are only sent when location changes significantly. This plan adds a configurable time interval (1-24 hours) so updates are sent periodically even if location hasn't changed, ensuring battery level and other data stay current.
todos:
  - id: add_setting
    content: "Add periodicLocationUpdateIntervalHours setting to SettingsManager with UserDefaults persistence (default: 2 hours)"
    status: completed
  - id: persist_last_update
    content: Persist lastServerUpdate to UserDefaults in LocationManager and load it on init
    status: completed
  - id: time_based_check
    content: Modify locationManager(_:didUpdateLocations:) to check time elapsed since lastServerUpdate and send update if threshold exceeded
    status: completed
  - id: add_ui_picker
    content: Add Picker for periodic update interval in iPhone_SettingsView within location tracking settings section
    status: completed
  - id: add_localizations
    content: Add localization strings for periodic update interval (title, explanation, hour labels) to Localizable.xcstrings for all 10 languages
    status: completed
---

# Implementation Plan: Periodic Location Updates

## Overview

Currently, `LocationManager` only sends location updates to the server when the location changes significantly (based on distance/accuracy thresholds). This plan adds a time-based criteria: updates will also be sent periodically at a user-configurable interval (1-24 hours), even if the location hasn't changed. This ensures battery level and other metadata stay current on the server.

## Architecture

The implementation will modify the location update decision logic in `LocationManager.swift` to check both:

1. **Location change criteria** (existing): Distance/accuracy thresholds
2. **Time-based criteria** (new): Time elapsed since last server update

## Implementation Details

### 1. Add Setting for Periodic Update Interval

**File**: `miataru/SettingsManagers/App Settings/SettingsManager.swift`

- Add new `@Published` property `periodicLocationUpdateIntervalHours: Int` (range: 1-24 hours)
- Store in UserDefaults with key `periodic_location_update_interval_hours`
- Default value: 2 hours (120 minutes)
- Add key to `Keys` enum

### 2. Persist Last Server Update Time

**File**: `miataru/LocationManagers/LocationManager.swift`

- Currently `lastServerUpdate` is only in memory (`@Published var lastServerUpdate: Date?`)
- Add UserDefaults persistence for `lastServerUpdate` so it survives app restarts
- Load persisted value in `init()`
- Save value whenever `lastServerUpdate` is set (in `sendLocationToServer`)

### 3. Modify Location Update Logic

**File**: `miataru/LocationManagers/LocationManager.swift`

In `locationManager(_:didUpdateLocations:)` method (around line 497):

- After checking location change criteria (lines 512-532), add a time-based check
- If location update was NOT accepted based on distance/accuracy, check if enough time has passed since `lastServerUpdate`
- Calculate time threshold: `settings.periodicLocationUpdateIntervalHours * 3600` seconds
- If `lastServerUpdate == nil` OR `timeSinceLastUpdate >= threshold`, accept the update and send to server
- This ensures periodic updates even when stationary

### 4. Add UI Setting

**File**: `miataru/views/iPhone/Settings Views/iPhone_SettingsView.swift`

- Add new Picker in the "activity_type_accuracy_settings_title" section (after location sensitivity picker, around line 69)
- Picker options: 1 hour, 2 hours, 3 hours, 4 hours, 6 hours, 8 hours, 12 hours, 24 hours
- Use localized strings for labels
- Add explanation text below the picker

### 5. Add Localization Strings

**File**: `miataru/Assets/Localizable.xcstrings`

Add new localization keys for all 10 supported languages:

- `periodic_location_update_interval_title`: "Periodic location update interval"
- `periodic_location_update_interval_explanation`: "Even if your location hasn't changed, the app will send updates to the server at least this often. This ensures battery level and other information stays current."
- Individual hour labels: `periodic_update_1_hour`, `periodic_update_2_hours`, etc.

### 6. Background Considerations

The existing significant location change monitoring in background mode will continue to work. When a significant location change occurs, the time check will also run. For truly stationary devices, the next significant location change (which can be triggered by iOS when the device moves even slightly) will trigger the time-based update.

## Files to Modify

1. `miataru/SettingsManagers/App Settings/SettingsManager.swift` - Add new setting property
2. `miataru/LocationManagers/LocationManager.swift` - Add time-based check and persist lastServerUpdate
3. `miataru/views/iPhone/Settings Views/iPhone_SettingsView.swift` - Add UI picker
4. `miataru/Assets/Localizable.xcstrings` - Add localization strings

## Testing Considerations

- Verify updates are sent when time threshold is reached even if location hasn't changed
- Verify updates are still sent immediately when location changes significantly
- Verify setting persists across app restarts
- Verify `lastServerUpdate` persists across app restarts
- Test with different interval values (1 hour, 24 hours)
- Verify behavior in both foreground and background modes