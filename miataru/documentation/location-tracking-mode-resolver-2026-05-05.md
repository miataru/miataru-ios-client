# Location Tracking Mode Resolver

Date: 2026-05-05

## Summary

Location tracking mode selection now runs through a single resolver in `LocationManager`. The app still keeps high-accuracy foreground tracking as before, but background transitions now always return to the configured background policy: significant-change monitoring by default or frequent background updates when the user has enabled them.

## Problem

The focused navigation view previously only changed local UI state when Turn-by-turn navigation started or stopped. `LocationManager` separately switched between foreground and background location APIs from several lifecycle paths. That made the intended behavior harder to reason about, especially when navigation, app backgrounding, frequent-background expiration, and low-battery auto-disable interacted.

## Runtime Behavior

`LocationManager` now resolves one of four tracking modes:

- `stopped`
- `foregroundHighAccuracy`
- `backgroundSignificantChange`
- `backgroundFrequent(distanceFilter, desiredAccuracy)`

All setting changes, authorization changes, app lifecycle transitions, tracking toggles, expiration timers, and low-battery fallback paths re-enter the same resolver via `applyTrackingMode(reason:)`.

Focused Turn-by-turn navigation registers a UUID-backed navigation location session through `beginNavigationLocationSession()`. Sessions are stored in a set so multiple windows or views cannot accidentally stop each other. Navigation sessions are ended idempotently when focused navigation is disabled, automatically stopped, direction-switched, or when the view disappears.

Navigation sessions do not override background policy. If the app enters the background while focused navigation is active, `LocationManager` keeps the session remembered but resolves to significant-change or frequent background mode. When the app returns to the foreground, the resolver applies high-accuracy foreground tracking again.

The legacy `applicationWillEnterForeground` hook now forwards to the foreground lifecycle path instead of stopping tracking, removing a trap where older delegate wiring could disable location reporting unexpectedly.

## Verification

Validated with:

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4.1' -only-testing:miataruTests/SettingsConfigurationTests/locationTrackingModeResolverKeepsForegroundNavigationAndBackgroundPoliciesDistinct
```

The broader `SettingsConfigurationTests` target compiles and runs, but still fails on the pre-existing missing localization key `frequent_background_location_updates_central_explanation`, unrelated to this resolver change.
