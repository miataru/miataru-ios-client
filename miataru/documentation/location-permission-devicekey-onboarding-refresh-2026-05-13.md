# Location Permission, Visitor Refresh, and Onboarding DeviceKey Flow

Date: 2026-05-13

## Summary

This release tightens three setup-adjacent flows:

- The current-device visitor list refreshes as soon as the My Device tab appears.
- Location tracking can re-enter the full permission request flow, including the `Always` escalation after `When In Use` authorization when iOS allows another prompt.
- DeviceKey sheets opened from onboarding close automatically shortly after a successful DeviceKey operation.

## Visitor History Refresh

The My Device tab now forces a visitor-history refresh when it appears. If visitor data is already present, the refresh runs without the loading state so the UI does not visibly reset. This keeps the visitor list aligned with the recent-visitor indicator shown elsewhere in the app.

Changed files:

- `miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift`
- `miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift`

## Location Permission Flow

`LocationManager` no longer stores a persistent "Always authorization already requested" flag. The previous behavior could prevent a follow-up `Always` request after a reinstall, an iOS limited-choice path such as "Ask Next Time Or When I Share", or a later user correction to `When In Use`.

The new behavior uses current-session gating:

1. `notDetermined` asks for When In Use authorization.
2. `authorizedWhenInUse` schedules a delayed `requestAlwaysAuthorization()` while tracking is enabled.
3. denied/restricted states cancel pending escalation and disable tracking as before.
4. `authorizedAlways` cancels any pending escalation.
5. Location Tracking Details exposes a manual "Request Location Permission Again" button that resets the current-session attempt and restarts the authorization request path.

Changed files:

- `miataru/miataru/LocationManagers/LocationManager.swift`
- `miataru/miataru/views/iPhone/Settings Views/iPhone_LocationStatusView.swift`
- `miataru/miataru/Assets/Localizable.xcstrings`

## Onboarding DeviceKey Sheet

`iPhone_DeviceKeySheetView` now accepts an optional `onDeviceKeySuccess` callback. Normal DeviceKey sheets keep the default no-op behavior and remain open after success. Onboarding pages pass a callback that waits briefly before dismissing the sheet, giving users enough time to see the success state before returning to the onboarding pager.

This behavior is wired for:

- `iPhone_6_OnboardingDeviceKeyView`
- `iPhone_8_OnboardingAllowedDeviceListView`

Changed files:

- `miataru/miataru/views/iPhone/iPhone_DeviceKeySheetView.swift`
- `miataru/miataru/views/iPhone/Onboarding/iPhone_6_OnboardingDeviceKeyView.swift`
- `miataru/miataru/views/iPhone/Onboarding/iPhone_8_OnboardingAllowedDeviceListView.swift`

## Validation

Validated with:

```sh
./miataru/scripts/test-unit.sh
```

Result:

- 115 tests passed in 18 suites.
