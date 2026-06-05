# Smart Frequent Update Evaluation Hardening

Date: 2026-06-05

## Summary

Real-environment testing showed two Smart frequent edge cases:

- Smart frequent runtime could activate only on the second usable background update after relaunch because the first update was used to seed the speed reference.
- A single Core Location callback can contain multiple locations, but the app previously evaluated only the last entry. That could hide usable intermediate samples and make Smart frequent updates feel sparser than the device actually delivered them.

This follow-up keeps the separate frequent/Smart movement threshold setting, avoids adding horizontal-accuracy-specific Smart logic for now, and hardens the existing update path.

## Implementation

- The frequent background movement threshold now accepts `100`, `50`, `25`, `10`, and `5` meters. The default remains `100` meters.
- The iPhone Advanced Options picker and Settings.bundle movement-threshold picker expose the new 10 m and 5 m options.
- The compact `5m` and `10m` string-catalog labels are explicitly marked as non-translatable literals with comments, while the explanatory 5 m and 10 m strings are localized across all supported app locales.
- `LocationManager` persists the last valid raw location as a Smart frequent seed. On app restore or location launch, the seed becomes the Smart speed reference only when it is fresh according to the selected inactivity window.
- Persisted seeds still flow through the existing plausible-speed guard. Derived activation speeds above the Smart frequent maximum are ignored, preventing unrealistic post-start activation.
- `didUpdateLocations` now filters invalid coordinates and non-finite timestamps, sorts the remaining locations chronologically, and evaluates each usable sample.
- Each processed sample updates raw state, Smart state, diagnostics, heading fallback, cache acceptance, and the upload queue. The tracking mode is reapplied only once at the end of the callback.
- Accepted batch locations are submitted sequentially to `LocationUpdateDeliveryCoordinator`, preserving chronological history/server order while keeping existing deduplication in place.

## Battery Implications

The new 5 m and 10 m thresholds can increase Core Location callbacks, accepted updates, server submissions, and Smart inactivity-timer resets whenever manual frequent mode or Smart frequent runtime is active.

The default Smart waiting mode remains sparse because it continues to use significant-change monitoring until Smart frequent runtime activates. Existing safeguards remain important: inactivity timeout, low-battery auto-disable, delayed delivery batching, retry outbox, and duplicate upload suppression.

## Expected Behavior

- A fresh persisted seed can allow the first post-relaunch background update to activate Smart frequent runtime if the movement and speed threshold are plausible.
- Stale, future-dated, invalid, or implausible seeds are ignored and cleared.
- Batched Core Location callbacks no longer discard usable intermediate points merely because a newer point exists in the same callback.
- The activation location is counted after Smart state processing, so diagnostics can classify it as Smart frequent instead of a plain significant-change tick.
- App-wide location sensitivity remains separate from the frequent/Smart movement threshold. It still controls cache/upload acceptance, while the movement threshold controls the frequent `distanceFilter` and Smart relevant-movement policy.

## Validation

- `./scripts/test-unit.sh`
- `git diff --check`
- `python3 -m json.tool miataru/miataru/Assets/Localizable.xcstrings`
- `plutil -lint miataru/miataru/SettingsManagers/App\ Settings/Settings.bundle/Root.plist`

The unit run passed 164 tests, including focused coverage for threshold normalization, Settings.bundle parity, persisted Smart frequent seed freshness/implausible-speed rejection, and chronological batch processing.
