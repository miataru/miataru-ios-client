# Location Tracking State Machines

Date: 2026-06-07

## Summary

This document is the canonical if-then reference for Miataru's current
location-tracking modes. `LocationManager` resolves one service-level Core
Location mode and overlays Smart frequent runtime phases on top of the normal
background policy.

The service-level modes are:

- `stopped`
- `foregroundHighAccuracy`
- `backgroundSignificantChange`
- `backgroundFrequent`

The user-facing background states are:

- foreground/live
- standard background mode
- Smart waiting
- Smart frequent active
- manual frequent active

## Shared Preconditions

Tracking is eligible only if the user has enabled location tracking and the
DeviceKey/auth state is not blocked.

If DeviceKey authentication is blocked, then `LocationManager` stops tracking
immediately, stops all Core Location services, and does not resolve another
active tracking mode until the block is cleared.

If location authorization is `authorizedAlways`, then background tracking can
run.

If location authorization is `authorizedWhenInUse`, then foreground tracking can
run while the app is active, but background tracking resolves to `stopped`.

If location authorization is denied, restricted, or not determined, then the
service-level mode resolves to `stopped`.

## Service-Level Resolver

The resolver is intentionally small:

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

The app can force the lifecycle context when needed. For example, entering the
background applies the background policy immediately even if UIKit state has not
fully settled yet.

## Stopped Mode

Enter `stopped` when:

- tracking is off;
- DeviceKey/auth is blocked;
- authorization is missing, denied, or restricted;
- the app is in background with only `When In Use` authorization.

Actions:

- stop primary standard location updates;
- stop primary significant-change monitoring unless a higher-level recovery path
  is explicitly maintaining it;
- stop the secondary frequent manager;
- stop heading and foreground timers;
- stop frequent background activity sessions;
- stop Smart frequent runtime state.

No location uploads are expected from this mode. If a stale callback arrives
after services were stopped, normal duplicate and stale-callback cleanup rules
still protect the upload path.

## Foreground High Accuracy

Enter `foregroundHighAccuracy` when:

- tracking is active;
- the app is active;
- authorization is either `Always` or `When In Use`.

Actions:

- run high-accuracy standard updates on the primary manager;
- use `kCLLocationAccuracyBestForNavigation`;
- use `kCLDistanceFilterNone`;
- keep the foreground live timer active;
- start heading updates when available;
- keep the background indicator off;
- stop the secondary frequent manager.

If authorization is `Always`, the app can also keep the significant-change
recovery anchor registered while foreground updates run. This protects relaunch
and background continuity without changing the foreground user experience.

Focused navigation registers a navigation location session, but it does not
bypass lifecycle policy: foreground still resolves to high accuracy, and
background still resolves through the background policy.

Smart or manual frequent preferences can remain set while the app is active,
but the foreground resolver still uses `foregroundHighAccuracy`. Smart
activation, confirmation, inactivity, and watchdog decisions are background-only
decisions.

## Standard Background Mode

Enter `backgroundSignificantChange` when:

- tracking is active;
- authorization is `Always`;
- the app is not active;
- effective frequent background updates are false.

Actions:

- stop primary standard updates;
- start primary significant-change monitoring;
- stop the secondary frequent manager;
- keep the background indicator off;
- keep the Always service session while eligible;
- maintain the significant-change recovery anchor.

This is the default battery-saving background mode. It is also the Smart
waiting service mode.

If Smart frequent is enabled and manual frequent is off, then standard
background mode also maintains a hidden Smart exit fence when possible:

```text
if tracking is enabled
and authorization is Always
and DeviceKey/auth is not blocked
and Smart is enabled
and manual frequent is off
and Smart runtime is waiting
and region monitoring is available
and the app is not active:
    maintain one exit fence around the last usable location
else:
    remove the Smart exit fence
```

The Smart exit-fence radius is:

```text
min(max(150 m, frequentDistanceFilter), maximumRegionMonitoringDistance)
```

## Manual Frequent Background Mode

Manual frequent background mode is the explicit user override. It becomes
available after Smart frequent is enabled, but while manual mode is on it
ignores Smart activation and deactivation criteria.

Enter manual frequent mode when:

- tracking is active;
- authorization is `Always`;
- app is not active;
- manual frequent background updates are enabled;
- frequent mode has not expired;
- low-battery auto-disable has not disabled it.

Actions:

- keep the primary manager registered for significant-change recovery;
- run standard background updates on the secondary frequent manager;
- set the secondary manager's distance filter from the frequent setting;
- use `kCLLocationAccuracyNearestTenMeters` for 50 m or lower distance filters;
- use `kCLLocationAccuracyHundredMeters` for larger distance filters;
- set `allowsBackgroundLocationUpdates = true`;
- set `pausesLocationUpdatesAutomatically = false`;
- set `showsBackgroundLocationIndicator = true`;
- maintain `CLBackgroundActivitySession`;
- apply frequent delivery-delay and visitor-check cadence settings.

Frequent-background callbacks from the secondary manager bypass the normal
Location Sensitivity rejection check in this mode. They still pass through the
shared coordinate/timestamp validation, frequent-background accuracy quality
gate, and duplicate-upload key before server submission or outbox enqueueing.

Manual frequent duration options are finite or unlimited. If a finite duration
expires, then manual frequent is disabled and the app falls back to standard
background mode.

If battery level is known and at or below the configured frequent-background
threshold, then manual frequent is disabled, reminder/expiration notifications
are cancelled, a low-battery notification is sent, and the app falls back to
standard background mode.

## Smart Frequent Runtime

Smart frequent is a policy layer, not a separate Core Location service mode.
It has three internal phases:

```text
waiting -> probing -> confirmedActive -> waiting
```

`smartFrequentBackgroundRuntimeActive` is true in `probing` and
`confirmedActive`.

### Waiting

Enter or remain in `waiting` when:

- Smart frequent is enabled;
- manual frequent is off;
- the app is in standard background mode;
- no Smart frequent runtime is active.

Actions:

- use standard significant-change background tracking;
- maintain the Smart exit fence when eligible;
- do not run frequent standard updates;
- do not show the background location indicator for Smart;
- do not send Smart active/deactive notifications.

### Activation Evidence

`waiting` can switch to `probing` only in background and only from one of these
evidence types:

- Smart exit-fence exit;
- trusted GPS speed;
- trusted derived movement in Hybrid detection mode.

The configured Smart speed threshold defaults to 10 km/h and can be 2, 5, 10,
15, 20, or 30 km/h. Speeds above 200 km/h are rejected as implausible.

GPS speed evidence is trusted when:

```text
CLLocation.speed is finite and >= 0
and speedKmh >= configured threshold
and speedKmh <= 200
and speedAccuracy is finite, >= 0, and <= 2 m/s
and the startup guard is not blocking GPS-only evidence
```

If GPS speed accuracy is not trusted, then GPS speed can still activate only
when meaningful displacement confirms it and the update is not the first cold
startup batch.

Derived movement is available only in Hybrid mode. It is trusted when:

```text
current and previous locations are usable
and both horizontal accuracies are valid and <= 300 m
and elapsed time is >= 5 s and <= 30 min
and derived speed >= configured threshold
and derived speed <= 200 km/h
and distance >= max(frequentDistanceFilter, (currentAccuracy + previousAccuracy) * 1.25)
```

Activation freshness:

```text
if evidence is region exit or trusted GPS speed:
    current location timestamp must be newer than the inactivity window
if evidence is trusted derived speed:
    current location timestamp and previous reference timestamp must both be newer than the inactivity window
```

### Probing

Enter `probing` when activation evidence passes.

Actions:

- set Smart runtime active;
- immediately resolve effective background mode to `backgroundFrequent`;
- start secondary frequent standard updates;
- show the background location indicator;
- seed the movement anchor;
- schedule the inactivity timer;
- schedule the runtime watchdog;
- write Smart activation diagnostics with result `probing`;
- do not send the Smart activation notification yet.

Frequent-background callbacks received during `probing` are upload-preserved:
the normal Location Sensitivity threshold cannot reject them from the upload
path. Duplicate callbacks with the same timestamp/coordinate key are still
skipped. A preserved point confirms Smart only if it also crosses the Smart
movement threshold below.

This is intentional: the device can show the blue location indicator before the
user receives a Smart active notification. The notification waits for confirmed
movement.

### Runtime Watchdog

After entering `probing`, the watchdog checks after 75 seconds. The watchdog
continues after confirmation, so `confirmedActive` remains protected against a
silent loss of frequent-background callbacks.

If a processable frequent-background sample arrived within the watchdog window,
then the watchdog is rescheduled and the recovery attempt counter is reset.

If no frequent-background callback arrived, then:

```text
if recovery attempts < 2:
    log smartFrequentRecovery
    reapply background frequent tracking
    reassert the frequent background activity session
    call requestLocation() on the secondary frequent manager
    schedule the watchdog again
else:
    deactivate Smart runtime back to waiting
    reapply background tracking
    send Smart deactivation notification if the runtime was confirmed active
    and mode-change notifications are enabled
```

Missing frequent callbacks are treated as recovery evidence, not as stillness.
The normal inactivity path is reserved for the case where callbacks continue but
no relevant movement is confirmed within the configured inactivity window.

### Accuracy Recovery

Smart frequent has an additional accuracy-recovery layer for the default 100 m
frequent distance filter. It is internal only: the user's configured 100 m
filter remains unchanged in Settings and diagnostics.

Accuracy recovery is eligible only when:

```text
app is not active
and Smart frequent is enabled
and manual frequent is off
and Smart runtime is probing/confirmedActive
and the configured frequent distance filter is 100 m
```

Poor frequent-background fixes still count as delivered callbacks for the
runtime recovery watchdog, but they do not automatically become accepted app
locations.

Recovery starts when either condition is true:

```text
horizontalAccuracy >= 1000 m
or two consecutive frequent-background fixes have horizontalAccuracy > 300 m
```

While recovery is active, the service-level frequent configuration is
temporarily boosted to:

```text
distanceFilter = 10 m
desiredAccuracy = kCLLocationAccuracyNearestTenMeters
```

Recovery stops when the first frequent-background fix has
`horizontalAccuracy <= 100 m` or when 120 seconds elapse. After recovery stops,
Miataru returns to the normal 100 m frequent configuration and will not start
another accuracy recovery attempt for 10 minutes.

If iOS still delivers only coarse positions during recovery, the normal Smart
inactivity and watchdog paths decide whether to keep reasserting frequent
tracking or return to Smart waiting. This is preferred over uploading a wrong
1 km-class position.

### Confirmation

`probing` switches to `confirmedActive` only when an accepted location comes
from the secondary frequent-background manager while the app is in background
and movement is confirmed.

The confirmation threshold is:

```text
max(frequentDistanceFilter, max(anchorHorizontalAccuracy, currentHorizontalAccuracy))
```

If the accepted frequent-background point moved at least that threshold from the
current Smart movement anchor, then:

- switch phase to `confirmedActive`;
- send exactly one Smart activation notification if Smart mode-change
  notifications are enabled;
- keep the runtime watchdog scheduled;
- keep the inactivity timer aligned to relevant movement;
- log Smart activation diagnostics with result `confirmedActive`.

### Confirmed Active

While `confirmedActive`, the app stays in frequent background mode as long as
relevant movement continues inside the inactivity window.

Frequent-background callbacks remain upload-preserved in `confirmedActive`.
Location Sensitivity can still reduce foreground/standard-background UI churn,
but it does not drop points that Core Location delivered from the active
frequent background manager.

Relevant movement updates the Smart movement anchor when:

```text
distance from anchor >= max(frequentDistanceFilter, max(anchorHorizontalAccuracy, currentHorizontalAccuracy))
```

The inactivity timeout is always:

```text
lastRelevantMovementAt + configured inactivity window
```

The configured inactivity window can be 5, 10, 15, or 30 minutes and defaults
to 10 minutes.

If frequent-background callbacks stop while `confirmedActive`, the runtime
watchdog treats that as a gap and reasserts the frequent manager up to two
times. Exhaustion returns Smart to `waiting`, restores standard background
tracking/fence behavior, and sends the Smart deactivation notification when the
confirmed runtime previously sent the Smart activation notification.

Because a normal timer cannot wake an iOS app after suspension, `confirmedActive`
also keeps a Smart recovery exit-fence around the latest usable movement anchor.
If that region exits before frequent callbacks resume, the exit event reasserts
frequent background updates, requests a fresh secondary-manager location, and
waits for a real location callback before arming the next recovery fence.

### Deactivation

Smart runtime returns to `waiting` when:

- no relevant movement was confirmed within the configured inactivity window;
- Smart frequent is turned off;
- tracking is turned off;
- manual frequent is turned on;
- DeviceKey/auth blocks tracking;
- low-battery auto-disable applies to effective frequent mode;
- the runtime watchdog exhausts its recovery attempts.

Deactivation actions:

- switch phase to `waiting`;
- clear movement/probe/watchdog runtime state;
- stop frequent standard updates on the next tracking-mode application;
- restore standard significant-change background mode when still eligible;
- recreate the Smart exit fence when eligible.

The Smart deactivation notification is sent only if an activation notification
was previously delivered for the same Smart runtime attempt. This avoids the
old "deactivated immediately followed by activated" notification sequence after
foreground recovery or failed probing.

## Location Acceptance and Upload Across Modes

All modes share the same accepted-location and upload path.

Core Location batches are filtered for valid coordinates/timestamps and then
processed chronologically. Samples that are implausibly future-dated, too old,
or older than the freshest already accepted raw/current/Smart reference
location are rejected before they can update local cache, Smart seed state,
fence anchors, diagnostics counters, or upload decisions. Delayed but still
fresh significant-change wake locations remain processable.

Location Sensitivity normally rejects accepted-location candidates that moved
less than the configured UI threshold and did not improve accuracy enough.
There is one deliberate background exception:

```text
if app is not active
and callback source is the secondary frequent-background manager
and (manual frequent is enabled OR Smart phase is probing/confirmedActive):
    accept for the shared upload path even when Location Sensitivity thresholds are not met
```

This prevents Smart probing/active and manual frequent tracking from receiving
Core Location points that never reach the server. The exception does not bypass
invalid-coordinate filtering, stale frequent callback suppression, frequent
background accuracy quality checks, upload deduplication, delivery delay,
visitor cadence, or outbox retry policy.

For frequent-background callbacks while the app is not active, horizontal
accuracy must be at least as good as:

```text
max(configuredFrequentDistanceFilter, 50 m)
```

At the default 100 m filter this means a frequent-background fix must have
`horizontalAccuracy <= 100 m` before it can update `currentLocation`, seed Smart
state, refresh speed/movement anchors, or enter the upload/outbox path. A
28.6 m fix is accepted; a 1414 m fix is rejected and logged as
`locationAcceptance|rejected|accuracyQuality`. The numeric 1414 m value is not a
threshold, just an example of a very coarse fix from real diagnostics.

Smart-derived state anchors are additionally capped at 300 m horizontal
accuracy, so 1000 m-class fixes cannot become speed references, movement
anchors, persisted Smart seeds, or Smart exit-fence centers.

Upload deduplication uses:

```text
timestamp seconds + latitude microdegrees + longitude microdegrees
```

If a parallel primary/secondary callback delivers the same location, the second
upload is skipped.

For background uploads, the app starts a short background-task token around the
async upload path.

Frequent background delivery delay and visitor-history check interval apply
only when the app is not active and effective frequent updates are enabled.

The persistent FIFO outbox preserves original payload metadata. Uncertain
`updateLocation` failures are queued rather than dropped:

- transient network errors;
- retryable HTTP status responses;
- `decodingError`;
- `invalidResponse` without a clear 401/403 auth context.

Clear auth/DeviceKey failures remain non-retryable and keep the existing auth
blocking behavior.

## Diagnostics

The diagnostics log records:

- resolved service-level tracking mode;
- Smart runtime phase transitions;
- Smart activation evidence;
- Smart recovery watchdog reassertions;
- Smart frequent accuracy recovery start/stop events;
- frequent-background accuracy-quality rejections;
- frequent manager background/indicator/session state;
- upload queued/sent/failed/flushed state;
- API error category and retryability for failed uploads;
- outbox flush metadata including original location timestamp, enqueue time,
  flush time, attempt count, history flag, retention, and server URL.

## Operational Notes

Smart frequent runtime state is in memory. After process relaunch, Smart starts
in `waiting`. A fresh persisted Smart seed may be restored only if it is newer
than the configured inactivity window and has valid coordinates and horizontal
accuracy.

After a reboot or system relaunch, the significant-change recovery anchor is the
durable wake mechanism. Smart frequent can escalate again when a fresh exit
fence, trusted GPS speed, or trusted derived movement evidence is observed.
