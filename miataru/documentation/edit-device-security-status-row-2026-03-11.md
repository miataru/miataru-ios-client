# Edit Device Security Status Row (2026-03-11)

## Problem
In the Edit Device sheet, the `Access Permissions` section only showed ACL toggles for linked devices. Users had no direct visibility into whether the target device currently has a DeviceKey set and whether ACL/access-control is enabled on the server.

## Change
Updated `iPhone_EditDeviceView` to add a new first row in `allowed_device_list_access_controls`:

- New security overview row with two textual status lines:
  - DeviceKey status
  - ACL/access-control status
- Added symbolic indicators:
  - DeviceKey: `key.fill` when active, `key.slash.fill` when inactive
  - ACL: `lock.fill` when active, `lock.open.fill` when inactive
  - Unknown fallback: `questionmark.circle.fill`
- Added explicit color coding:
  - Active: `green`
  - Inactive: `red`
  - Unknown/loading: `secondary`
- Added fetch on sheet open (`.onAppear`) via:
  - `MiataruAppAPI.getDeviceSecurityStatus(...)`
  - Parameters: server URL from settings, target device ID, requesting device ID, requesting device key
- Added fallback behavior:
  - If server URL/device key is missing, or API call fails (including auth/network/server errors), both statuses are set to `unknown`
  - Auth errors are still passed through `DeviceKeyAuthHandler.handle(error:)`
  - No blocking alert is shown by this status row itself

## Localization
Added full localization keys in `Localizable.xcstrings` for all supported languages (`da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`):

- `allowed_device_list_security_overview_label`
- `allowed_device_list_security_devicekey_active`
- `allowed_device_list_security_devicekey_inactive`
- `allowed_device_list_security_devicekey_unknown`
- `allowed_device_list_security_acl_active`
- `allowed_device_list_security_acl_inactive`
- `allowed_device_list_security_acl_unknown`

## Expected Behavior
- Opening Edit Device (for a non-own device while allowed-device-list feature is enabled) triggers one security-status fetch.
- The new row shows DeviceKey and ACL status text + icon.
- Visual state is color-coded (green/red/secondary) and does not misreport failures as inactive.
- Existing ACL toggle behavior (including immediate server sync) remains unchanged.

## Verification
- Validated `Localizable.xcstrings` JSON format (`jq empty .../Localizable.xcstrings`).
- Built the project successfully in Xcode integration (`BuildProject`, workspace tab `windowtab1`).
