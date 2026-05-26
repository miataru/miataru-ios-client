# Background Location Recovery Anchor Follow-Up (2026-05-26)

## Problem

After the reboot-safe background-location change, frequent background mode could still fail to produce frequent updates once the app was already in the background. In practice the app continued to receive, at most, significant-change location events.

This was observed when frequent background mode was enabled while Miataru was running in the background.

## Cause

The first recovery-anchor implementation kept significant-change monitoring active on the same `CLLocationManager` instance that also owns standard location updates for foreground and frequent background tracking.

That preserved the reboot recovery path, but it also meant the same manager was asked to maintain significant-change monitoring and later switch into `startUpdatingLocation()` for frequent background tracking. On device, that service mix can leave the frequent path effectively behaving like significant-change-only tracking.

There was also a lifecycle race: SwiftUI can report `scenePhase == .background` while `UIApplication.shared.applicationState` still briefly reports `.active`. Without an explicit lifecycle context, the tracking resolver could choose the foreground mode during a background transition.

## Fix

`LocationManager` now uses two separate Core Location managers:

- `locationManager` remains responsible for foreground high-accuracy updates, standard background mode switching, and frequent background `startUpdatingLocation()`.
- `recoveryAnchorLocationManager` is dedicated to significant-change monitoring as the reboot/system-termination recovery anchor.

Frequent background mode explicitly clears significant-change monitoring from the primary manager before starting standard location updates. The recovery anchor stays active on its own manager, so it no longer displaces frequent updates.

Background and foreground lifecycle calls now also pass an explicit tracking state context. Background transitions force the resolver to evaluate background policy even if UIKit still reports the old application state for a moment.

## Expected Behavior

- Frequent background mode should use standard background location updates while the app is in the background.
- Significant-change monitoring remains available as a low-power recovery anchor for reboot/system relaunch cases.
- Standard tracking still uses significant-change monitoring.
- Tracking-off, permission loss, DeviceKey auth block, and explicit stop shut down both managers.

## Validation

- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:miataruTests/SettingsConfigurationTests test`
- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build`

Manual device validation remains required for real background delivery cadence.
