# Smart Frequent Exit Fence and Quality Gate

Date: 2026-06-06

## Summary

Real-device diagnostics from two devices showed that Smart frequent background updates could activate later than desired during walking, because the app waited for a second significant-change callback after relaunch. They also showed a reboot/stationary false activation where Core Location reported non-zero GPS speed with almost no displacement.

This follow-up keeps standard significant-change tracking and manual frequent tracking unchanged, but makes Smart frequent activation use stronger movement evidence.

## Implementation

- Smart waiting mode now maintains one hidden geographic exit fence around the last usable location.
- The fence uses a 150 m radius, clamped to `maximumRegionMonitoringDistance`, and is active only while Smart is enabled, manual frequent is off, Smart runtime is inactive, tracking is enabled, Always authorization is available, and region monitoring is supported.
- Exiting the fence activates Smart frequent runtime immediately and starts frequent background updates.
- Smart location-triggered activation now goes through a quality-aware evidence classifier:
  - region exit;
  - trusted GPS speed;
  - trusted derived speed backed by meaningful displacement.
- The first cold/background startup batch is stricter: GPS speed alone cannot activate Smart unless displacement or region-exit evidence confirms movement.
- Derived speed now requires sane elapsed time and displacement that is larger than the frequent movement threshold and materially larger than horizontal-accuracy noise.

## Unchanged Behavior

- Standard significant-change updates still upload according to the existing location acceptance rules.
- Manual frequent mode still bypasses Smart activation/deactivation criteria.
- Smart inactivity deactivation still uses the shared inactivity window and frequent distance filter.

## Diagnostics

Smart activation diagnostics now include the evidence kind, startup-guard state, speed accuracy, displacement, elapsed time, and exit-fence radius where relevant. This should make future exported logs explain whether Smart started from a region exit, GPS speed, or derived movement.

## Validation

Validated with:

```sh
./miataru/scripts/test-unit.sh
```

The unit suite passed 172 tests, including coverage for stationary reboot speed noise, same-second derived-speed spikes, walking displacement activation, exit-fence eligibility/radius, and existing manual/significant-change behavior.
