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

Users can also choose how frequent background updates are delivered to the server:

- Immediately (default)
- Every 30 seconds
- Every minute
- Every 5 minutes
- Every 10 minutes

Delayed delivery stores updates in the persistent local outbox first. The first delayed update starts a delivery window; additional updates that arrive before that window closes share the same release time. When the window is reached, the queued updates are flushed together through the existing FIFO delivery path.

The in-app Advanced Options screen shows a localized explanation for the currently selected movement threshold, auto-disable duration, and delivery mode. These explanations make the battery and behavior tradeoffs visible without requiring an extra alert.

Because this mode uses regular background location updates instead of significant-change monitoring, the settings view shows a localized red warning while the option is enabled to explain the expected higher battery usage.

## Runtime Behavior

`SettingsManager` owns the new persisted settings and normalizes unsupported distance or duration values back to the shipped defaults. The DeviceKey recovery/reset snapshot now includes these settings so that identity changes do not silently reset the user's background-tracking preference.

`LocationManager` keeps the existing significant-change path as the default. Only when the frequent mode is enabled and not expired does it start regular background location updates with the selected `distanceFilter`. Expiration is checked on startup, app foreground/background transitions, tracking-mode updates, setting changes, timer expiry, and incoming background location updates.

When delayed delivery is selected, `LocationManager` passes the selected delay only for non-active app states while frequent background updates are enabled. Foreground updates and the default significant-change mode continue to use immediate delivery.

`LocationUpdateDeliveryCoordinator` stores delayed updates with an `availableAfter` timestamp. Periodic, network-recovery, and app-activation flushes respect that timestamp, while explicit manual/server-change flushes can drain the queue immediately.

The location-status view now shows whether background tracking is using significant-change monitoring or frequent updates. If frequent updates have a finite expiration date, the status card also shows when the mode will revert.

## Verification

Validated with:

```sh
./miataru/scripts/test-unit.sh
./miataru/scripts/test-unit.sh -only-testing:miataruTests/SettingsConfigurationTests
git diff --check
```
