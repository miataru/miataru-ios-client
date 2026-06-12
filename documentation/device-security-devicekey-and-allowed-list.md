# Device Security, DeviceKey, And Allowed Device List

## Summary

This document consolidates DeviceKey recovery, DeviceKey UI hints, device security status, and Allowed Device List behavior.

## Source Notes Consolidated

This document consolidates:

- `device-security-status-api-client-2026-03-11.md`
- `allowed-device-list-read-api-client-2026-03-13.md`
- `edit-device-security-status-row-2026-03-11.md`
- `edit-device-acl-immediate-sync-2026-03-06.md`
- `devicekey-recovery-identity-reset-2026-03-12.md`
- `devicekey-keycard-longpress-hint-2026-03-12.md`
- DeviceKey-related sections from `location-permission-devicekey-onboarding-refresh-2026-05-13.md`

## API Client Support

### Device Security Status

The shared Swift client supports `getDeviceSecurityStatus`.

`MiataruClientSwift` additions:

- `GetDeviceSecurityStatusRequestBody`
- `GetDeviceSecurityStatusPayload`
- `MiataruDeviceSecurityStatus`
- `MiataruGetDeviceSecurityStatusResponse`
- `MiataruAPIClient.getDeviceSecurityStatus(serverURL:forDeviceID:requestingDeviceID:requestingDeviceKey:)`

Endpoint shape:

- Path: `v1/getDeviceSecurityStatus`
- Request root key: `MiataruGetDeviceSecurityStatus`
- Response root key: `MiataruDeviceSecurityStatus`

App wrapper:

- `MiataruAppAPI.getDeviceSecurityStatus(...)`
- Uses centralized `MiataruRequestExecutor` read retry policy.

### Allowed Device List Read

The shared Swift client supports `getAllowedDeviceList`.

`MiataruClientSwift` additions:

- `GetAllowedDeviceListRequestBody`
- `GetAllowedDeviceListPayload`
- `MiataruAllowedDeviceList`
- `MiataruGetAllowedDeviceListResponse`
- `MiataruAPIClient.getAllowedDeviceList(serverURL:deviceID:deviceKey:)`

Endpoint shape:

- Path: `v1/getAllowedDeviceList`
- Request root key: `MiataruGetAllowedDeviceList`
- Response root key: `MiataruAllowedDeviceList`

Response model:

- `DeviceID`
- `IsAllowedDeviceListEnabled`
- `allowedDevices` decoded as existing `MiataruAllowedDevice` values

The client also removed an existing non-functional Swift warning in `SkipDecodable` by changing `var keyed` to `let keyed`.

Package README usage examples were added for both endpoints. `getAllowedDeviceList` also received changelog entries.

## Edit Device Security Overview

The Edit Device sheet includes a security overview row in the `Access Permissions` section for linked devices.

Behavior:

- Shows DeviceKey status and ACL/access-control status.
- DeviceKey icons: `key.fill` active, `key.slash.fill` inactive, `questionmark.circle.fill` unknown.
- ACL icons: `lock.fill` active, `lock.open.fill` inactive, `questionmark.circle.fill` unknown.
- Active is green, inactive is red, unknown/loading is secondary.
- Fetches status on sheet open through `MiataruAppAPI.getDeviceSecurityStatus(...)`.
- Parameters use server URL from settings, target DeviceID, requesting DeviceID, and requesting DeviceKey.
- Missing server URL, missing DeviceKey, API failures, auth failures, network failures, and server failures set both statuses to unknown.
- Auth errors still pass through `DeviceKeyAuthHandler.handle(error:)`.
- The status row itself does not show a blocking alert.

Localization keys:

- `allowed_device_list_security_overview_label`
- `allowed_device_list_security_devicekey_active`
- `allowed_device_list_security_devicekey_inactive`
- `allowed_device_list_security_devicekey_unknown`
- `allowed_device_list_security_acl_active`
- `allowed_device_list_security_acl_inactive`
- `allowed_device_list_security_acl_unknown`

All app locales are covered.

## ACL Immediate Sync

Allowed Device List changes in Edit Device synchronize immediately rather than waiting for Save.

Behavior:

- `allowed_device_list_current_location_access` and `allowed_device_list_history_access` call `AllowedDeviceListManager.shared.upsertDeviceACL(...)` directly on toggle changes.
- Disabling current-location access still turns history access off.
- ACL controls are disabled while sync is running.
- A `ProgressView` shows in-flight sync.
- Sync failures roll values back and present an error.
- The toolbar Cancel button was removed.
- Save became a localized Close action.
- Close finalizes remaining local edits such as name, color, and slogan and closes the sheet.

Expected result:

- ACL updates become visible server-side immediately.
- ACL writes are no longer coupled to unrelated local edits.
- The sheet has one close action and no separate cancel path.

## DeviceKey Recovery And Emergency Identity Reset

The DeviceKey recovery flow is hardened for runtime auth failures (`401/403`) and emergency recovery.

User-visible behavior:

1. Runtime DeviceKey auth failure uses explicit error wording and opens the DeviceKey handling flow.
2. Forbidden after "Generate and set DeviceKey" keeps the red error and opens the Custom DeviceKey sheet.
3. Custom DeviceKey sheet includes emergency guidance and a destructive double-confirmed reset action.
4. Emergency reset creates a new DeviceID and DeviceKey and migrates local state.
5. After success, navigation switches to "This Device".
6. Emergency button is red with readable foreground styling.
7. If tracking was active before auth failure and disabled because of it, tracking is automatically re-enabled after successful recovery/reset.

Implementation:

- `DeviceKeyAuthHandler` marks auth as blocked, persists whether tracking was disabled by auth failure, and disables tracking for that auth-failure case.
- `SettingsManager` adds `trackAndReportLocationDisabledByDeviceKeyAuth`.
- `iPhone_DeviceKeySheetView` handles forbidden auto-opening of custom sheet, emergency reset UI, confirmation, migration snapshot and rollback, success notifications (`deviceIdentityDidReset`, `deviceKeyAuthResolved`), tracking restoration, and ACL reinitialization.
- `AllowedDeviceListManager.activateAllowedDeviceList()` is called after reset when ACL was enabled before reset.
- `thisDeviceIDManager` publishes DeviceID change notification.
- `iPhone_MyDeviceQRCodeView` refreshes current-device state after identity changes.
- iPhone and iPad root views update runtime auth banner/recovery presentation and auto-switch to This Device after identity reset.
- Strings and project references were added for the recovery flow.

## DeviceKey Sheet Hint And Onboarding Behavior

The DeviceKey sheet includes a localized hint:

```text
Long press the Keycard to unlock the administrative options.
```

It is shown whether a DeviceKey is already set or not. Localization key:

- `device_key_long_press_admin_hint`

Covered locales:

- `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`

Onboarding DeviceKey sheets accept an optional `onDeviceKeySuccess` callback:

- Normal sheets default to no-op and remain open after success.
- Onboarding pages wait briefly, then dismiss so users see the success state before returning to the pager.
- Wired in `iPhone_6_OnboardingDeviceKeyView` and `iPhone_8_OnboardingAllowedDeviceListView`.

## Location Permission Touchpoint

The same setup work also changed the location permission request flow:

- `LocationManager` no longer stores a persistent "Always authorization already requested" flag.
- `notDetermined` asks for When In Use.
- `authorizedWhenInUse` schedules a delayed Always escalation while tracking is enabled.
- denied/restricted states cancel pending escalation and disable tracking as before.
- `authorizedAlways` cancels pending escalation.
- Location Tracking Details exposes "Request Location Permission Again" to reset current-session attempt state and restart the flow.

## Validation History

Validation included:

- Swift package builds for `MiataruAPIClient`.
- Full Swift package build for `getAllowedDeviceList`.
- App builds with `xcodebuild`.
- `Localizable.xcstrings` JSON validation.
- Confirmation that security status row displays DeviceKey/ACL status without misreporting failures as inactive.
- Confirmation that ACL toggles sync immediately and rollback on error.
- Unit run for the onboarding/permission follow-up: 115 tests passed in 18 suites.

Known historical note: one early package-target build succeeded while the full package build still failed in the example app due unrelated pre-existing `String`/`Double` mismatches. The later allowed-list client build completed successfully.

