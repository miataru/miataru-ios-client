# Automation Event Store

## Summary

This stage adds a Miataru-owned event model for internal state changes that Shortcuts cannot observe as native automation triggers. The EventStore makes automation behavior inspectable, testable, and privacy-safe.

The EventStore is not a replacement for App Intents. It is the internal history that App Intents can query, export, or clear.

## Event Kinds

Start with a compact event enum:

```swift
enum MiataruAutomationEventKind: String, Codable, CaseIterable {
    case navigationStarted
    case navigationEnded
    case frequentTrackingStarted
    case frequentTrackingStopped
    case frequentTrackingExpired
    case trackingPaused
    case trackingResumed
    case personLocationUpdated
    case personEnteredPlace
    case personLeftPlace
    case unknownVisitorDetected
    case deviceKeyBlockedOperation
    case lowBatteryDisabledFrequentTracking
}
```

`personEnteredPlace` and `personLeftPlace` are included for schema stability but should not be emitted until Places and watches exist.

## Event Record

Use a small Codable record stored in Application Support:

```swift
struct MiataruAutomationEventRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MiataruAutomationEventKind
    let timestamp: Date
    let privacyLevel: MiataruAutomationEventPrivacyLevel
    let personID: String?
    let personDisplayName: String?
    let placeID: String?
    let placeName: String?
    let latitude: Double?
    let longitude: Double?
    let payload: [String: String]
}

enum MiataruAutomationEventPrivacyLevel: String, Codable, CaseIterable, Sendable {
    case publicSummary
    case privateLocation
    case securitySensitive
}
```

Storage rules:

- Store only the minimum data needed to explain the event.
- Avoid DeviceKey entirely.
- Avoid raw API responses.
- Avoid unknown visitor raw identifiers unless they are explicitly needed for a security workflow and marked `securitySensitive`.
- Keep exact coordinates optional and only for events that require location semantics.
- Cap the event log by count and age to avoid unbounded growth.

## EventStore API

Add a small actor or serial store:

```swift
protocol MiataruAutomationEventStoring: Sendable {
    func append(_ event: MiataruAutomationEventRecord) async
    func latest(matching filter: MiataruAutomationEventFilter) async -> MiataruAutomationEventRecord?
    func recent(since date: Date?, limit: Int) async -> [MiataruAutomationEventRecord]
    func clear(olderThan date: Date?) async
}
```

Use the same persistence style as nearby stores, such as Application Support JSON files, unless the implementation team decides SwiftData is already required elsewhere. Do not introduce SwiftData only for this stage.

## Event Sources

First emission points:

- Miataru navigation starts from App Intent or deep link: `navigationStarted`.
- Navigation view exits or route ends where detectable: `navigationEnded`.
- Manual frequent tracking starts: `frequentTrackingStarted`.
- Manual frequent tracking stops: `frequentTrackingStopped`.
- Frequent expiry notification path: `frequentTrackingExpired`.
- Low-battery auto-disable path: `lowBatteryDisabledFrequentTracking`.
- DeviceKey auth blocks an intent or operation: `deviceKeyBlockedOperation`.
- Unknown visitor alert candidate is accepted for notification: `unknownVisitorDetected`.

Do not emit high-volume `personLocationUpdated` events for every background location update in the first version. If needed later, throttle and summarize them.

## Event App Intents

Add these as App Intents but not App Shortcuts initially:

- `GetLatestMiataruEventIntent`
- `ListRecentMiataruEventsIntent`
- `ClearMiataruEventsIntent`
- `ExportAutomationEventIntent`

Structured output should include kind, timestamp, summary text, privacy level, optional person display name, optional place name, and a compact payload dictionary. Spoken dialogs should summarize one or a few events, not dump JSON.

## Schema And Indexing

Default schema decisions:

- Keep event intents custom.
- Do not index event records in Spotlight in v1.
- Do not expose `MiataruAutomationEventEntity` for semantic search by default.
- Revisit indexing only for user-visible, privacy-safe summaries after an event log UI exists.

If an event entity is added for App Intents outputs, keep it local to App Intents and avoid global indexing.

## Optional Shortcut Callback Bridge

Miataru may later support user-configured callback shortcuts through `shortcuts://run-shortcut`, but callbacks are explicitly optional bridge behavior.

Rules:

- EventStore remains the source of truth.
- Callback configuration must be explicit and user-visible.
- Payload must be compact text or JSON.
- Missing shortcut, URL failure, cancellation, and background limitations must be non-destructive.
- Callback failures should record diagnostic events without retry loops.

## Testing

Add tests for:

- Event encoding and decoding.
- Append, latest, list, and clear behavior.
- Retention by count and age.
- Privacy sanitization for DeviceKey, raw responses, and hidden identifiers.
- Event emission from frequent tracking start and stop.
- Event emission from low-battery auto-disable and unknown visitor notification paths when feasible with existing test seams.
- Event query intents returning stable summaries.

## Explicit Deferrals

- Do not implement place-enter/place-leave emission until Places and watches exist.
- Do not build a UI event log in this stage unless separately requested.
- Do not index events in Spotlight.
- Do not use Shortcuts URL callbacks as automation triggers.

