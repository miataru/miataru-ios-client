# Frequent Background Low-Battery Auto-Disable

Date: 2026-04-28

## Summary

Frequent background location updates now have an always-active low-battery safeguard. The setting is only exposed in Advanced Options while frequent background updates are enabled and defaults to 30%.

## Behavior

- Users can choose a disable threshold of 10%, 20%, 30%, 40%, or 50%.
- Existing and new installs default to 30%.
- Unsupported stored values are normalized back to the default.
- The threshold is included in DeviceKey recovery/reset snapshots so identity changes preserve the user's background tracking configuration.
- Percentages shown in explanatory copy and low-battery notifications are formatted in code via `NumberFormatter`, avoiding hard-coded percent values in `Localizable.xcstrings`.

## Runtime Flow

`LocationManager` checks the current battery level before starting frequent background updates and again when background location updates arrive. When the battery level is at or below the configured threshold, Miataru:

- turns off the frequent background update setting;
- invalidates the local frequent-background expiration timer;
- starts standard significant-change monitoring;
- leaves regular foreground/background update cleanup to the existing `startSignificantChangeMonitoring()` path;
- asks `FrequentBackgroundTrackingReminderService` to notify the user.

`FrequentBackgroundTrackingReminderService` cancels the repeating reminder, pending expiration notification, and stored expiration notification date before sending the low-battery notification. The notification explains the current battery level, the configured threshold, and that Miataru returned to the standard background mode.

Notification taps reuse the existing Advanced Options routing so the user can inspect or change the setting.

## Files

- `miataru/miataru/LocationManagers/LocationManager.swift`
- `miataru/miataru/Notifications/FrequentBackgroundTrackingReminderService.swift`
- `miataru/miataru/SettingsManagers/App Settings/SettingsConfiguration.swift`
- `miataru/miataru/SettingsManagers/App Settings/SettingsManager.swift`
- `miataru/miataru/views/iPhone/Settings Views/iPhone_AdvancedOptionsView.swift`
- `miataru/miataru/Assets/Localizable.xcstrings`

## Verification

Validated with:

```sh
xcrun xcstringstool compile --dry-run --output-directory /tmp/miataru-xcstrings-check miataru/miataru/Assets/Localizable.xcstrings
git diff --check
xcodebuild build-for-testing -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/miataru-deriveddata-percent-check
```
