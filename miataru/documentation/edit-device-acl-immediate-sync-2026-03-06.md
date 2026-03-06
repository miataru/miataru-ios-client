# Edit Device ACL Immediate Sync (2026-03-06)

## Problem
In the Edit Device sheet, ACL changes were only persisted when tapping Save. This made permission updates appear stale until users closed and reopened flows, and it coupled ACL writes to unrelated edits (for example device name/color).

## Change
Updated `iPhone_EditDeviceView` so ACL toggles are synchronized immediately when changed:

- `allowed_device_list_current_location_access` and `allowed_device_list_history_access` now call `AllowedDeviceListManager.shared.upsertDeviceACL(...)` directly on toggle changes.
- Current-location access still enforces history-access off when disabled.
- While ACL sync is running, ACL controls are disabled and a `ProgressView` is shown.
- On sync failure, ACL values are rolled back to their previous state and an error is presented.
- Removed the toolbar Cancel button in Edit Device.
- Replaced Save button label with localized `close_button_label` ("Close"/"Schließen"/...).
- Save/Close now only finalizes remaining local edits (name/color/slogan) and closes the sheet.

## Expected Behavior
- ACL updates are visible server-side immediately after each toggle change.
- Users do not need to press Save for ACL writes.
- Edit Device has a single close action and no cancel action.
- UI remains consistent during in-flight ACL sync and recovers correctly on errors.

## Verification
- Built app target successfully with:
  - `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build`
- Confirmed `close_button_label` localization exists in string catalog and is translated for current supported languages.
