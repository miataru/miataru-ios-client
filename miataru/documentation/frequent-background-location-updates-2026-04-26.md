# Frequent Background Location Updates

## Problem

Miataru previously used iOS significant-change monitoring for background location tracking. That behavior is battery-friendly and remains the default, but it only wakes the app after larger movement. Some users need a temporary mode that reports background movement more often without changing the default behavior for everyone else.

## Change

Advanced Options now include an explicit frequent-background update toggle in the background location section. The toggle defaults to off, so existing users continue to use significant-change monitoring unless they opt in.

When the mode is enabled, users can choose a background distance filter:

- 100 m (default)
- 50 m
- 25 m

Users can also choose when the mode should disable itself:

- 1 hour
- 4 hours (default)
- 12 hours
- 24 hours
- Never

The expiration is stored as a date when the option is enabled or when the duration changes. Once the date has passed, the app disables the frequent mode and returns to significant-change monitoring automatically. The "Never" option stores no expiration date.

Because this mode uses regular background location updates instead of significant-change monitoring, the settings view shows a localized red warning while the option is enabled to explain the expected higher battery usage.

## Runtime Behavior

`SettingsManager` owns the new persisted settings and normalizes unsupported distance or duration values back to the shipped defaults. The DeviceKey recovery/reset snapshot now includes these settings so that identity changes do not silently reset the user's background-tracking preference.

`LocationManager` keeps the existing significant-change path as the default. Only when the frequent mode is enabled and not expired does it start regular background location updates with the selected `distanceFilter`. Expiration is checked on startup, app foreground/background transitions, tracking-mode updates, setting changes, timer expiry, and incoming background location updates.

The location-status view now shows whether background tracking is using significant-change monitoring or frequent updates. If frequent updates have a finite expiration date, the status card also shows when the mode will revert.

## Verification

Validated with:

```sh
./miataru/scripts/test-unit.sh
./miataru/scripts/test-unit.sh -only-testing:miataruTests/SettingsConfigurationTests
git diff --check
```
