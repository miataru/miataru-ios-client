# Schema And Entity Foundation

## Summary

This stage defines how Miataru should model people, places, groups, routes, and automation events for App Intents, Siri, Apple Intelligence, Spotlight, and on-screen awareness. It is a foundation stage, not a visual feature. The implementation should make later intents easier to add without changing privacy semantics or the existing Shortcuts behavior.

The important shift is to treat iOS 26 schema and annotation APIs as implementation inputs now. They are not deferred to a future iOS 27-only phase.

## Availability Policy

Miataru currently builds with the iOS 26.5 SDK and deploys to iOS 18.6. Any iOS 26-only feature must be added without breaking the baseline app:

- Keep existing `AppEntity`, `EntityQuery`, and dynamic string option behavior available to all supported OS versions.
- Put iOS 26-only schema, indexing, value query, and annotation code behind `@available(iOS 26.0, *)` or equivalent compile/runtime guards.
- Prefer small adapter files for iOS 26 features so the main entity and intent code stays readable.
- Do not raise the deployment target as part of this sprint.
- If a type or macro name differs between Xcode 26.x seeds, verify the final SDK spelling through Xcode autocomplete or the Swift interface before implementation.

## Entity Strategy

| Entity | Source of truth | Query model | Indexing | Schema decision | Annotation target |
| --- | --- | --- | --- | --- | --- |
| `TrackedPersonEntity` | `KnownDeviceStore` through `IntentLocationService` | Keep `TrackedPersonQuery`; keep `TrackedPersonOptionsProvider` for Shortcuts until AppEntity selection is stable | Do not index exact coordinates. Consider indexing only display name and non-sensitive metadata after explicit validation | Keep custom first. Add schema conformance only if the SDK exposes a neutral person/device schema that does not imply Contacts ownership | Device rows, device detail, map-selected device |
| `MiataruPlaceEntity` | Future persisted place store | `EntityQuery`, `EntityStringQuery`, later `IntentValueQuery` | Index user-named places when enabled; do not index live person presence | Prefer an Apple place/location schema if it maps to saved places without exposing private coordinates unexpectedly | Place rows, map place markers |
| `MiataruGroupEntity` | `DeviceGroupStore` | `EntityQuery` and name search | Index group names only if groups are user-created and visible in app UI | Keep custom unless a generic collection/group schema fits | Group rows and group map screens |
| `MiataruRouteEntity` | Route/navigation runtime and `RouteCacheStore` | No broad query in v1; use as return value or current-route status later | Do not index transient routes by default | Keep custom. Apple navigation schemas should be adopted only if they match Miataru's direction/privacy model | Current navigation screen |
| `MiataruAutomationEventEntity` | Future `MiataruAutomationEventStore` | Event query intents, not global search | Do not index by default. Revisit only for explicit user-visible event summaries | Keep custom | Event log screen if one is added |

## Schema Adoption Rules

Entity schemas and intent schemas are useful only when they make Siri understand Miataru more accurately. Do not adopt a schema merely because one exists.

Adopt a schema only when all of these are true:

- The Apple schema describes the same concept Miataru exposes.
- Required schema fields can be populated without leaking DeviceKey, hidden DeviceID, raw server payloads, or exact coordinates beyond the user's intent.
- The schema does not imply ownership in another app domain, such as Contacts, Messages, Photos, or Calendar.
- The same behavior can remain available as a custom App Intent on older OS versions.

Default decisions for this sprint:

- Status, privacy, frequent tracking, and automation-event intents remain custom App Intents.
- `TrackedPersonEntity` remains custom in Stage 1. Schema conformance may be added behind iOS 26 availability only after validating a neutral schema fit.
- Places are designed as schema-ready from the start because user-named places are more likely to match system semantic search behavior than live tracked-person locations.
- Navigation/open actions may use existing App Intents and OpenIntent-style behavior first. Adopt an intent schema only if it preserves Miataru's route direction and privacy semantics.

## Query And Resolution Plan

Keep the current two-track person resolution model:

- For Shortcuts parameters, continue using `TrackedPersonOptionsProvider` with dynamic string options until `TrackedPersonEntity` parameter serialization is verified.
- For Spotlight/Siri/entity resolution, keep `TrackedPersonQuery` and add iOS 26-specific resolution helpers only behind availability gates.

Add `IntentValueQuery` only when it improves an actual Siri or Spotlight flow:

- Candidate for Stage 2: resolve a status value for a selected person.
- Candidate for Places: resolve saved places by name, coarse area, or user-defined aliases.
- Do not add `IntentValueQuery` for transient automation events in the first EventStore stage.

## Spotlight Indexing Plan

Indexing must be conservative because Miataru handles location-sharing data.

- Do not index exact live coordinates for tracked people.
- Do not index DeviceKey, DeviceID, server URL, raw visitor IDs, or raw API payloads.
- For `TrackedPersonEntity`, indexing is limited to display names and non-sensitive metadata if product review confirms that the system search benefit is worth it.
- For `MiataruPlaceEntity`, indexing saved place names is acceptable once the user has explicitly created the place in Miataru.
- For groups, index only user-visible group names and stable group identifiers.
- For automation events, keep data out of Spotlight by default.

## View Annotation Plan

Use entity annotations to let Siri understand visible Miataru context on iOS 26+ while keeping older OS behavior unchanged.

First annotation targets:

- Device list rows: annotate each visible row with `TrackedPersonEntity`.
- Device map detail: use `NSUserActivity.appEntityIdentifier` for the primary displayed person/device.
- Group map markers: annotate multiple visible device markers with their `TrackedPersonEntity` identifiers.
- Navigation screen: annotate the destination person and, later, the active route.
- Future place rows and markers: annotate visible `MiataruPlaceEntity` values.

Implementation guidance:

- Use `NSUserActivity` annotation for one primary visible entity.
- Use View Annotation APIs for multiple visible entities in lists and maps.
- Keep annotation identifiers stable and privacy-safe.
- Do not annotate hidden devices or devices without current-location access.
- Do not annotate unknown visitors until they are explicitly accepted or represented in a privacy-safe event summary.

## Testing

Add or extend tests around:

- Entity mapping from `KnownDevice` to `TrackedPersonEntity`.
- Hidden devices and empty DeviceIDs never appearing in queries or annotations.
- Dynamic string options remaining compatible with Shortcuts.
- iOS 26-only code being availability-gated and excluded from lower-runtime paths.
- Indexed entities excluding DeviceKey, raw DeviceID where not needed, exact coordinates, and raw payloads.
- View annotation builders producing identifiers only for visible, authorized entities.

## Explicit Deferrals

- Do not create a full Places store in this stage.
- Do not replace current Shortcuts person parameters with entity parameters until runtime testing proves stability.
- Do not index automation events.
- Do not adopt a Contacts or messaging schema for tracked devices unless Apple provides a schema that matches Miataru's concept without changing meaning.

