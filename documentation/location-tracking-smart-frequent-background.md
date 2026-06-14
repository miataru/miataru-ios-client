# Location Tracking, Smart Frequent, And Background Updates

## Summary

This document is the consolidated reference for Miataru's location tracking modes, background recovery, manual frequent updates, Smart frequent runtime, diagnostics, upload/outbox behavior, and the LocationManager modularization boundary.

The current model is:

- Foreground tracking uses high accuracy while the app is active.
- Standard background tracking uses significant-change monitoring and remains the battery-saving default.
- Manual frequent background tracking is an explicit user override with distance, duration, delayed delivery, visitor-check cadence, reminders, expiry, and low-battery safeguards.
- Smart frequent background tracking is a policy layer that waits in standard mode, activates frequent runtime when movement evidence is strong enough, confirms only after accepted frequent movement, and deactivates or recovers based on inactivity and callback watchdogs.
- The location tracking health reminder is an enabled-by-default local notification guardrail for users with normal location tracking enabled. It asks the user to reopen Miataru only after no app foreground activity and no successfully sent own-location update occurred within the configured interval.

## Source Notes Consolidated

This document consolidates:

- `location-tracking-mode-resolver-2026-05-05.md`
- `frequent-background-location-updates-2026-04-26.md`
- `frequent-background-device-list-notice-2026-04-27.md`
- `frequent-background-low-battery-auto-disable-2026-04-28.md`
- `background-location-recovery-anchor-2026-05-26.md`
- `background-location-reboot-hardening-2026-05-27.md`
- `frequent-background-session-hardening-2026-05-29.md`
- `smart-frequent-background-updates-2026-06-04.md`
- `smart-frequent-updatewertung-hardening-2026-06-05.md`
- `smart-frequent-exit-fence-and-quality-gate-2026-06-06.md`
- `location-diagnostics-and-significant-change-rearm-2026-06-05.md`
- `location-tracking-state-machines-2026-06-07.md`
- `smart-frequent-accuracy-recovery-2026-06-08.md`
- `smart-frequent-inactivity-timer-recursion-fix-2026-06-09.md`
- `location-tracking-health-reminder-2026-06-14.md`
- `location-manager-modularization-2026-06-08.md`
- `miataru-retry-outbox-implementation-2026-03-04.md`
- `notification-sounds-2026-06-07.md`

## Service-Level Resolver

`LocationManager` resolves one of four Core Location service modes:

- `stopped`
- `foregroundHighAccuracy`
- `backgroundSignificantChange`
- `backgroundFrequent`

User-facing states are:

- foreground/live
- standard background mode
- Smart waiting
- Smart frequent active
- manual frequent active

Shared preconditions:

- Tracking is eligible only when location tracking is enabled and DeviceKey/auth is not blocked.
- If DeviceKey auth is blocked, stop all Core Location services and do not resolve another active mode until cleared.
- `authorizedAlways` can run background tracking.
- `authorizedWhenInUse` can run foreground tracking while active, but background tracking resolves to stopped.
- Denied, restricted, or not determined authorization resolves to stopped.

Resolver logic:

```text
if DeviceKey auth is blocked:
    stop all location services
else if tracking is not active:
    mode = stopped
else if authorization is authorizedWhenInUse:
    if app is active:
        mode = foregroundHighAccuracy
    else:
        mode = stopped
else if authorization is not authorizedAlways:
    mode = stopped
else if app is active:
    mode = foregroundHighAccuracy
else if effective frequent background updates are enabled:
    if Smart 100 m accuracy recovery is active:
        mode = backgroundFrequent(10 m, nearest-ten-meters)
    else:
        mode = backgroundFrequent(distanceFilter, desiredAccuracy)
else:
    mode = backgroundSignificantChange
```

Effective frequent background updates are:

```text
manual frequent enabled OR (Smart enabled AND Smart runtime phase is probing/confirmedActive)
```

Lifecycle contexts can be forced when needed. During background transitions the resolver evaluates the background policy immediately even if UIKit briefly still reports the previous active state.

Focused turn-by-turn navigation registers UUID-backed navigation location sessions. Sessions do not override background policy: foreground resolves to high accuracy; background resolves to significant-change or frequent background mode.

## Stopped Mode

Enter `stopped` when tracking is off, DeviceKey/auth is blocked, authorization is missing/denied/restricted, or the app is backgrounded with only When In Use authorization.

Actions:

- Stop primary standard updates.
- Stop primary significant-change monitoring unless a higher-level recovery path is explicitly maintaining it.
- Stop the secondary frequent manager.
- Stop heading and foreground timers.
- Stop frequent background activity sessions.
- Stop Smart frequent runtime state.

No uploads are expected. Stale callbacks after service shutdown still flow through duplicate and stale-callback cleanup.

## Foreground High Accuracy

Enter foreground high accuracy when tracking is active, the app is active, and authorization is Always or When In Use.

Actions:

- Run high-accuracy standard updates on the primary manager.
- Use `kCLLocationAccuracyBestForNavigation`.
- Use `kCLDistanceFilterNone`.
- Keep foreground live timer active.
- Start heading updates when available.
- Keep the background indicator off.
- Stop the secondary frequent manager.
- If authorization is Always, keep the significant-change recovery anchor registered where useful for relaunch/background continuity.

Smart/manual frequent preferences can remain set, but foreground resolver still uses foreground high accuracy. Smart activation, confirmation, inactivity, and watchdog decisions are background-only.

## Standard Background Mode

Enter `backgroundSignificantChange` when tracking is active, authorization is Always, the app is not active, and effective frequent background updates are false.

Actions:

- Stop primary standard updates.
- Start significant-change monitoring.
- Stop the secondary frequent manager.
- Keep background indicator off.
- Keep the Always service session while eligible.
- Maintain the significant-change recovery anchor.

This is the default battery-saving mode and the Smart waiting service mode.

If Smart frequent is enabled and manual frequent is off, standard background also maintains a hidden Smart exit fence when eligible:

```text
tracking enabled
and authorization is Always
and DeviceKey/auth is not blocked
and Smart enabled
and manual frequent off
and Smart runtime waiting
and region monitoring available
and app not active
```

The Smart exit-fence radius is:

```text
min(max(150 m, frequentDistanceFilter), maximumRegionMonitoringDistance)
```

## Manual Frequent Background Updates

Manual frequent background mode is the explicit user override. It is available after Smart frequent is enabled, and while manual mode is active it ignores Smart activation/deactivation criteria.

Settings:

- Toggle defaults to off.
- Distance filter choices: 100 m default, 50 m, 25 m, 10 m, 5 m.
- Duration choices: 1h, 2h, 3h, 4h default, 12h, 24h, Never.
- Server delivery delay choices: immediately default, every 30 seconds, every minute, every 5 minutes, every 10 minutes.
- Visitor-history check cadence after successful frequent uploads: every update, every minute, every 5 minutes, every 10 minutes default, every 30 minutes, every hour.
- Low-battery auto-disable threshold: 10%, 20%, 30% default, 40%, 50%.

Runtime:

- Starts regular background location updates with the selected distance filter.
- Finite durations store an expiry date and automatically disable frequent mode when due.
- Never-expiring mode schedules a repeating 24-hour reminder while normal tracking is also enabled.
- Finite durations schedule a one-shot expiration notification.
- Expiration is checked on startup, app lifecycle transitions, tracking-mode updates, setting changes, timer expiry, and incoming background locations.
- Manual disable cancels future reminder/expiry notifications. Automatic expiry does not swallow a notification that is already due.
- The DeviceKey recovery/reset snapshot preserves frequent settings.

Core Location actions:

- Keep the primary manager registered for significant-change recovery.
- Run standard background updates on the secondary frequent manager.
- Use nearest-ten-meters accuracy for 50 m or lower distance filters and hundred-meters accuracy for larger filters.
- Enable background updates, disable automatic pausing, show background indicator, and maintain a `CLBackgroundActivitySession`.
- Apply delivery delay and visitor-check cadence settings.

Low-battery behavior:

- Check battery before starting frequent mode and when background updates arrive.
- If battery is at or below threshold, turn off frequent mode, invalidate expiry timer, return to significant-change monitoring, cancel reminder/expiry notifications, and send a low-battery notification explaining current battery, threshold, and fallback to standard mode.

UI:

- Advanced Options show localized explanations for threshold, auto-disable duration, delivery mode, and visitor-check interval.
- A red warning explains higher battery use while manual frequent mode is enabled.
- Device lists show a notice when tracking is enabled and frequent background updates are active. The notice opens Advanced Options and shows expiry when finite.

## Smart Frequent Runtime

Smart frequent updates are off by default. They keep standard background mode as the normal state, then temporarily start frequent background updates when movement evidence is strong enough.

Smart settings:

- Smart frequent updates: default off.
- Speed threshold: 2, 5, 10, 15, 20, 30 km/h; default 10 km/h.
- Speed detection: Hybrid or GPS-only; default Hybrid.
- Smart inactivity window: 5, 10, 15, 30 minutes; default 10 minutes.
- Smart frequent mode-change notifications: default off.

Hybrid speed detection uses valid `CLLocation.speed` first and derived speed when GPS speed is invalid. GPS-only ignores derived speed. Activation speeds above 200 km/h are rejected as implausible.

Smart runtime state is primarily in memory. After relaunch, a fresh persisted confirmedActive marker resumes Smart frequent mode if normal tracking is still eligible; stale or ineligible markers fall back to waiting and may emit the restart-recovery deactivation notification. A fresh persisted Smart seed may become the speed reference only if it is newer than the configured inactivity window and passes plausibility checks.

The runtime phases are:

```text
waiting -> probing -> confirmedActive -> waiting
```

### Waiting

Waiting uses standard significant-change background tracking and, when eligible, maintains the hidden Smart exit fence. It does not run frequent updates or send active/deactive notifications.

### Activation Evidence

Waiting can switch to probing in background only from:

- Smart exit-fence exit.
- Trusted GPS speed.
- Trusted derived movement in Hybrid mode.

GPS speed evidence requires finite non-negative speed, configured threshold, <= 200 km/h, trusted speed accuracy <= 2 m/s, and no startup guard blocking GPS-only evidence.

Derived movement requires usable current/previous locations, both accuracies <= 300 m, elapsed time between 5 seconds and 30 minutes, derived speed within threshold and <= 200 km/h, and distance at least:

```text
max(frequentDistanceFilter, (currentAccuracy + previousAccuracy) * 1.25)
```

The cold/background startup batch is stricter: GPS speed alone cannot activate Smart unless displacement or region-exit evidence confirms movement.

### Probing

Probing starts frequent background tracking immediately, shows the background indicator, seeds movement anchor, schedules inactivity timer and watchdog, and logs activation diagnostics. It does not send the Smart activation notification yet.

Frequent-background callbacks during probing are upload-preserved but must pass shared accuracy quality gates before updating current location or Smart anchors.

### Confirmation

Probing switches to confirmedActive only when an accepted secondary frequent-background point arrives in background and movement from the Smart anchor reaches:

```text
max(frequentDistanceFilter, max(anchorHorizontalAccuracy, currentHorizontalAccuracy))
```

Confirmation sends exactly one Smart activation notification when mode-change notifications are enabled.

### Confirmed Active

Confirmed active stays in frequent background mode while relevant movement continues within the inactivity window. Relevant movement updates the anchor using the same threshold formula. The inactivity timeout is:

```text
lastRelevantMovementAt + configured inactivity window
```

If frequent callbacks stop, the runtime watchdog treats it as a recovery gap, not proof of stillness.

### Runtime Watchdog

After entering probing, the watchdog checks after 75 seconds and continues after confirmation.

If a processable frequent-background sample arrived within the window, reschedule and reset recovery attempts. If not:

```text
if recovery attempts < 2:
    log smartFrequentRecovery
    reapply background frequent tracking
    reassert CLBackgroundActivitySession
    requestLocation() on secondary manager
    schedule watchdog again
else:
    deactivate to waiting
    reapply standard background tracking
    send deactivation notification only if runtime was confirmed active and notifications are enabled
```

Because a normal timer cannot wake an iOS app after suspension, confirmedActive also maintains a Smart recovery exit fence around the latest usable movement anchor and refreshes the persisted runtime marker as relevant movement advances.

### Accuracy Recovery

Smart frequent has an internal accuracy-recovery layer only when the configured frequent distance filter is 100 m.

Eligible when:

- App is in background.
- Smart is enabled.
- Manual frequent is off.
- Smart runtime is probing or confirmedActive.
- Frequent distance filter is 100 m.

Recovery starts when:

```text
horizontalAccuracy >= 1000 m
or two consecutive frequent-background fixes have horizontalAccuracy > 300 m
```

While active:

```text
distanceFilter = 10 m
desiredAccuracy = kCLLocationAccuracyNearestTenMeters
```

Recovery ends after a frequent-background fix with `horizontalAccuracy <= 100 m` or after 120 seconds, then enters a 10-minute cooldown. Coarse fixes can inform diagnostics and recovery but cannot update current location, upload path, Smart seed, speed reference, movement anchor, or exit-fence center.

### Inactivity Timer Recursion Fix

`SmartFrequentBackgroundPolicy` exposes `InactivityTimerAction`:

- `.schedule(Date)` when callback data is fresh and timeout is future.
- `.expired` when callback data is fresh and movement has aged out.
- `.none` when timestamps are missing, window is invalid, or callback gap is stale.

The scheduler no longer calls the handler synchronously for a past date. Stale callback gaps clear `smartFrequentBackgroundNextInactivityTimeoutAt` and leave recovery to the watchdog. This prevents recursion when `lastRelevantMovementAt + inactivityWindow` is in the past but callback data is stale.

For 25 m frequent mode, accuracy acceptance remains:

```text
horizontalAccuracy <= max(configuredFrequentDistanceFilter, 50 m)
```

So 25 m mode accepts up to 50 m accuracy and rejects, for example, a 69.4 m fix.

### Deactivation

Smart returns to waiting when no relevant movement is confirmed within the inactivity window, Smart is turned off, tracking is turned off, manual frequent is turned on, DeviceKey/auth blocks tracking, low battery disables effective frequent mode, or the watchdog exhausts recovery attempts.

Deactivation clears runtime state, stops frequent updates on the next mode application, restores significant-change background tracking where eligible, and recreates the Smart exit fence where eligible.

## Location Acceptance And Upload

Core Location batches are filtered for valid coordinates/timestamps and processed chronologically. Implausibly future-dated, too old, or older-than-current samples are rejected before updating cache, Smart seeds, fence anchors, diagnostics counters, or uploads.

Location Sensitivity normally rejects candidates that moved too little and did not improve accuracy enough. Exception:

```text
if app is not active
and callback source is secondary frequent manager
and (manual frequent enabled OR Smart phase is probing/confirmedActive):
    accept for upload path even when Location Sensitivity thresholds are not met
```

This exception does not bypass invalid-coordinate filtering, stale callback suppression, frequent-background accuracy quality checks, upload deduplication, delivery delay, visitor cadence, or outbox retry policy.

Frequent-background callbacks in background require:

```text
horizontalAccuracy <= max(configuredFrequentDistanceFilter, 50 m)
```

At the default 100 m filter, 28.6 m is accepted and 1414 m is rejected as `locationAcceptance|rejected|accuracyQuality`. The 1414 m value is an example, not a threshold.

Upload deduplication uses:

```text
timestamp seconds + latitude microdegrees + longitude microdegrees
```

Background uploads are wrapped in a short background-task token.

## Retry And Outbox

The app-level retry/outbox architecture is:

- `MiataruRequestExecutor` centralizes retry behavior.
- Reads, writes, and `updateLocation` each retry once with short jittered backoff for transient failures.
- Uncertain `updateLocation` failures are queued in a persistent FIFO outbox rather than dropped.
- Clear auth/DeviceKey failures remain non-retryable and keep existing auth blocking behavior.

Outbox cases include transient network failures, retryable HTTP status responses, decoding errors, and invalid responses without a clear 401/403 auth context.

Outbox items preserve original location metadata. Delayed frequent delivery stores an `availableAfter` timestamp. Periodic, network-recovery, and app-activation flushes respect that timestamp; explicit manual/server-change flushes may drain immediately. Flushed items preserve the stored visitor-check interval.

User behavior:

- Upload errors that are probably transient are not shown as immediate destructive failures.
- Updates can be retried later without rewriting their original metadata.
- DeviceKey/auth failures still require user recovery.
- Only direct or flushed own-location updates that were accepted by the server post `.didSendOwnLocationUpdate` and count as confirmed health-reminder activity. Queued and failed sends do not reset the health-reminder clock.

## Background Recovery And Reboot Hardening

The recovery architecture separates concerns:

- The primary manager handles foreground high-accuracy updates, standard background mode switching, and frequent background `startUpdatingLocation()`.
- A dedicated recovery-anchor manager handles significant-change monitoring for reboot/system-termination recovery.
- Frequent background mode clears significant-change monitoring from the primary manager before starting standard updates; the recovery anchor remains active separately.

Launch hardening:

- `AppDelegate` restores tracking in `application(_:willFinishLaunchingWithOptions:)` for location launches.
- The same recovery check remains in `didFinishLaunchingWithOptions`, deduped per launch.
- Background location uploads get explicit background-task protection.
- `authorizedWhenInUse` is foreground-only; background recovery requires Always authorization.

Session hardening:

- Active Always-authorized tracking holds an Always `CLServiceSession`.
- Frequent background mode additionally holds a `CLBackgroundActivitySession`.
- Sessions stop when tracking stops, authorization is lost, DeviceKey blocks tracking, frequent mode is disabled/expired, or low battery disables it.
- A primary significant-change callback can reassert frequent standard updates only if frequent updates were already active in the current process, avoiding aggressive frequent restoration after cold reboot.
- In standard significant-change mode, a background primary callback reasserts significant-change monitoring again.
- The secondary frequent manager is stopped defensively when frequent mode is inactive.

iOS boundaries:

- User force-quit still prevents background relaunch until the user opens the app.
- When In Use authorization is not reboot-capable background tracking.
- Simulator reboot is not a reliable proof of significant-change relaunch.
- iOS may defer or coalesce significant-change delivery based on movement, radio state, power, and scheduling.

## Diagnostics And Re-Arm

`LocationDiagnosticsLogStore` owns an opt-in persisted diagnostics buffer:

- Setting key: `location_diagnostics_logging_enabled`, default false.
- JSON in Application Support.
- Ring buffer capped at 1000 entries.
- UI shows newest 20 entries.
- Export includes the full buffer and metadata.
- Disabling logging keeps old entries until the user clears them.

Entries include ID, timestamp, level, event, summary, result, reason, checks, and context. The log records location/tracking decisions only, not generic UI/map/device-cache logs.

Privacy:

- Latitude/longitude rounded to four decimal places.
- Accuracy, speed, distance stored numerically.
- DeviceKey and exact coordinates are not logged.
- Disabled logging exits cheaply through autoclosure-based context construction.

Significant-change re-arm:

- Runs once per app version/build after normal launch restore.
- Requires tracking enabled, Always authorization, no DeviceKey block, and no previous attempt for the current build.
- On success, enables background updates, stop/starts significant-change monitoring, resets the recovery-anchor flag, and persists attempted status.
- On failure, stores skipped status with reason.

## UI, Notifications, And Sounds

Location Tracking Details distinguishes foreground/live, significant-change, Smart waiting, Smart frequent active, and manual frequent active. It shows Smart diagnostics such as activation reason, last relevant movement, and next inactivity timeout.

Mode counters persist separately for foreground/live, standard background, Smart frequent, and manual frequent updates, and reset together after 24 hours.

Frequent-background notifications:

- 24-hour reminder for never-expiring manual frequent mode.
- One-shot expiration notification for finite manual duration.
- Low-battery auto-disable notification.
- Optional Smart frequent mode-change notifications.
- Location tracking health reminder when normal location tracking is enabled but Miataru has not been foregrounded and no own-location update has been successfully sent within the configured interval.

Location tracking health reminder:

- Notification type: `location_tracking_health_reminder`.
- Settings key: `location_tracking_health_reminder_interval_days`.
- Interval choices: 5 days default, 7 days, 14 days, 30 days.
- Confirmed activity is either app launch/foreground activation while tracking is enabled or `.didSendOwnLocationUpdate`.
- Confirmed activity stores `lastConfirmedActivityDate` and schedules one non-repeating notification for `lastConfirmedActivityDate + interval`.
- Changing the interval refreshes the pending notification from the persisted confirmed activity date rather than treating the settings change as new activity.
- Tracking disabled cancels pending and delivered health reminders and does not request notification permission.
- Notification permission is checked only when tracking is enabled and the service is about to schedule the reminder. If permission is `.notDetermined`, Miataru requests alert/sound permission; if denied, it cancels pending and delivered health reminders.
- Tapping the notification uses default iOS behavior and only opens Miataru; it is intentionally not routed to Advanced Options.

Smart mode-change notifications are sent only when enabled by the user and notification permission is granted. They fire when Smart activates after detected movement, deactivates after inactivity, or returns to standard after watchdog exhaustion. Manual overrides, disabling Smart, and low-battery auto-disable do not send Smart mode-change notifications.

Frequent-background reminder, expiration, low-battery, and Smart mode-change notification taps route to Advanced Options. The location tracking health reminder does not.

Custom notification sounds:

- Smart frequent activated: `confirm.caf`
- Smart frequent deactivated/paused: `cancel.caf`
- Unknown visitor alert: `confirm.caf`
- Frequent reminder, expiry, low-battery, and location tracking health reminder notifications keep the default iOS sound.

`MiataruNotificationSounds` centralizes the sound names. The CAF files are copied to the app bundle root so iOS can resolve them by file name.

## LocationManager Boundaries

`LocationManager.swift` remains the ObservableObject facade for published state, lifecycle hooks, permission entry points, tracking start/stop methods, navigation sessions, and delegate glue.

Extracted or supporting components:

- `LocationManager+Types.swift`: UI-facing nested names, constants, and typealiases.
- `LocationManager+PolicyCompatibility.swift`: stable static wrappers for existing tests/call sites.
- `LocationTrackingPolicy`: service mode decisions.
- `SmartFrequentBackgroundPolicy`: Smart runtime decisions.
- `LocationSamplePolicy`: sample acceptance and ordering.
- `LocationBackgroundForensics`: deterministic background gap decisions.
- `LocationBackgroundForensicsRecorder`: persisted forensics, significant-change re-arm status, background-gap and recovery-burst logs, Smart activation/deactivation timestamps, and related defaults.
- `CoreLocationServiceController`: primary/frequent managers, activity type, indicators, sessions, recovery-anchor state, frequent update state, and stale frequent-callback cleanup.
- `LocationUpdateUploadService`: upload payload and background-task handling.
- `LocationUpdateMetricsStore`: 24-hour counter persistence.
- `HeadingSmoother`: heading/course smoothing.

Preserved compatibility:

- `LocationManager.shared`
- Published properties used by SwiftUI
- nested names such as `LocationManager.ServerUpdateStatus`
- static policy wrapper methods
- existing `UserDefaults` keys
- notification names and lifecycle entry points

Deferred extraction: `SmartFrequentRuntimeController` remains a good future split but touches published diagnostics, timers, notifications, anchors, frequent callbacks, and tracking-mode application.

## Validation History

Validation across the consolidated work included:

- `./miataru/scripts/test-unit.sh`
- `./miataru/scripts/test-unit.sh -only-testing:miataruTests/SettingsConfigurationTests`
- `./miataru/scripts/test-unit.sh -only-testing:miataruTests/FrequentBackgroundTrackingReminderServiceTests`
- `xcodebuild` builds for app and simulator destinations
- focused `SettingsConfigurationTests`
- focused `LocationTrackingPolicyTests`
- focused `SmartFrequentBackgroundPolicyTests`
- focused `LocationSamplePolicyTests`
- focused `LocationBackgroundForensicsTests`
- focused `LocationUpdateMetricsStoreTests`
- `python3 -m json.tool miataru/miataru/Assets/Localization/LocationTracking.xcstrings`
- `plutil -lint "miataru/miataru/SettingsManagers/App Settings/Settings.bundle/Root.plist"`
- `git diff --check`

Coverage included defaults, Settings.bundle parity, migration, Smart prerequisite normalization, localization completeness, stale/new string-catalog detection, Hybrid/GPS-only speed detection, startup gating, implausible-speed rejection, activation/deactivation policy, manual override behavior, shared frequent interval behavior, persisted counters, Smart notifications, location tracking health-reminder scheduling and permission timing, threshold normalization, persisted seeds, chronological batch processing, exit-fence behavior, accuracy recovery, inactivity timer action behavior, diagnostics export privacy, re-arm eligibility, same-build suppression, and outbox defaults.

Manual real-device validation remains required for exact background cadence and reboot relaunch behavior.
