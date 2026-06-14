# Testing And Rollout

## Summary

The Intent Sprint touches system integrations that can fail outside normal unit tests. Validation must cover pure service behavior, App Intents metadata shape, localization, privacy, Shortcuts, Spotlight, Siri, and iOS availability.

This document now records the post-step-05 validation state for the implemented Intent Sprint work. Entity/schema foundations, status intents, navigation/frequent controls, the automation EventStore, and places/proximity checks have automated preparation coverage. Watches, the visible Places UI annotation pass, and any callback bridge remain deferred.

Local validation on 2026-06-14 used Xcode 26.5 with the iOS 26.5 simulator SDK. The app deployment target remains iOS 18.6.

## Test Layers

Use multiple layers rather than relying on one broad UI test:

- Pure unit tests for service-layer result structs and policy decisions.
- App Intents preparation tests for entities, parameters, privacy-safe URLs, and dialogs.
- Persistence tests for EventStore and Places.
- Localization key coverage for all app locales.
- Availability tests or compile checks for iOS 26-only schema, indexing, and annotation code.
- Manual Shortcuts validation for promoted App Shortcuts and power-user App Intents.
- Spotlight validation for indexed entities on iOS 26+.
- Siri validation on iOS 26+ devices or simulators where supported.
- AppIntentsTesting validation only if a future local Xcode toolchain exposes the framework.

## Existing Commands

Use the existing scripts where possible:

```sh
miataru/scripts/test-unit.sh
miataru/scripts/test-ui.sh
miataru/scripts/test-functional-ui-serial.sh
miataru/scripts/test-all.sh
```

For focused local work, use `xcodebuild test` against `miataruTests` and the specific test suite being changed.

Observed focused validation:

```sh
miataru/scripts/test-unit.sh -only-testing:miataruTests/AppIntentsPreparationTests -only-testing:miataruTests/MiataruPlaceStoreTests -only-testing:miataruTests/MiataruAutomationEventStoreTests
```

Result on 2026-06-14: passed, with 54 Swift Testing cases across `AppIntentsPreparationTests`, `MiataruAutomationEventStoreTests`, and `MiataruPlaceStoreTests`.

## Stage-Specific Coverage

### Schema And Entity Foundation

Implemented automated coverage:

- `KnownDevice` to `TrackedDeviceEntity` mapping.
- Hidden devices and empty DeviceIDs excluded.
- Dynamic string options remain available for Shortcuts.
- Indexed payload builders exclude DeviceKey, server URL, raw DeviceID where not required, exact coordinates, and raw API responses.
- Device user activity annotation emits only entity identifiers for visible, authorized entities on iOS 26+.

Deferred:

- Additional iOS 26 schema adapters remain deferred until an Apple schema maps cleanly to Miataru's privacy model.

### Status Intents

Implemented automated coverage:

- Tracking enabled, disabled, and blocked states.
- Frequent tracking active, inactive, expiring, and unlimited states.
- Permission and DeviceKey failures.
- Device status with current location and cached place text.
- No location, hidden device, and no devices configured.
- Distance calculation and missing current-user-location fallback.
- ETA route provider success and failure through an injectable seam.
- Dialogs remain short and privacy-safe.

### Navigation And Frequent Controls

Implemented automated coverage:

- Current navigation defaults remain unchanged.
- Direction, transport, and presentation parameters map to expected deep-link options.
- Apple Maps URLs continue to avoid DeviceID and display name leakage.
- Frequent duration uses injected clock and produces expected expiry.
- Stop frequent remains idempotent.
- View annotation handoff excludes hidden or unauthorized devices.

### Automation Event Store

Implemented automated coverage:

- Event append, latest, recent list, and clear.
- Retention by count and age.
- Current schema version loading and corrupt-file recovery.
- Privacy sanitizer prevents DeviceKey and raw payload leaks.
- Frequent tracking and known notification paths emit expected events.
- Event query/export intents return stable summaries.

Deferred:

- Codable migration behavior should be expanded when the event schema changes.

### Places, Proximity, And Watches

Implemented automated coverage:

- Place persistence round trip.
- Device-scoped place validation, including duplicate names rejected within one device and allowed across devices.
- Radius validation.
- Place entity query and name search.
- Proximity calculation with accuracy expansion.
- Hidden devices excluded.
- Place Spotlight payload excludes device presence.
- Place intent output privacy, including no raw coordinates or raw DeviceIDs.

Deferred:

- Visible Places UI annotations, including saved place rows, map markers, and detail views.
- Watch record persistence, transition detection, cooldown behavior, and local notification scheduling.
- Optional callback bridge.

## Manual Validation

Before shipping or merging a user-visible Intent Sprint release:

- Open the Shortcuts app and confirm promoted App Shortcuts appear with localized titles, summaries, and icons.
- Run promoted App Shortcuts and power-user App Intents from Shortcuts with valid and invalid inputs.
- Confirm status, navigation, frequent tracking, event query/export/clear, and place/proximity flows behave as documented in `../app-intents-current-shortcuts-and-manual-validation.md`.
- Confirm dialogs are understandable when spoken aloud.
- Confirm errors are actionable and do not expose private implementation details.
- On iOS 26+, validate Spotlight results for any indexed entities.
- On iOS 26+, validate Siri flows that depend on schemas or on-screen context.
- On iOS 26+, validate annotated screens by asking about visible content where Siri support is available.

## Availability And Toolchain Checks

The implementation target is Xcode 26.5 / iOS 26.5 SDK, while the app deployment target remains iOS 18.6.

Current local checks:

- Xcode: 26.5.
- iOS simulator SDK: 26.5.
- Deployment target: 18.6.
- `AppIntentsTesting` is not importable in the active local toolchain, so it is a validation gap rather than a release blocker.

Every iOS 26-only feature must continue to satisfy:

- Code is guarded with `@available(iOS 26.0, *)` or a compatible compile-time pattern.
- Lower-runtime behavior falls back to existing custom App Intents, dynamic options, or no-op indexing/annotation.
- Tests or build checks prove lower-runtime code paths still compile.
- The implementation does not require raising `IPHONEOS_DEPLOYMENT_TARGET`.
- If `AppIntentsTesting` becomes importable later, add App Intents runtime validation without replacing the existing service-layer and manual Shortcuts/Siri checks.

## Localization

All new user-visible strings need keys in the app's localization catalog and coverage across the existing app locales:

- `da`
- `de`
- `en`
- `es`
- `fi`
- `fr`
- `it`
- `ja`
- `nl`
- `zh-Hans`

The localization key test should fail if a new App Intent title, description, parameter, dialog, or error is missing in any supported locale.

## Rollout

Implemented stages:

1. Entity/schema foundation and tests.
2. Status intents and curated App Shortcuts.
3. Parameterized navigation and frequent controls.
4. EventStore and event query/export intents.
5. Places and proximity checks.

Deferred stages:

1. Visible Places UI and saved-place view annotations.
2. Watches and optional callback bridge.

Each stage remains mergeable on its own and should preserve existing App Shortcuts behavior.

## Explicit Deferrals

- Do not require AppIntentsTesting if the framework is unavailable in the local Xcode installation.
- Do not promote every App Intent as an App Shortcut.
- Do not require Siri validation for lower-runtime devices.
- Do not raise the deployment target as part of the Intent Sprint.
- Do not implement watches, local notification watch delivery, or callback bridge behavior as part of this docs-only step.
