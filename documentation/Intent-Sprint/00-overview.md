# Intent Sprint Overview

## Summary

This folder is the implementation plan for the next Miataru App Intents and automation sprint. The goal is not to add a long list of App Shortcuts. The goal is to build a small, privacy-safe automation model:

- A curated set of high-value App Shortcuts for normal users.
- More granular App Intents for Shortcuts power users, Spotlight, Action Button, Siri, widgets, and future system surfaces.
- A Miataru-owned event log for internal state changes that Shortcuts cannot trigger directly.
- An iOS 26-ready entity and schema foundation for Siri, Apple Intelligence, Spotlight semantic search, and on-screen context.

All documentation in this folder is written in English and is intended to be directly usable by an implementer.

## Current App State

The current app already has a first App Intents layer, documented here with the device-facing names used for future work:

- `TrackedDeviceEntity` represents configured Miataru devices for App Intents.
- `TrackedDeviceQuery` and `TrackedDeviceOptionsProvider` resolve selectable devices.
- `FindDeviceLocationIntent` returns privacy-friendly location text.
- `OpenRouteToDeviceIntent` opens Apple Maps without leaking DeviceKey or raw API data.
- `OpenMiataruNavigationToDeviceIntent` opens Miataru's internal navigation deep link.
- `StartFrequentTrackingIntent` and `StopFrequentTrackingIntent` control manual frequent tracking.
- `IntentLocationService` and `IntentFrequentTrackingService` keep intent behavior testable.
- `AppIntentsPreparationTests` covers entity mapping, privacy-safe URLs, visible-device filtering, frequent tracking preconditions, and localization key coverage.

The current Shortcuts-facing device parameter intentionally uses dynamic string options because dynamic AppEntity selections have previously failed in Shortcuts with runtime serialization errors. Do not replace that path until entity selection is verified across Shortcuts, Spotlight, and Siri.

## Platform Reality Check

Miataru cannot register arbitrary personal automation triggers such as `MiataruNavigationStarted` in the Shortcuts app. Shortcuts personal automations are driven by system-defined trigger classes. Miataru can expose actions through App Intents and App Shortcuts, and it can optionally open `shortcuts://run-shortcut` for a user-configured shortcut, but that URL bridge is not a native event-trigger system.

The robust architecture is therefore:

1. Miataru records meaningful internal events in a local EventStore.
2. App Intents expose event query, export, and acknowledgement actions.
3. User-visible App Shortcuts remain curated and limited.
4. Optional callback bridges are treated as explicit user-configured integrations, not as the source of truth.

## iOS 26 Schema Readiness

The local development environment uses Xcode 26.5 and the iOS 26.5 SDK. The app deployment target remains iOS 18.6. The implementation plans in this folder treat iOS 26 App Intents features as available to the SDK but not available to every runtime user.

Important iOS 26 SDK capabilities to plan around:

- Entity schemas via the App Intents schema APIs, including SDK symbols such as `AssistantSchemas`, `@AppEntity(schema:)`, and `AssistantSchemaEntity`.
- Intent schemas via SDK symbols such as `@AssistantIntent(schema:)` and `AssistantSchemaIntent`.
- `IndexedEntity` and Core Spotlight helpers for semantic search.
- `IntentValueQuery` for structured entity or value lookup.
- Entity annotations through `AppEntityAnnotatable`, `NSUserActivity`, and View Annotation APIs.
- App Intents testing support where available in the active toolchain.

Because Miataru still deploys below iOS 26, any implementation using iOS 26-only APIs must be isolated behind compile-time and runtime availability gates. Existing App Intents behavior must continue to build and run on the current deployment baseline.

## Stage Map

- `01-schema-and-entity-foundation.md`: entity model, schema-fit policy, indexing rules, value queries, and view annotation targets.
- `02-status-intents.md`: first concrete implementation stage for tracking, frequent tracking, device status, distance, and ETA.
- `03-navigation-and-frequent-controls.md`: parameterized navigation and frequent tracking controls.
- `04-automation-event-store.md`: internal event model and event query/export intents.
- `05-places-proximity-and-watches.md`: persisted places, proximity checks, and later Miataru-native watches.
- `06-testing-and-rollout.md`: unit, integration, localization, Shortcuts, Spotlight, Siri, and availability validation.

## Product Rules

- Keep App Shortcuts curated. A shortcut tile should represent something a normal Miataru user can understand immediately.
- Expose advanced automation through App Intents, even when those intents are not promoted as App Shortcuts.
- Prefer service-layer result structs before intent wrappers so behavior remains testable without invoking App Intents runtime surfaces.
- Keep dialogs privacy-safe: no DeviceKey, no raw API response, no hidden identifiers unless the user explicitly requested technical detail.
- Keep structured outputs useful for Shortcuts power users while keeping spoken responses short.
- Do not adopt an Apple schema unless it matches Miataru semantics without implying the wrong domain, such as pretending tracked devices are Address Book contacts.

## References

- [Build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/)
- [Explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/)
- [Platforms State of the Union WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/)
- [App Intents](https://developer.apple.com/documentation/appintents)
- [App Shortcuts Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts)
- [Run a shortcut from a URL](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)
- [Use x-callback-url with Shortcuts](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios)
