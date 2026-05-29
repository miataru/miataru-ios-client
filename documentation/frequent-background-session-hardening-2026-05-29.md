# Frequent Background Session Hardening

Date: 2026-05-29

## Summary

Real-device testing showed that reboot-safe significant-change tracking was stable, but frequent background updates could degrade into short update bursts separated by significant-change wakeups. The frequent update stream resumed briefly after the primary significant-change manager delivered an event, then paused again.

This follow-up keeps the primary `CLLocationManager` as the durable significant-change reboot anchor and keeps frequent standard updates on the secondary manager, but adds explicit runtime support for live frequent background tracking.

## Implementation

- Active `Always`-authorized tracking now holds an `Always` `CLServiceSession`, including standard significant-change mode.
- Frequent background mode additionally holds a `CLBackgroundActivitySession` while the mode is active.
- The Always service session is stopped when tracking is stopped, authorization is lost, or DeviceKey authentication blocks uploads. The frequent background activity session is also stopped when frequent mode is disabled, expires, or is disabled for low battery.
- A primary significant-change callback can reassert frequent standard updates only if frequent standard updates were already active in the current process. This avoids restoring frequent mode aggressively after a cold reboot location wakeup.
- In standard significant-change mode, a background primary callback reasserts significant-change monitoring again. This keeps the post-reboot path from relying only on launch-time reconstruction after the first delivered location.
- The secondary frequent manager is stopped more defensively when frequent mode is inactive: standard updates and significant-change monitoring are stopped, background updates are disabled, automatic pausing is restored, and the delegate is detached.
- If a stale secondary callback arrives just after frequent mode was stopped, the first valid location can still flow through the normal deduped upload path. Repeated stale callbacks are suppressed after cleanup.

## Expected Behavior

- Standard significant-change tracking remains the reboot/system-termination recovery path.
- Frequent mode should produce continuous background standard location updates while the app is alive and the mode is active.
- Disabling or expiring frequent mode falls back to significant-change tracking without continuing to receive uploads from the secondary frequent manager.
- After a reboot while frequent mode is enabled, Miataru still resumes via significant-change tracking first; saved frequent mode resumes when the app is started normally.

## Validation

- Real-device testing by the user confirmed the final behavior.
- `xcodebuild -quiet -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,id=73874736-DD77-4211-B78B-A50B1A6FB2B9' -only-testing:miataruTests/SettingsConfigurationTests test`
- `xcodebuild -quiet -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build`
- `git diff --check`
