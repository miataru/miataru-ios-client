# Background Location Reboot Hardening

Date: 2026-05-27

## Summary

Real-device testing showed that the first reboot-safe recovery-anchor implementation was still not sufficient: after rebooting an iPhone while frequent background updates were active, Miataru could fail to resume both frequent updates and significant-change updates until the app was opened manually.

This follow-up keeps the recovery-anchor architecture, but hardens the launch and delivery edges that matter after iOS starts the app in the background for location.

## Problem

The app had two fragile points:

- Location recovery was handled in `didFinishLaunchingWithOptions`, after some app bootstrap work had already started. For a location-triggered background launch, the app should restore tracking as early as possible.
- A received background location could start an async server upload without explicit background-task protection. If iOS suspended the app quickly after a reboot/location relaunch, the location might be observed locally but not delivered to the server.

The resolver also allowed `authorizedWhenInUse` to resolve to background tracking. That is not a durable state for reboot recovery, because iOS background relaunch for location requires the app to have sufficient background-capable authorization.

## Implementation

- `AppDelegate` now restores tracking from `application(_:willFinishLaunchingWithOptions:)` when the launch options contain `UIApplication.LaunchOptionsKey.location`.
- The same recovery check remains in `didFinishLaunchingWithOptions`, guarded by a single-launch dedupe flag.
- `LocationManager` wraps non-foreground location uploads in a short `UIApplication.beginBackgroundTask` token and ends it when the async upload path completes.
- `LocationManager.resolvedTrackingMode(...)` now treats `authorizedWhenInUse` as foreground-only. Background tracking, including frequent background mode and significant-change recovery, requires `authorizedAlways`.
- Frequent background mode keeps the dedicated significant-change recovery manager registered while the primary manager runs `startUpdatingLocation()`.

## Expected Behavior

- With tracking enabled, `Always` authorization, no DeviceKey auth block, and no user force-quit, significant-change monitoring remains the reboot/system-termination recovery anchor.
- Frequent background mode still uses standard background location updates for higher cadence while the app is alive in the background.
- If frequent mode expires or is disabled by low battery, the app falls back to standard significant-change tracking instead of stopping all tracking.
- If the app is relaunched by iOS for location after reboot or system termination, tracking is reconstructed before normal app startup continues and the resulting background upload gets protected execution time.

## Remaining iOS Boundaries

- A user force-quit still prevents background relaunch until the user opens the app again.
- `When In Use` authorization is not treated as reboot-capable background tracking.
- Simulator shutdown/restart is not a reliable proof for significant-change relaunch behavior; real-device tests remain required for reboot validation.
- iOS can still defer or coalesce significant-change delivery based on movement, radio state, power policy, and system scheduling.

## Validation

Focused regression tests passed:

```sh
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:miataruTests/SettingsConfigurationTests test
```

The focused suite executed 12 tests with 0 failures.
