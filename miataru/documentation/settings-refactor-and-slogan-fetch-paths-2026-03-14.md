# Settings Refactor And Device Slogan Fetch Paths (2026-03-14)

## Scope

This change set combines two related areas:

1. A substantial iOS settings refactor with centralized defaults, localized copy cleanup, and a shorter root settings screen.
2. A corrected device-slogan fetch strategy so slogan reads no longer depend on a one-size-fits-all endpoint choice.

## Settings

### Centralized defaults and migration

- Runtime defaults now live centrally in `SettingsConfiguration.swift`.
- `SettingsManager` registers the same defaults that are mirrored in `Settings.bundle/Root.plist`.
- Fresh installs now start with the requested defaults (for example: default location update mode, map update interval `30s`, outside-map interval `60s`, map zoom `5 km`, route auto-update `on`, route progress `on`).
- Existing installations receive a one-time migration before the first `SettingsManager.shared` access so the requested existing-user booleans are force-enabled once.

### Screen structure

- The root settings screen was shortened.
- Advanced toggles moved into a dedicated push screen `Advanced Options`.
- The former status section became `Advanced Options and Tracking Status`.
- `Device Access Control` is shown in root settings only while ACL is disabled; once ACL is active, the section moves to `Location Tracking Details`.

### Copy and localization

- Settings labels/descriptions were normalized to direct, neutral phrasing without personal address.
- Missing setting descriptions were added.
- `Localizable.xcstrings` and all `Settings.bundle/*.lproj/Root.strings` files were aligned across supported locales.
- Runtime defaults and `Settings.bundle` defaults are now covered by regression tests.

## Device slogan behavior

### Input handling

- While editing a device slogan, normal spaces are now preserved during typing.
- Final save cleansing still removes control characters, trims outer whitespace, and enforces the 40-character limit.

### Fetch strategy

The slogan fetch path is now intentionally split:

- `Add Device`: fetch via `getDeviceSlogan`
- `Edit Device`: fetch via `getDeviceSlogan`
- Unknown devices in the iPhone/iPad device list: refresh locations via `getLocation`, then request missing slogans individually via `getDeviceSlogan`
- All other cases: continue using `getLocation`

This avoids unnecessary individual slogan lookups for normal list/device refreshes, while still fixing the case where no location payload is available but a slogan exists on the server.

## Notes

- The unknown-device list only performs the individual slogan request when no slogan is already cached (or a forced refresh is triggered).
- The existing dirty `project.pbxproj` change was treated as unrelated and should be reviewed independently.
