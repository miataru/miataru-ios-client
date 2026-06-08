# Smart Frequent Background Updates

Date: 2026-06-04

## Summary

Miataru 3.2 changes frequent background tracking from one flat manual toggle into a two-stage model:

- Stage 1, Smart frequent updates, is off by default.
- Stage 2, manual frequent background updates, becomes available after Stage 1 is enabled and overrides Smart behavior completely.

Smart frequent updates keep the battery-saving standard background mode, backed by significant-change monitoring, as the normal state. When a significant-change update shows movement above the configured speed threshold, Smart temporarily starts frequent background updates. Frequent runtime is stopped again when the shared inactivity window expires because no location update arrived or because no relevant movement over the configured frequent distance filter was observed.

## User-Facing Behavior

Smart frequent settings live in Advanced Options under the background location section:

- Smart frequent updates: default off.
- Speed threshold: 2, 5, 10, 15, 20, or 30 km/h; default 10 km/h.
- Speed detection: Hybrid or GPS-only; default Hybrid.
- Smart inactivity window: 5, 10, 15, or 30 minutes; default 10 minutes.
- Smart frequent mode-change notifications: default off.

Hybrid speed detection uses valid `CLLocation.speed` first. If GPS speed is not valid, it derives speed from distance and elapsed time between usable location samples. GPS-only mode ignores derived speed and only uses `CLLocation.speed`. Smart activation rejects implausible activation speeds above 200 km/h so startup/reset GPS spikes do not switch frequent runtime on.

The inactivity window is shared by both Smart stop conditions:

- no location update within the selected window;
- no movement over the frequent distance filter within the selected window.

Manual frequent background updates keep the existing distance, duration, delivery delay, visitor-check interval, reminder/expiration notifications, and low-battery auto-disable behavior. Smart frequent runtime uses the same frequent distance, delivery-delay, and visitor-check interval policies. Manual mode ignores Smart activation and inactivity criteria while it is enabled.

## Migration

Existing installs with manual frequent background updates enabled are preserved. During migration, Miataru enables the Smart prerequisite and leaves manual frequent mode enabled, so the effective behavior remains manual frequent tracking after the update.

There is also startup normalization for externally changed settings: if manual frequent mode is enabled through the iOS Settings.bundle while the Smart prerequisite is off, the app re-enables the Smart prerequisite on load.

## Runtime Implementation

`LocationManager` keeps Smart runtime state in memory only. After relaunch, Smart starts in the waiting state. The first background location in a fresh process seeds Smart's speed/movement reference and cannot activate frequent runtime by itself; a later qualifying significant-change update can activate Smart once movement is measured against that in-process reference.

The effective frequent background state is:

```text
manual frequent enabled OR (Smart enabled AND Smart runtime active)
```

Smart activation only happens from primary significant-change callbacks while the app is not active. Smart runtime does not activate from foreground/live updates or from secondary frequent-manager callbacks.

Battery auto-disable acts on the effective frequent state. For manual frequent mode it turns off the manual preference; for Smart frequent runtime it only stops the Smart runtime and leaves the user's Smart preference intact.

## Notifications

`FrequentBackgroundTrackingReminderService` now owns four frequent-background notification families:

- 24-hour reminder for never-expiring manual frequent mode;
- one-shot expiration notification for finite manual frequent durations;
- low-battery auto-disable notification;
- optional Smart frequent mode-change notifications.

Smart mode-change notifications are sent only when enabled by the user. Enabling them requests notification permission first; denied permission leaves the setting off and the UI offers a shortcut to the app's system settings. They fire when Smart itself activates frequent runtime after detected movement, deactivates frequent runtime because the inactivity window elapsed, or returns to standard mode after the frequent callback recovery watchdog is exhausted. Manual overrides, disabling Smart in Settings, and battery auto-disable do not send the Smart mode-change notification.

All frequent-background notification taps route to Advanced Options through `AppDelegate` and `AppNavigationCoordinator`.

## UI and Diagnostics

The root Settings view shows Smart frequent updates with explanatory text. The manual frequent toggle is shown only when Smart is enabled and includes explanatory text that manual mode overrides Smart. While manual frequent mode is active, the Smart frequent toggle is disabled and explains that Smart can only be changed after the manual override is turned off.

Advanced Options show every Smart option with explanatory text in all supported locales. Shared frequent parameters such as distance filter, delivery delay, visitor-check interval, and battery auto-disable remain visible when Smart is active. Manual duration is shown only when manual frequent mode is enabled.

Location Tracking Details distinguishes:

- foreground/live;
- significant-change;
- Smart waiting;
- Smart frequent active;
- manual frequent active.

The status view also shows Smart diagnostics:

- last activation reason;
- last relevant Smart movement;
- next inactivity timeout.

Location update statistics now persist separate counters for foreground/live, battery-saving standard mode, Smart frequent, and manual frequent updates. The counters reset together after 24 hours. Background Status rows use distinct icons for the total, per-mode counters, active mode, expiry, Smart activation, Smart movement, and Smart timeout values.

## Localization

The feature adds localized labels, explanatory texts, picker options, diagnostic labels, and notification strings for all supported app locales. The string catalog is also kept free of stale and newly extracted translation units:

`da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`.

Settings.bundle strings are updated for the iOS Settings app where the Settings.bundle can expose the same defaults.

## Verification

Validated with:

```sh
plutil -lint "miataru/miataru/SettingsManagers/App Settings/Settings.bundle/Root.plist"
python3 -c 'import json; json.load(open("miataru/miataru/Assets/Localizable.xcstrings"))'
./miataru/scripts/test-unit.sh
git diff --check
```

The unit suite covers defaults, Settings.bundle parity, migration, Smart prerequisite normalization, localization completeness, stale/new string-catalog detection, Hybrid/GPS-only speed detection, startup-reference gating, implausible-speed rejection, activation/deactivation policy, manual override behavior, shared frequent-mode interval behavior, persisted 24-hour mode counters, and Smart mode-change notification scheduling/authorization behavior.
