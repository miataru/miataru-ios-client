# Smart Frequent Accuracy Recovery

Date: 2026-06-08

## Summary

Diagnostics showed a Smart frequent runtime with the default 100 m frequent
distance filter receiving very coarse background fixes while movement was still
ongoing. Those fixes could keep parts of the runtime alive while also being too
imprecise to use as the current location, upload payload, Smart movement anchor,
speed reference, persisted seed, or exit-fence center.

This change adds an internal accuracy-recovery layer for Smart frequent runtime.
The user-visible frequent distance filter remains 100 m; only the temporary
Core Location configuration is boosted when quality falls apart.

## Behavior

Recovery is eligible only when all of these are true:

- the app is in background;
- Smart frequent updates are enabled;
- manual frequent background updates are off;
- Smart runtime is active (`probing` or `confirmedActive`);
- the configured frequent background distance filter is 100 m.

Recovery starts immediately for a frequent-background fix with
`horizontalAccuracy >= 1000 m`. It also starts after two consecutive
frequent-background fixes with `horizontalAccuracy > 300 m`.

While recovery is active, Miataru reapplies frequent background tracking with:

```text
distanceFilter = 10 m
desiredAccuracy = kCLLocationAccuracyNearestTenMeters
```

Recovery stops after the first frequent-background fix with
`horizontalAccuracy <= 100 m` or after 120 seconds. After it stops, Miataru
returns to the normal configured 100 m frequent mode and observes a 10 minute
cooldown before another recovery attempt can start.

The concrete 1414 m diagnostic sample is not a configured threshold. It is an
example of a coarse fix that is worse than the 100 m acceptance gate and above
the 1000 m immediate-recovery threshold.

## Acceptance Rules

Frequent-background callbacks while the app is in background now require:

```text
horizontalAccuracy <= max(configuredFrequentDistanceFilter, 50 m)
```

At the default 100 m filter, a 28.6 m fix remains accepted and a 1414 m fix is
rejected. Rejected fixes are logged as
`locationAcceptance|rejected|accuracyQuality`. They can still inform diagnostics
and accuracy recovery, but they cannot update `currentLocation`, enter the
upload/outbox path, persist a Smart seed, refresh speed or movement anchors, or
become an exit-fence center.

Smart state helpers keep their existing 300 m usability ceiling for derived
movement and fence anchors, so 1000 m-class fixes are never used as Smart
movement/fence state even if Core Location delivers them during recovery.

## Side Effects

- Short recovery windows can increase battery use and visible background
  location activity because Core Location is asked for 10 m / nearest-ten-meter
  updates.
- Indoor, weak-GPS, or radio-only situations may produce fewer uploads because
  coarse 1 km-class fixes are now discarded instead of sent.
- If iOS still cannot provide a useful fix during the 120 second recovery
  window, Smart frequent falls back through the normal inactivity/watchdog
  behavior rather than publishing an inaccurate position.
- Manual frequent mode benefits from the background accuracy acceptance gate,
  but the temporary 10 m recovery boost is intentionally limited to Smart
  frequent with the 100 m configured filter.

## Validation

Validated with:

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=miataru Tests - iPhone 16,OS=26.5' -only-testing:miataruTests
git diff --check
```

The focused unit suite passed 189 tests, including coverage for immediate
recovery from a 1414 m fix, the two-sample >300 m trigger, 10 m /
nearest-ten-meters recovery configuration, 120 second timeout, 10 minute
cooldown, 28.6 m acceptance at the 100 m filter, and continued rejection of
1000 m-class Smart fence anchors.
