# Navigation And Frequent Controls

## Summary

Status: implemented in version 3.2.2.

This stage extends existing actions instead of replacing them. Navigation and manual frequent tracking are now more useful from Shortcuts, Siri, Spotlight, widgets, and on-screen context while preserving the current deep-link behavior.

Existing actions:

- `OpenRouteToDeviceIntent`
- `OpenMiataruNavigationToDeviceIntent`
- `StartFrequentTrackingIntent`
- `StopFrequentTrackingIntent`

Implemented improvements:

- Parameterized navigation direction.
- Parameterized transport mode.
- Parameterized presentation mode.
- Manual frequent tracking duration.
- Stronger frequent-tracking status reasons.
- iOS 26 on-screen entity handoff from visible devices into navigation intents.

## Navigation Parameters

Shared intent enums:

```swift
enum IntentNavigationDirection: String, AppEnum {
    case userToDevice
    case deviceToUser
}

enum IntentTransportMode: String, AppEnum {
    case automobile
    case walking
    case transit
}

enum IntentNavigationPresentation: String, AppEnum {
    case standard
    case focused
}
```

`IntentTransportMode` is also an `AppEnum` and continues to use the existing automobile, walking, and transit route modes.

Implemented default behavior matches the existing app:

- Miataru navigation defaults to `userToDevice` and `focused`.
- Apple Maps defaults to user-to-device routing and does not add a transport query unless the shortcut provides one.
- Existing deep links continue to resolve through `DeviceLinkResolver`.

No combined route-app enum was added in this stage. Apple Maps and Miataru navigation remain separate App Intents so each action keeps a clear privacy and handoff contract.

`DeviceNavigationLaunchOptions` and `DeviceLinkResolver` now accept an optional transport override. The override is used by the launched navigation screen and does not mutate the saved navigation transport setting.

## Frequent Tracking Duration

`StartFrequentTrackingIntent` now has an optional duration parameter.

Implemented rules:

- If duration is omitted, use the current settings-driven duration behavior.
- If duration is provided, persist that duration to the existing manual frequent setting, refresh the expiry, and reconcile tracking state through the existing service path.
- The result reports whether frequent tracking was already active, the new expiry, and the effective duration mode.
- Supported choices match the app's existing manual frequent durations: 1h, 2h, 3h, 4h, 12h, 24h, and unlimited.

The intent must keep current preconditions:

- Normal location tracking must be enabled.
- DeviceKey auth must not block tracking.
- Always authorization is required for frequent background tracking.

## Stop And Status Behavior

`StopFrequentTrackingIntent` should continue to be safe when frequent tracking is already inactive.

The status path added in Stage 2 now distinguishes:

- Tracking disabled.
- Manual frequent active.
- Smart frequent active.
- Smart waiting.
- Frequent expired.
- Low battery blocked or disabled frequent mode.
- Permission blocked.
- DeviceKey blocked.

Stop Frequent Tracking still clears only the manual frequent override. It does not disable Smart frequent mode.

## Schema Fit

Default schema decisions:

- Keep Miataru navigation intents custom unless an Apple navigation/open schema can express route direction, destination device, presentation mode, and Miataru privacy constraints.
- Keep frequent tracking custom. It is a Miataru-specific battery/privacy control.
- If an Apple open-content or navigation schema is adopted later, retain the existing custom App Intent as the backward-compatible implementation path and add schema conformance only as an iOS 26+ Siri layer.

Do not distort parameter names or behavior to fit a schema. A correct custom intent is better than a misleading schema intent.

## View Annotation Handoff

On iOS 26+, visible device context should be able to feed navigation intents:

- Device detail and navigation contexts keep `NSUserActivity` for the primary tracked device.
- Device list rows annotate each visible row so Siri can resolve "navigate to this device" while the row is on screen.
- Device and group map markers annotate each visible marker with its device entity where current-location access is allowed.
- Navigation screens annotate the active destination device.

The handoff must never include hidden devices, unauthorized devices, DeviceKey, or raw server data.

Implementation note: the active Xcode 26.5 SDK includes `_AppIntents_SwiftUI` symbols for a `View.appEntityIdentifier(...)` modifier, but the modifier is not visible to the Swift compiler interface in this toolchain. Direct modifier calls fail to compile. Miataru therefore centralizes the handoff in `trackedDeviceViewAnnotation(for:)`, using SwiftUI `userActivity` plus `NSUserActivity.appEntityIdentifier` after the same `TrackedDeviceIntentMetadata.entity(for:)` privacy filter. The wrapper can be switched to the direct view modifier once the SDK exposes it to Swift source.

## Testing

Implemented coverage:

- Apple Maps and Miataru navigation URL defaults remain unchanged.
- Apple Maps direction and transport query behavior.
- Miataru deep-link direction, presentation, and transport override behavior.
- Apple Maps URL still avoids DeviceID and display name leakage.
- Transport mode mapping is deterministic.
- Frequent tracking explicit duration, omitted duration, unlimited duration, and renewal behavior.
- Permission, DeviceKey, and tracking-disabled preconditions still prevent start.
- Low-battery frequent status.
- Annotation builders include only visible, authorized devices with non-empty IDs.
- App Intent and App Shortcut localization completeness.
- App Shortcut trigger phrase placement in `AppShortcuts.xcstrings`, using one top-level key per shortcut and storing alternate phrases in `stringSet.values` so Xcode does not mark them stale.
- Non-English App Intent and App Shortcut values are not verbatim English fallback copies and preserve all interpolation placeholders.

## Explicit Deferrals

- Do not add route history summaries in this stage.
- Do not create a route entity index.
- Do not add place-based navigation until the visible Places UI exists and users can inspect/edit saved places in app.
- Do not make callback automation part of navigation start; record events in Stage 4 first.
