# Frequent Background Device List Notice

Date: 2026-04-27

## Summary

When frequent background location updates are active, the device list now shows a dedicated notice above the devices. The notice is separated from the actual device section and can be tapped to open Settings directly in Advanced Options.

## Behavior

- The notice is shown only when location tracking is enabled and frequent background location updates are active.
- The notice appears in its own list section above the device rows on iPhone.
- On iPad, the notice appears as the first row inside the Devices section so the section header keeps the same spacing as the inactive state.
- If frequent background updates have a temporary expiration date, the notice shows the localized expiration time below the active-mode message.
- If the duration is set to never expire, the notice keeps the compact single-line active-mode message.
- Tapping the notice uses `AppNavigationCoordinator.openAdvancedSettings()` to switch to Settings and push Advanced Options.
- A chevron indicates that the row is actionable.
- Localized copy and an accessibility hint are included for all existing app languages.

## Files

- `miataru/miataru/views/iPhone/iPhone_DevicesView.swift`
- `miataru/miataru/views/iPad/iPad_DevicesView.swift`
- `miataru/miataru/views/iPhone/Settings Views/SettingsSupportViews.swift`
- `miataru/miataru/Assets/Localizable.xcstrings`

## Verification

Built successfully with:

```sh
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build
```
