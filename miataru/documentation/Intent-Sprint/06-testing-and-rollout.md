# Testing And Rollout

## Summary

The Intent Sprint touches system integrations that can fail outside normal unit tests. Validation must cover pure service behavior, App Intents metadata shape, localization, privacy, Shortcuts, Spotlight, Siri, and iOS availability.

This document defines the testing and rollout requirements for every stage in this folder.

## Test Layers

Use multiple layers rather than relying on one broad UI test:

- Pure unit tests for service-layer result structs and policy decisions.
- App Intents preparation tests for entities, parameters, privacy-safe URLs, and dialogs.
- Persistence tests for EventStore, Places, and watch records.
- Localization key coverage for all app locales.
- Availability tests or compile checks for iOS 26-only schema, indexing, and annotation code.
- Manual Shortcuts validation for promoted App Shortcuts and power-user App Intents.
- Spotlight validation for indexed entities on iOS 26+.
- Siri validation on iOS 26+ devices or simulators where supported.
- AppIntentsTesting validation where the local Xcode toolchain exposes the framework.

## Existing Commands

Use the existing scripts where possible:

```sh
miataru/scripts/test-unit.sh
miataru/scripts/test-ui.sh
miataru/scripts/test-functional-ui-serial.sh
miataru/scripts/test-all.sh
```

For focused local work, use `xcodebuild test` against `miataruTests` and the specific test suite being changed.

## Stage-Specific Coverage

### Schema And Entity Foundation

Required coverage:

- `KnownDevice` to `TrackedPersonEntity` mapping.
- Hidden devices and empty DeviceIDs excluded.
- Dynamic string options remain available for Shortcuts.
- iOS 26-only schema adapters are availability-gated.
- Indexed payload builders exclude DeviceKey, server URL, raw DeviceID where not required, exact coordinates, and raw API responses.
- View annotation builders emit identifiers only for visible, authorized entities.

### Status Intents

Required coverage:

- Tracking enabled, disabled, and blocked states.
- Frequent tracking active, inactive, expiring, and unlimited states.
- Permission and DeviceKey failures.
- Person status with current location and cached place text.
- No location, hidden person, and no people configured.
- Distance calculation and missing current-user-location fallback.
- ETA route provider success and failure through an injectable seam.
- Dialogs remain short and privacy-safe.

### Navigation And Frequent Controls

Required coverage:

- Current navigation defaults remain unchanged.
- Direction, transport, and presentation parameters map to expected deep-link options.
- Apple Maps URLs continue to avoid DeviceID and display name leakage.
- Frequent duration uses injected clock and produces expected expiry.
- Stop frequent remains idempotent.
- View annotation handoff excludes hidden or unauthorized devices.

### Automation Event Store

Required coverage:

- Event append, latest, recent list, and clear.
- Retention by count and age.
- Codable migration behavior if event schema changes.
- Privacy sanitizer prevents DeviceKey and raw payload leaks.
- Frequent tracking and known notification paths emit expected events.
- Event query/export intents return stable summaries.

### Places, Proximity, And Watches

Required coverage:

- Place persistence round trip.
- Radius validation.
- Place entity query and name search.
- Proximity calculation with accuracy expansion.
- Hidden people excluded.
- Place Spotlight payload excludes person presence.
- Watch transition detection and cooldown once watches are implemented.

## Manual Validation

Before merging an implementation stage:

- Open the Shortcuts app and confirm promoted App Shortcuts appear with localized titles, summaries, and icons.
- Run each new App Intent from Shortcuts with valid and invalid inputs.
- Confirm dialogs are understandable when spoken aloud.
- Confirm errors are actionable and do not expose private implementation details.
- On iOS 26+, validate Spotlight results for any indexed entities.
- On iOS 26+, validate Siri flows that depend on schemas or on-screen context.
- On iOS 26+, validate annotated screens by asking about visible content where Siri support is available.

## Availability And Toolchain Checks

The implementation target is Xcode 26.5 / iOS 26.5 SDK, while the app deployment target remains iOS 18.6.

Every iOS 26-only feature must satisfy:

- Code is guarded with `@available(iOS 26.0, *)` or a compatible compile-time pattern.
- Lower-runtime behavior falls back to existing custom App Intents, dynamic options, or no-op indexing/annotation.
- Tests or build checks prove lower-runtime code paths still compile.
- The implementation does not require raising `IPHONEOS_DEPLOYMENT_TARGET`.

If `AppIntentsTesting` is not importable in the active local toolchain, document that as a validation gap and continue with unit tests, Shortcuts, Spotlight, and Siri manual validation.

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

Ship in small stages:

1. Entity/schema foundation and tests.
2. Status intents and curated App Shortcuts.
3. Parameterized navigation and frequent controls.
4. EventStore and event query/export intents.
5. Places and proximity checks.
6. Watches and optional callback bridge.

Each stage should be mergeable on its own and should preserve existing App Shortcuts behavior.

## Explicit Deferrals

- Do not require AppIntentsTesting if the framework is unavailable in the local Xcode installation.
- Do not promote every App Intent as an App Shortcut.
- Do not require Siri validation for lower-runtime devices.
- Do not raise the deployment target as part of the Intent Sprint.

