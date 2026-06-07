# Notification sounds for Smart frequent and unknown visitors

Smart frequent mode-change notifications and unknown visitor notifications now use
Miataru's bundled CAF sounds instead of the default iOS notification sound.

## Mapping

- Smart frequent activated: `confirm.caf`
- Smart frequent deactivated/paused: `cancel.caf`
- Unknown visitor alert: `confirm.caf`

The mapping follows the existing mutual navigation feedback sounds, where
`confirm.caf` marks entry into the mutual state and `cancel.caf` marks exit.

## Implementation notes

- `MiataruNotificationSounds` centralizes the custom notification sound names.
- Frequent background reminder, expiration, and low-battery notifications keep
  the iOS default sound.
- `confirm.caf` and `cancel.caf` are copied to the app bundle root by the
  file-system-synchronized Xcode project resources, which is where iOS custom
  notification sounds can be resolved by file name.

## Verification

- `UnknownVisitorAlertEvaluatorTests` verifies unknown visitor notifications use
  `confirm.caf`.
- `FrequentBackgroundTrackingReminderServiceTests` verifies Smart frequent
  activation uses `confirm.caf` and deactivation uses `cancel.caf`.
- A simulator build confirmed `confirm.caf` and `cancel.caf` are present in the
  built `miataru.app` bundle root.
