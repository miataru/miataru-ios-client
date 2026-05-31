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
- 2 hours
- 3 hours
- 4 hours (default)
- 12 hours
- 24 hours
- Never

The expiration is stored as a date when the option is enabled or when the duration changes. Once the date has passed, the app disables the frequent mode and returns to significant-change monitoring automatically. The "Never" option stores no expiration date.

As of 2026-05-31, the finite duration list includes the additional 2-hour and 3-hour options. Existing installs keep their saved duration unchanged. Values that were valid before this change remain valid, and any unsupported stored value is still normalized back to the 4-hour default.

When the mode is enabled with "Never", Miataru schedules a repeating local reminder notification every 24 hours while normal location tracking is also enabled. The reminder is not rescheduled on every app launch or setting refresh, so the 24-hour timer is not accidentally pushed out forever. If the user turns location tracking off, disables frequent background updates, or changes the duration back to a finite value, the pending reminder and any delivered reminder are removed.

For finite durations, Miataru also schedules a one-shot local notification at the stored expiration date. That notification tells the user that the temporary frequent-background mode ended and Miataru has returned to the standard background update mode. If the user manually disables the mode before the expiration date, the pending expiration notification is removed. If the automatic expiration is already due, the notification is left in place so the settings refresh that turns the mode off cannot accidentally cancel the user-facing notice.

Users can also choose how frequent background updates are delivered to the server:

- Immediately (default)
- Every 30 seconds
- Every minute
- Every 5 minutes
- Every 10 minutes

Delayed delivery stores updates in the persistent local outbox first. The first delayed update starts a delivery window; additional updates that arrive before that window closes share the same release time. When the window is reached, the queued updates are flushed together through the existing FIFO delivery path.

When frequent background updates are enabled, users can also choose how often Miataru checks visitor history after successful background uploads:

- Every update
- Every minute
- Every 5 minutes
- Every 10 minutes (default)
- Every 30 minutes
- Every hour

This affects the Unknown Visitor Alerts follow-up request only. Location uploads continue to use the selected server-delivery behavior. The 10-minute default reduces repeated `GetVisitorHistory` requests while preserving the old "every update" behavior as an explicit option.

The in-app Advanced Options screen shows a localized explanation for the currently selected movement threshold, auto-disable duration, delivery mode, and visitor-check interval. These explanations make the battery, network, and behavior tradeoffs visible without requiring an extra alert.

Because this mode uses regular background location updates instead of significant-change monitoring, the settings view shows a localized red warning while the option is enabled to explain the expected higher battery usage.

## Runtime Behavior

`SettingsManager` owns the new persisted settings and normalizes unsupported distance or duration values back to the shipped defaults. The DeviceKey recovery/reset snapshot now includes these settings so that identity changes do not silently reset the user's background-tracking preference.

`LocationManager` keeps the existing significant-change path as the default. Only when the frequent mode is enabled and not expired does it start regular background location updates with the selected `distanceFilter`. Expiration is checked on startup, app foreground/background transitions, tracking-mode updates, setting changes, timer expiry, and incoming background location updates.

When delayed delivery is selected, `LocationManager` passes the selected delay only for non-active app states while frequent background updates are enabled. Foreground updates and the default significant-change mode continue to use immediate delivery.

For frequent background uploads, `LocationManager` also passes the selected visitor-check minimum interval into the delivery path. Immediate successful sends call `UnknownVisitorAlertService` with that interval; queued sends persist the interval on the outbox item so a later flush still applies the same throttling decision.

`LocationUpdateDeliveryCoordinator` stores delayed updates with an `availableAfter` timestamp. Periodic, network-recovery, and app-activation flushes respect that timestamp, while explicit manual/server-change flushes can drain the queue immediately. When a queued item is delivered, its stored visitor-check interval is forwarded to the unknown-visitor alert processing path.

`UnknownVisitorAlertService` stores the last background visitor-check attempt timestamp. If the next successful frequent-background upload arrives before the configured interval has elapsed, the visitor-history request is skipped. Foreground uploads and the unchanged significant-change background default do not pass an interval and therefore keep the previous behavior.

`FrequentBackgroundTrackingReminderService` owns the 24-hour repeating local notification for the "Never" duration and the one-shot expiration notification for finite durations. It requests alert/sound notification permission only when the active combination requires a notification, keeps an existing pending reminder instead of resetting its trigger, and cancels pending notifications whenever they are no longer relevant. The expiration notification stores its target date so manual disables can cancel future notifications while automatic expiry cannot swallow a notification that is already due. The notifications carry Miataru notification-type markers so the app delegate can distinguish them from unknown-visitor alerts.

`AppNavigationCoordinator` handles reminder and expiration notification taps. The app delegate routes the tap to the Settings tab, and the settings view opens Advanced Options programmatically so the frequent-background setting is visible.

The location-status view now shows whether background tracking is using significant-change monitoring or frequent updates. If frequent updates have a finite expiration date, the status card also shows when the mode will revert.

## Verification

Validated with:

```sh
./miataru/scripts/test-unit.sh
./miataru/scripts/test-unit.sh -only-testing:miataruTests/SettingsConfigurationTests
./miataru/scripts/test-unit.sh -only-testing:miataruTests/FrequentBackgroundTrackingReminderServiceTests
git diff --check
```
