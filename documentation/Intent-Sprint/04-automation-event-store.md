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
    case deviceLocationUpdated
    case deviceEnteredPlace
    case deviceLeftPlace
    case unknownVisitorDetected
    case deviceKeyBlockedOperation
    case lowBatteryDisabledFrequentTracking
}
```

`deviceEnteredPlace` and `deviceLeftPlace` are included for schema stability but should not be emitted until Places and watches exist.

## Event Record

Use a small Codable record stored in Application Support:

```swift
struct MiataruAutomationEventRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: MiataruAutomationEventKind
    let timestamp: Date
    let privacyLevel: MiataruAutomationEventPrivacyLevel
    let deviceID: String?
    let deviceDisplayName: String?
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
- Treat localization as required anywhere event data becomes user-facing: intent titles, descriptions, parameter summaries, dialogs, event summaries, kind labels, privacy labels, storage-stat labels, and export-facing stable labels where useful.
- Keep the storage and retrieval implementation as battery-, CPU-, and storage-space conserving as possible.

## Storage Size, Growth, And Housekeeping

V1 uses a single Application Support JSON file named `automation-events.json` with schema version `1`, ISO-8601 dates, and atomic writes. If decoding fails, remove the invalid file and start with an empty in-memory log rather than repeatedly attempting to parse corrupt data.

Use the selected default retention policy:

- Retain at most 90 days.
- Retain at most 2,500 records.
- Enforce whichever limit is hit first.

Expected persistent size:

- Typical events should be compact: about 250-700 bytes per record after JSON overhead.
- At 2,500 records, the persistent file should usually stay below about 2 MB.
- Security-sensitive events may carry a small normalized identifier where required, but the payload remains bounded.

Housekeeping policy:

- Run housekeeping only on load, append, query, export, and clear.
- Prune old records first, then enforce the count cap by dropping oldest records.
- Persist only when the in-memory set actually changed.
- Do not add background polling, recurring cleanup tasks, file watchers, Spotlight indexing, or database compaction jobs in this stage.

Payload bounds:

- Trim identifiers and display names.
- Omit nil or empty optionals.
- Limit payload key/value pairs.
- Cap payload key and value length.
- Reject DeviceKey, authorization, token, and raw API-style payload fields through a sanitizer.

Resource-conservation assessment:

- JSON is sufficient for the expected bounded size; SwiftData, Core Data, SQLite, and indexing would add CPU, IO, migration, and maintenance cost that is not justified for v1.
- Reads are lazy and tied to explicit query/export/storage-stat actions.
- Writes happen only after accepted events, clear operations that remove records, or housekeeping that actually changes the persisted set.
- No high-volume event sources are enabled in this stage.

## EventStore API

Add a small actor or serial store:

```swift
protocol MiataruAutomationEventStoring: Sendable {
    func append(_ event: MiataruAutomationEventRecord) async
    func latest(matching filter: MiataruAutomationEventFilter) async -> MiataruAutomationEventRecord?
    func recent(since date: Date?, limit: Int) async -> [MiataruAutomationEventRecord]
    func clear(olderThan date: Date?) async -> Int
}
```

Use the same persistence style as nearby stores, such as Application Support JSON files, unless the implementation team decides SwiftData is already required elsewhere. Do not introduce SwiftData only for this stage.

Add a small recording facade so feature code can emit events without knowing persistence details. This keeps call sites easy to test with a fake or no-op recorder.

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

Do not emit high-volume `deviceLocationUpdated` events for every background location update in the first version. If needed later, throttle and summarize them.

V1 non-emission decisions:

- Do not emit `deviceLocationUpdated`.
- Do not emit `deviceEnteredPlace`.
- Do not emit `deviceLeftPlace`.
- Do not emit a frequent-tracking stop event for an already-inactive no-op.
- Emit `unknownVisitorDetected` only after notification scheduling succeeds; never include the normalized visitor ID in spoken dialogs.

## Event App Intents

Add these as App Intents but not App Shortcuts initially:

- `GetLatestMiataruEventIntent`
- `ListRecentMiataruEventsIntent`
- `ClearMiataruEventsIntent`
- `ExportAutomationEventIntent`

Structured output should include kind, timestamp, summary text, privacy level, optional device display name, optional place name, and a compact payload dictionary. Spoken dialogs should summarize one or a few events, not dump JSON.

For v1, return structured JSON strings from the event query and export intents. Each event object includes `kind`, `timestamp`, `summary`, `privacyLevel`, optional `deviceDisplayName`, optional `placeName`, and `payload`.

## Local Storage Statistics UI

Add a localized "Local storage" section to the existing "Details zur Standortverfolgung" / Location Tracking Details screen, visible whether location tracking is currently enabled or disabled.

The section reports total local storage plus compact per-store rows with localized names, formatted byte counts, and record/item counts where they are cheap to compute. It must not show DeviceKey, raw API payloads, raw event payload values, or hidden identifiers.

Known stores to include:

- Automation event store.
- Location diagnostics log.
- Location update outbox.
- Known devices.
- Device groups.
- Device location cache.
- Widget shared data/config.
- Widget map snapshot cache.
- UserDefaults-backed stores shown as counts or estimated size only when cheap to compute.

Refresh behavior:

- Refresh on view appear.
- Refresh on scene activation.
- Refresh after clear/export/storage-changing actions where the app has a direct hook.
- Do not use a timer or continuous filesystem scan for storage statistics.

Reporter behavior:

- Read file attributes only for known store URLs.
- Do not decode store contents just to calculate sizes.
- Traverse only known shallow snapshot directories and only count matching files.

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
- Corrupt-file recovery.
- Privacy sanitization for DeviceKey, raw responses, and hidden identifiers.
- No-op persistence avoidance.
- Storage metadata.
- Local storage reporter missing-file, directory-total, widget-snapshot-style, and byte-formatting behavior.
- Intent JSON shape, no-event behavior, clear count, localized dialogs, and privacy-sensitive summaries.
- Event emission from frequent tracking start and stop.
- Event emission from low-battery auto-disable and unknown visitor notification paths when feasible with existing test seams.
- Event query intents returning stable summaries.
- Localization coverage for new `intent_` and storage UI keys across all app locales, including placeholder safety.

## Explicit Deferrals

- Do not implement place-enter/place-leave emission until Places and watches exist.
- Do not build a UI event log in this stage unless separately requested.
- Do not index events in Spotlight.
- Do not use Shortcuts URL callbacks as automation triggers.
