# Status Intents

## Summary

This is the first concrete implementation stage. Add App Intents that answer status questions without opening a map or starting navigation:

- `GetTrackingStatusIntent`
- `GetFrequentTrackingStatusIntent`
- `GetPersonStatusIntent`
- `GetDistanceToPersonIntent`
- `GetETAForPersonIntent`

These intents should be service-first, structured where possible, privacy-safe in dialogs, and compatible with the existing dynamic string person parameter strategy.

## Existing Anchors

Reuse and extend the current App Intents implementation:

- `IntentLocationService` already resolves visible people and fetches current server locations.
- `IntentFrequentTrackingService` already exposes manual frequent tracking state and start/stop validation.
- `TrackedPersonOptionsProvider` already provides person choices for Shortcuts.
- `AppIntentsPreparationTests` already covers the right layer for service and intent preparation tests.

Do not build these intents by reading SwiftUI state directly. Add service-layer result structs first, then wrap those results in App Intent types.

## Planned Service Results

Add result structs that are independent of App Intents runtime protocols:

```swift
struct IntentTrackingStatus: Equatable, Sendable {
    let trackingEnabled: Bool
    let authorizationStatus: CLAuthorizationStatus
    let deviceKeyAuthBlocked: Bool
    let effectiveMode: IntentTrackingMode
    let frequentTracking: IntentFrequentTrackingStatus
}

enum IntentTrackingMode: String, Equatable, Sendable {
    case stopped
    case foregroundHighAccuracy
    case backgroundSignificantChange
    case smartWaiting
    case smartFrequentActive
    case manualFrequentActive
    case blocked
}

struct IntentFrequentTrackingStatus: Equatable, Sendable {
    let manualEnabled: Bool
    let smartEnabled: Bool
    let active: Bool
    let expiresAt: Date?
    let remainingSeconds: TimeInterval?
    let durationMode: FrequentBackgroundLocationUpdateDuration
    let blockingReason: IntentFrequentTrackingBlockingReason?
}

struct IntentPersonStatus: Equatable, Sendable {
    let personID: String
    let displayName: String
    let timestamp: Date
    let ageText: String
    let horizontalAccuracy: Double?
    let coarsePlaceDescription: String?
    let distanceMeters: Double?
    let bearingDegrees: Double?
}

struct IntentETAStatus: Equatable, Sendable {
    let personStatus: IntentPersonStatus
    let expectedTravelTimeSeconds: TimeInterval
    let distanceMeters: Double
    let transportMode: IntentTransportMode
}
```

Use existing cache and policy sources when possible. If the current code has no shared stale-location threshold, do not invent one in this stage; expose timestamp and age text and let later UI or policy work define stale categorization.

## Intent Behavior

| Intent | User question | Main service path | Output | App Shortcut |
| --- | --- | --- | --- | --- |
| `GetTrackingStatusIntent` | "Is Miataru tracking active?" | New status method backed by `SettingsManager` and `LocationManager` policy state | Tracking enabled, effective mode, authorization, DeviceKey blocked, frequent summary | Yes |
| `GetFrequentTrackingStatusIntent` | "How long is precise tracking active?" | Extend `IntentFrequentTrackingService` with a status method | Active/inactive, manual/smart, expiry, remaining time, blocking reason | Yes |
| `GetPersonStatusIntent` | "How old is Steffi's location?" | `IntentLocationService.latestLocation(for:)` plus formatting helpers | Display name, age, accuracy, coarse place, optional distance from user | Yes |
| `GetDistanceToPersonIntent` | "How far away is Steffi?" | Latest person location plus current user location if available | Distance in meters/km and bearing text | Yes |
| `GetETAForPersonIntent` | "How long will it take to reach Steffi?" | Latest person location plus `MKDirections` route request | ETA, route distance, transport mode, fallback error | No in first shortcut set unless UX testing shows it is reliable |

The first App Shortcuts set should promote only the most reliable user-facing actions. ETA can remain an App Intent until route failures, network behavior, and transport-mode prompts are polished.

## Schema Fit

Default schema decisions:

- `GetTrackingStatusIntent`: custom App Intent. No known Apple intent schema cleanly represents Miataru tracking privacy state.
- `GetFrequentTrackingStatusIntent`: custom App Intent. Frequent tracking is a Miataru-specific privacy and battery policy concept.
- `GetPersonStatusIntent`: custom App Intent. It queries a shared device/person record, not a generic contact profile.
- `GetDistanceToPersonIntent`: custom App Intent. It returns a privacy-scoped distance to a Miataru-tracked person.
- `GetETAForPersonIntent`: custom App Intent for v1. Revisit Apple schema fit only if an iOS 26 navigation/travel schema maps cleanly to Miataru's destination and transport semantics.

Do not block these intents on schema adoption. Add schema conformance later behind iOS 26 availability only if it improves Siri behavior without changing meaning.

## Privacy Constraints

All dialogs must avoid:

- DeviceKey.
- Raw DeviceID unless the intent is explicitly technical and user-requested.
- Raw Miataru API responses.
- Server URL.
- Unknown visitor identifiers.
- Exact coordinates in spoken text unless the user requested coordinate-style output.

Structured outputs may include coordinates only for intents where Shortcuts users need them and where the selected person already has current-location access. Spoken dialogs should prefer display name, age, coarse place, distance, accuracy, and ETA.

## Error Behavior

Reuse existing `IntentLocationError` cases and add status-specific errors only where needed.

Expected user-facing failures:

- No people configured.
- Selected person no longer exists.
- Selected person has no current-location access.
- No location available.
- Server unavailable or invalid server configuration.
- Tracking disabled.
- Always location permission missing for frequent background tracking.
- DeviceKey authentication blocks tracking or reads.
- ETA route cannot be calculated.

Every error must be localizable and covered by the localization key test.

## Localization

Add LocalizedStringResource keys for:

- Intent titles and descriptions.
- Parameter names and summaries.
- Dialogs for active/inactive tracking.
- Dialogs for frequent tracking expiry and no-expiry cases.
- Dialogs for person age, distance, accuracy, and coarse place.
- ETA success and ETA unavailable.
- New error messages.

Maintain coverage for all ten app locales through the existing localization-key test style.

## Testing

Extend `AppIntentsPreparationTests` or add a focused status-intents suite covering:

- Tracking status when tracking is off.
- Tracking status when DeviceKey auth is blocked.
- Frequent status inactive, active with expiry, active without expiry, and expired.
- Person status with visible person and cached place description.
- Hidden person rejected.
- Empty DeviceID rejected.
- Location age text remains stable with injected reference dates.
- Distance calculation uses great-circle distance and handles missing user location.
- ETA success can be tested with an injectable route provider.
- ETA failure returns a localized error without leaking the route request.
- Dialog text does not contain DeviceKey, raw response text, or unexpected identifiers.

## Explicit Deferrals

- Do not add Places dependencies to these intents.
- Do not add an EventStore dependency in this stage.
- Do not promote ETA to App Shortcuts until route reliability and prompt behavior are validated.
- Do not replace dynamic string person parameters with entity parameters until Shortcuts serialization is verified.

