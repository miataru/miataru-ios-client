# Navigation And Frequent Controls

## Summary

This stage extends existing actions instead of replacing them. The goal is to make navigation and manual frequent tracking more useful from Shortcuts, Siri, Spotlight, widgets, and on-screen context while preserving current deep-link behavior.

Existing actions:

- `OpenRouteToDeviceIntent`
- `OpenMiataruNavigationToDeviceIntent`
- `StartFrequentTrackingIntent`
- `StopFrequentTrackingIntent`

Planned improvements:

- Parameterized navigation direction.
- Parameterized transport mode.
- Parameterized presentation mode.
- Manual frequent tracking duration.
- Better status and stop behavior.
- iOS 26 View Annotation handoff from visible devices into navigation intents.

## Navigation Parameters

Add shared intent enums before changing individual intents:

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

enum IntentRouteApp: String, AppEnum {
    case miataru
    case appleMaps
}
```

Default behavior must match the current app:

- Miataru navigation defaults to `userToDevice` and `focused`.
- Apple Maps defaults to user-to-device routing.
- Existing deep links continue to resolve through `DeviceLinkResolver`.

## Frequent Tracking Duration

Extend `StartFrequentTrackingIntent` with an optional duration parameter.

Implementation rules:

- If duration is omitted, use the current settings-driven duration behavior.
- If duration is provided, start manual frequent tracking and calculate an expiry from the provided duration.
- Reconcile tracking state after updating settings, matching the existing service behavior.
- Return whether frequent tracking was already active, the new expiry, and the effective duration mode.
- Add a maximum duration using existing app policy if one exists; otherwise document the current app-supported duration choices rather than accepting arbitrary unbounded values.

The intent must keep current preconditions:

- Normal location tracking must be enabled.
- DeviceKey auth must not block tracking.
- Always authorization is required for frequent background tracking.

## Stop And Status Behavior

`StopFrequentTrackingIntent` should continue to be safe when frequent tracking is already inactive.

The status path added in Stage 2 should distinguish:

- Tracking disabled.
- Manual frequent active.
- Smart frequent active.
- Smart waiting.
- Frequent expired.
- Low battery disabled frequent mode.
- Permission blocked.
- DeviceKey blocked.

Do not overload "stop frequent tracking" to disable Smart frequent mode unless the user explicitly asks for a Smart setting change in a future intent.

## Schema Fit

Default schema decisions:

- Keep Miataru navigation intents custom unless an Apple navigation/open schema can express route direction, destination device, presentation mode, and Miataru privacy constraints.
- Keep frequent tracking custom. It is a Miataru-specific battery/privacy control.
- If an Apple open-content or navigation schema is adopted later, retain the existing custom App Intent as the backward-compatible implementation path and add schema conformance only as an iOS 26+ Siri layer.

Do not distort parameter names or behavior to fit a schema. A correct custom intent is better than a misleading schema intent.

## View Annotation Handoff

On iOS 26+, visible device context should be able to feed navigation intents:

- Device detail view: annotate the primary `TrackedDeviceEntity` through `NSUserActivity`.
- Device list rows: annotate each visible row so Siri can resolve "navigate to this device" while the row is on screen.
- Group map markers: annotate each visible marker with its device entity where current-location access is allowed.
- Navigation screen: annotate the active destination device and later the active route.

The handoff must never include hidden devices, unauthorized devices, DeviceKey, or raw server data.

## Testing

Add or extend tests for:

- Miataru navigation URL defaults remain unchanged.
- New navigation parameters produce expected deep-link options.
- Apple Maps URL still avoids DeviceID and display name leakage.
- Transport mode mapping is deterministic.
- Frequent tracking duration sets the expected expiry with an injected clock.
- Existing no-duration frequent tracking behavior remains unchanged.
- Stop frequent is idempotent.
- Permission, DeviceKey, and tracking-disabled preconditions still prevent start.
- Annotation builders include only visible, authorized devices.

## Explicit Deferrals

- Do not add route history summaries in this stage.
- Do not create a route entity index.
- Do not add place-based navigation until Places exist.
- Do not make callback automation part of navigation start; record events in Stage 4 first.

