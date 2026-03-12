# DeviceKey Recovery + Device Identity Reset Flow (2026-03-12)

## Goal
Harden the DeviceKey recovery flow for runtime auth failures (`401/403`) and make emergency recovery reliable by:

- guiding users directly into restore/custom key handling,
- enabling an explicit emergency reset path (new DeviceID + new DeviceKey),
- preserving local state as far as possible,
- reinitializing ACL state on the new identity,
- restoring location tracking automatically when it was disabled due to DeviceKey auth failure.

## User-Visible Behavior

1. Runtime DeviceKey auth failure now uses explicit error wording and opens the DeviceKey handling flow directly.
2. Forbidden after "Generate and set DeviceKey" keeps the red error and opens the Custom DeviceKey sheet.
3. Custom DeviceKey sheet includes emergency guidance and a destructive, double-confirmed action.
4. Emergency action creates a new DeviceID and DeviceKey and migrates local state.
5. After successful emergency reset, app navigation switches to "This Device" tab.
6. Emergency button in custom sheet is red with readable foreground styling.
7. If tracking was active before auth failure and got disabled due to that failure, it is automatically re-enabled after successful DeviceKey recovery/reset.

## Implemented Changes

### Auth Error Handling
- Updated runtime auth handling and notifications:
  - `miataru/miataru/DeviceKeyAuthHandler.swift`
- Runtime auth errors (`401/403`) now:
  - mark DeviceKey auth as blocked,
  - persist whether tracking was disabled due to auth failure,
  - disable tracking toggle for that auth-failure case.

### Settings Persistence for Auth-Disabled Tracking
- Added persisted setting:
  - `trackAndReportLocationDisabledByDeviceKeyAuth`
- File:
  - `miataru/miataru/SettingsManagers/App Settings/SettingsManager.swift`

### DeviceKey Sheet / Emergency Identity Reset
- Expanded DeviceKey sheet with:
  - forbidden handling auto-opening custom sheet,
  - emergency reset UI and confirmation,
  - migration snapshot + rollback flow,
  - post-success notifications (`deviceIdentityDidReset`, `deviceKeyAuthResolved`),
  - automatic tracking restoration if disabled by DeviceKey auth,
  - ACL reinitialization for the new identity.
- File:
  - `miataru/miataru/views/iPhone/iPhone_DeviceKeySheetView.swift`

### ACL Reinitialization
- During emergency identity reset success path:
  - if ACL feature was enabled before reset, call `AllowedDeviceListManager.activateAllowedDeviceList()` for the new DeviceID/DeviceKey.
- Related file:
  - `miataru/miataru/SettingsManagers/App Settings/Devices/AllowedDeviceListManager.swift`

### DeviceID Change Propagation / This-Device Refresh
- Added DeviceID change notification + listeners to refresh current-device UI state.
- Files:
  - `miataru/miataru/SettingsManagers/App Settings/thisDeviceIDManager.swift`
  - `miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift`

### Root View Behavior (iPhone/iPad)
- Runtime auth banner fallback messaging and direct recovery presentation updates.
- Auto-switch to "This Device" tab after identity reset for both iPhone and iPad root views.
- Files:
  - `miataru/miataru/views/iPhone/iPhone_RootView.swift`
  - `miataru/miataru/views/iPad/iPad_RootView.swift`

### Localization / Project Wiring
- Added/updated string resources and project references as part of the flow updates.
- Files:
  - `miataru/miataru/Assets/Localizable.xcstrings`
  - `miataru/miataru.xcodeproj/project.pbxproj`

## Validation

- Build command:
  - `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build`
- Result:
  - `** BUILD SUCCEEDED **`
