# App Intents, Shortcuts, And Manual Validation

## Summary

This document consolidates Miataru's current App Intents implementation notes and manual validation plan. It covers the implemented Siri/Shortcuts surface, the service boundaries behind those intents, privacy constraints, and the manual checks that still complement the existing unit tests.

The forward-looking iOS 26 schema roadmap is intentionally kept separate in `Intent-Sprint/`. Do not fold those sprint documents into this current-state reference.

## Source Notes Consolidated

This document consolidates:

- `AppIntentsPreparation.md`
- `AppIntentsManualTestPlan.md`

Related roadmap package:

- `Intent-Sprint/00-overview.md`

## Current Intent Scope

The implemented foundation supports:

- "Find Device": fetch the last known location for a configured tracked device.
- "Route in Apple Maps": open Apple Maps to the last known target coordinate, with optional route direction and transport mode.
- "Navigate in Miataru": open Miataru directly into internal navigation, with optional route direction, presentation, and transport mode. External `miataru://` links remain valid for Safari and `simctl openurl`.
- "Start Frequent Tracking": start the manual frequent-background override without turning normal location tracking on, optionally choosing one of the app's supported manual frequent durations.
- "Stop Frequent Tracking": stop the manual frequent-background override without changing normal location tracking.

The "Is Device Near Place" idea remains deferred because the app does not yet have a persistent Places data source. When Places exist, build that on `MiataruPlaceEntity`, `MiataruPlaceQuery`, and a dedicated proximity intent rather than hiding place behavior inside the current device-location intents.

## Relevant Models And Services

Current App Intents expose the user-facing word "Device" and use the existing device model internally. Some Swift type and file names still include `Person` from the first App Intents implementation, but the active entity/query/options layer is the tracked-device layer.

Relevant models:

- `KnownDevice`: contains `DeviceName`, `DeviceID`, current-location/history access flags, and display/sort metadata.
- `KnownDeviceStore.shared.devices`: local source of configured tracked devices.
- `MiataruLocationData`: API location model with DeviceID, coordinate, accuracy, and timestamp.
- `DeviceLocationCacheStore`: cache for last device locations and previously known reverse-geocoding results.

Relevant services:

- `MiataruAppAPI.getLocation(...)`: existing `getLocation` adapter, including server configuration, API counters, and cache integration.
- `DeviceLocationCacheStore.shared.getPlacemark(for:)`: returns coarse existing place data such as city/country without forcing a new reverse-geocode request from an intent.
- `DeviceLinkResolver` and `AppNavigationCoordinator`: route legacy `miataru://<deviceID>` links to device detail and navigation links such as `miataru://<deviceID>?action=navigate&direction=userToDevice&presentation=focused&transport=walking` into internal navigation.
- `SettingsManager.shared`: source for normal tracking state, DeviceKey lock state, manual frequent-background configuration, duration, and expiration.
- `LocationManager.shared`: source for current Core Location authorization and the central reconcile path used by both UI and intent actions.
- `FrequentBackgroundTrackingReminderService`: updated indirectly through existing Settings/LocationManager observers when manual frequent tracking starts or stops.

## Implementation Files

App Intents and support types live under the app's existing `AppIntents/` and `Services/` structure:

- `miataru/miataru/Services/IntentLocationService.swift`
  - `IntentLocationServicing`
  - `IntentLocationService`
  - `IntentDeviceLocation`
  - `IntentLocationError`
  - small provider/mapping layer for tests without a real server
- `miataru/miataru/Services/IntentFrequentTrackingService.swift`
  - `IntentFrequentTrackingService`
  - `IntentFrequentTrackingError`
  - testable controller for starting/stopping manual frequent-background tracking
- `miataru/miataru/AppIntents/Entities/TrackedDeviceEntity.swift`
- `miataru/miataru/AppIntents/Entities/TrackedDeviceIntentMetadata.swift`
- `miataru/miataru/AppIntents/Queries/TrackedDeviceQuery.swift`
- `miataru/miataru/AppIntents/Queries/TrackedDeviceOptionsProvider.swift`
- `miataru/miataru/AppIntents/Intents/FindPersonLocationIntent.swift`
- `miataru/miataru/AppIntents/Intents/OpenRouteToPersonIntent.swift`
- `miataru/miataru/AppIntents/Intents/OpenMiataruNavigationToPersonIntent.swift`
- `miataru/miataru/AppIntents/Intents/StartFrequentTrackingIntent.swift`
- `miataru/miataru/AppIntents/Intents/StopFrequentTrackingIntent.swift`
- `miataru/miataru/AppIntents/Intents/StatusIntents.swift`
- `miataru/miataru/AppIntents/Views/DeviceLocationSnippetView.swift`
- `miataru/miataru/AppIntents/MiataruAppShortcutsProvider.swift`
- `miataru/miataru/Assets/Localizable.xcstrings`
- `miataru/miataru/Assets/AppShortcuts.xcstrings`

## Architecture Decisions

App Intents must not call SwiftUI views or view models directly. They should use small service boundaries that can be tested without launching the app UI.

Device selection and visibility:

- `TrackedDeviceQuery` only offers devices with a non-empty `DeviceID` and `hasCurrentLocationAccess == true`.
- The product currently has no separate "Show in Siri/Shortcuts" setting, so `hasCurrentLocationAccess` is the visibility and permission boundary.
- There is no favorites model yet, so Shortcuts suggestions follow the current `KnownDeviceStore.shared.devices` ordering.
- Production intent parameters currently use `TrackedDeviceOptionsProvider` as a dynamic string picker. This avoids a Shortcuts runtime failure where dynamic `AppEntity` selections can be rejected as an unregistered `AppEntity` identifier.
- The prepared entity/query layer remains in the project so `TrackedDeviceEntity` can be revisited as a direct shortcut parameter when the runtime behavior is stable enough.

Privacy and output:

- Siri/dialog text may include display name, location age, and a coarse place description.
- Siri/dialog text must not include DeviceID, DeviceKey, raw API responses, or exact implementation details.
- Apple Maps URLs must contain only destination coordinates and never DeviceID.
- Locked-device behavior is not separately reduced yet; all dialog output remains generally data-minimized.

Navigation behavior:

- `FindPersonLocationIntent` does not automatically open the app.
- `OpenRouteToPersonIntent` stays as the existing intent type and visible "Route in Apple Maps" action. Its default URL remains `http://maps.apple.com/?daddr=<lat>,<lon>`.
- When the Apple Maps direction is `deviceToUser`, the URL uses the device coordinate as `saddr` and `Current Location` as `daddr`.
- Apple Maps transport is optional. When omitted, no `dirflg` query item is added; when provided, the App Intent mode maps to Apple's `d`, `w`, or `r` direction flag.
- `OpenMiataruNavigationToPersonIntent` uses the same device-selection and permission logic, creates `miataru://<DeviceID>?action=navigate&direction=userToDevice&presentation=focused` by default, opens Miataru, and passes the parsed request to `AppNavigationCoordinator`.
- Miataru navigation can also pass `direction=deviceToUser`, `presentation=overview`, and an optional `transport=<mode>` override.
- `DeviceLinkResolver` distinguishes legacy device links from navigation links. Legacy links still open only device detail.
- `AppNavigationCoordinator` routes known navigation links into a device-navigation request and unknown DeviceIDs into Add Device.
- `iPhone_DeviceNavigationView` accepts launch options: `direction=userToDevice` starts with the reversed route, `presentation=focused` switches into focused navigation after a route is available, and the transport override is used without changing the saved navigation setting.

Frequent tracking behavior:

- `StartFrequentTrackingIntent` accepts an optional duration. If omitted, it uses Miataru's configured manual frequent-background duration.
- Provided durations persist to the existing duration setting, refresh the manual frequent expiration, and return the effective mode. Supported duration choices are 1h, 2h, 3h, 4h, 12h, 24h, and unlimited.
- `StopFrequentTrackingIntent` remains parameterless.
- Starting frequent tracking does not turn `trackAndReportLocation` on.
- Starting frequent tracking fails with localized errors when normal tracking is off, DeviceKey authentication is blocking uploads, or Always location authorization is unavailable.
- Repeated starts renew the manual frequent-background expiration based on the effective duration.
- Stopping frequent tracking is idempotent. If the override is already off, state remains unchanged and normal standard tracking is not disabled.
- Frequent tracking status distinguishes manual active, Smart active, Smart waiting, expired, tracking disabled, DeviceKey blocked, permission blocked, and low-battery blocked/disabled states.

Snippet and localization behavior:

- `DeviceLocationSnippetView` is prepared but is not wired through `ShowsSnippetView`, because the locally visible SDK signature was available only behind newer AppIntents APIs at the time this implementation was prepared.
- Intent titles, descriptions, parameters, dialogs, errors, shortcut titles, snippet preparation strings, and extracted parameter-summary strings are covered in `Localizable.xcstrings` across all ten app locales.
- App Shortcut trigger phrases live in the separate `AppShortcuts.xcstrings` catalog with `${applicationName}` placeholders. Each shortcut uses one top-level source key, with alternate phrases stored per locale in `stringSet.values`; adding alternates as separate top-level keys makes Xcode mark them stale.
- Non-English intent and shortcut localizations must not be verbatim English fallback copies, even when Xcode marks the translation state as translated. The App Intents regression suite checks this and also verifies that placeholders such as `%@`, `${device}`, `${duration}`, and `${applicationName}` are preserved.

On-screen handoff:

- Device detail, list row, map marker, and navigation contexts annotate only devices that pass `TrackedDeviceIntentMetadata.entity(for:)`.
- Hidden devices, unauthorized devices, empty IDs, DeviceKey, raw server data, and unknown visitors are never annotated.
- Direct SwiftUI `View.appEntityIdentifier(...)` calls do not compile with the current Xcode 26.5 Swift interface even though related symbols are present in `_AppIntents_SwiftUI`. Miataru uses a centralized `NSUserActivity.appEntityIdentifier` wrapper until the modifier is source-visible.

## Manual Validation Plan

Run these checks on an iPhone or simulator after installing the app:

1. Configure at least one tracked device in Miataru.
2. Ensure that `hasCurrentLocationAccess` is enabled for that device.
3. Ensure a current server location exists for that device.
4. Open the Shortcuts app.
5. Search for Miataru actions.
6. Optionally switch the device language to each supported app locale and verify that titles, parameters, dialogs, and errors appear localized.

Find Device:

1. Select the "Find Device" action.
2. Choose a suggested device.
3. Run the shortcut.
4. Verify that the dialog contains display name, location age, and coarse place description or fallback text.
5. Verify that no DeviceID, DeviceKey, or raw API response is shown.
6. Test Siri with a phrase such as "Where is [Name] in Miataru?"
7. Verify that the app does not open automatically.
8. Verify that execution does not produce a `TrackedDeviceEntity` or `EntityIdentifier` Shortcuts error.

Route in Apple Maps:

1. Select the "Route in Apple Maps" action.
2. Choose a suggested device.
3. Run the shortcut.
4. Verify that Apple Maps opens with a route to the last known coordinate.
5. Test Siri with a phrase such as "Route to [Name] in Miataru."
6. Verify that the Maps URL does not contain DeviceID.
7. Run once with no transport mode and verify that no `dirflg` query is added.
8. Run with walking, automobile, and transit and verify the expected Maps route mode.
9. Run with device-to-user direction and verify that the device coordinate is used as the route start.

Navigate in Miataru:

1. Select the "Navigation in Miataru" action.
2. Choose a suggested device.
3. Run with default parameters and verify that Miataru opens focused navigation from the user device to the selected device.
4. Run with overview presentation and verify that the route opens in the standard navigation presentation.
5. Run with device-to-user direction and verify that the route direction flips.
6. Run with a transport override and verify that the launched route uses it without changing the saved navigation transport setting.
7. Verify that the deep link contains no DeviceKey or raw server data.

Start Frequent Tracking:

1. Select "Start Frequent Tracking".
2. Run it while normal location tracking is off and verify the expected message that location tracking must first be enabled in Miataru.
3. Enable normal location tracking and ensure iOS allows Always location access.
4. Run the action again.
5. Verify that the manual frequent-background override is active and uses the configured duration.
6. Run the action with explicit 1h, 2h, 3h, 4h, 12h, 24h, and unlimited durations and verify the effective duration setting and expiration behavior.
7. Run the action a second time and verify that the expiration is renewed.
8. Test Siri with a phrase such as "Start frequent tracking in Miataru."
9. Verify that the app does not open automatically and no DeviceID, DeviceKey, or server data is spoken.

Stop Frequent Tracking:

1. Enable the manual frequent-background override.
2. Select "Stop Frequent Tracking".
3. Run the shortcut.
4. Verify that the manual override is disabled and normal standard tracking remains unchanged.
5. Run the action again and verify the expected "already off" style message.
6. Test Siri with a phrase such as "Stop frequent tracking in Miataru."
7. Verify that the app does not open automatically.

Error paths:

1. Run without configured devices and verify the "no devices configured" message.
2. Remove a device from Miataru and rerun an existing shortcut. It should fail with a "device no longer available" style message.
3. Disable `hasCurrentLocationAccess` for a device. The device must not be suggested, and an old shortcut must fail with a permission error.
4. Make the server unreachable and verify the network/server error.
5. Test a device with no location and verify the "no location available yet" message.
6. Run "Start Frequent Tracking" while DeviceKey authentication blocks uploads and verify the message asking the user to open Miataru and update the DeviceKey.
7. Run "Start Frequent Tracking" without Always location permission and verify the message that Always access is required.
8. Simulate or verify low-battery frequent disabling and confirm that frequent status reports the low-battery reason.

Deferred Places validation once Places exist:

1. Create a saved place such as Home or Work.
2. Search for the proximity action in Shortcuts.
3. Choose device, place, and radius.
4. Use the returned Boolean in an automation.
5. Validate distance calculation against known test coordinates.

## Automated Coverage

`AppIntentsPreparationTests` covers the implementation layer that can be tested without Siri:

- known-device entity mapping
- current-location-access filtering
- API-location mapping
- no-location and unauthorized errors
- Apple Maps URL privacy
- Apple Maps direction and transport behavior
- Miataru navigation URL defaults, direction, presentation, and transport override behavior
- Shortcuts foreground handoff
- frequent tracking explicit duration, omitted duration, unlimited duration, renewal, and precondition failures
- low-battery frequent status
- on-screen annotation helper privacy filtering
- App Intent localization completeness
- parameter-summary localization key coverage
- App Shortcut phrase localization coverage
- App Shortcut phrase table placement, so trigger phrases stay out of `Localizable.xcstrings`

Manual Siri/Shortcuts validation remains required because App Shortcut phrase discovery and Siri recognition are only realistic on device or simulator.

## iOS 26 Schema Roadmap Boundary

The earlier "App Actions" research concluded that Apple's newer Siri/App Intents direction is still based on App Intents, Intent/Entity Schemas, Spotlight semantic indexing, View Annotations, and AppIntentsTesting rather than a separate framework path. That roadmap is now documented as iOS 26 SDK readiness in `Intent-Sprint/`.

For the current implemented actions:

- Keep `TrackedDeviceEntity`, `TrackedDeviceQuery`, and the dynamic-options fallback in place.
- Keep Frequent Tracking as custom App Intents unless an Apple schema maps cleanly without distorting Miataru's privacy semantics.
- Revisit direct `TrackedDeviceEntity` shortcut parameters, `IndexedEntity`, snippets, View Annotations, and AppIntentsTesting through the separate `Intent-Sprint/` plan.

## Deferrals And Risks

- Add an explicit per-device "Show in Siri/Shortcuts" permission if product requirements demand finer control than `hasCurrentLocationAccess`.
- Add persisted Places before building place/proximity intents.
- Wire snippet views only when deployment target and AppIntents APIs allow the integration cleanly.
- Continue manual Siri testing whenever shortcut phrases, dialog text, or entity/parameter registration changes.
