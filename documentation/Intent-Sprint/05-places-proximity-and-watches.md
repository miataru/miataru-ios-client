# Places, Proximity, And Watches

## Summary

Places are the largest product expansion in the Intent Sprint. They enable questions like "Is Steffi home?" and later watches like "Tell me when Steffi reaches the hotel."

This stage should happen after status intents and the EventStore foundation. Places must be designed as schema-ready entities from the start, but watches should wait until place persistence and event recording are reliable.

## Place Model

Add a local persisted place store before adding proximity intents:

```swift
struct MiataruPlaceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    var createdAt: Date
    var updatedAt: Date
}
```

Defaults:

- Minimum radius: 50 meters.
- Default radius: 150 meters.
- Maximum radius: 5000 meters.
- Coordinates are stored locally only.
- Place names are user-visible and may be indexed only after the user saves the place.

Use Application Support JSON persistence unless another local persistence layer is already being introduced at the same time.

## Place Entity

Add `MiataruPlaceEntity` with:

- Stable ID.
- Display name.
- Optional coarse subtitle, such as radius or locality.
- `EntityQuery` for exact ID lookup.
- `EntityStringQuery` for name search.
- iOS 26 schema conformance only if a neutral place/location entity schema fits.
- `IndexedEntity` only for user-saved place names and non-sensitive metadata.

Do not index live person presence at a place.

## Proximity Intents

Planned intents:

- `SaveCurrentPlaceIntent`
- `ListPlacesIntent`
- `IsPersonNearPlaceIntent`
- `FindPeopleNearPlaceIntent`

Behavior:

- `SaveCurrentPlaceIntent` saves the user's current location as a named place with a radius.
- `ListPlacesIntent` returns saved places.
- `IsPersonNearPlaceIntent` checks the latest authorized location for one selected person against one saved place.
- `FindPeopleNearPlaceIntent` checks all visible people with current-location access against one saved place.

Distance calculation should use a shared Haversine helper or existing map helper. A person is near a place when the center distance is less than or equal to the place radius plus the reported horizontal accuracy when accuracy exists.

## Schema Fit

Default schema decisions:

- `MiataruPlaceEntity` should be built to support an Apple place/location entity schema if the SDK exposes one that matches saved user places.
- Proximity intents remain custom because "is this Miataru-tracked person near this saved place" is app-specific.
- `SaveCurrentPlaceIntent` may be evaluated for a schema only if the schema represents saving a user-defined place and does not imply adding a contact address or calendar location.

## Spotlight Indexing

Index only:

- Place ID.
- Place name.
- Optional locality or user-visible label.

Do not index:

- DeviceKey.
- Server URL.
- Raw person locations.
- Person presence at a place.
- Watch rules.
- Private callback configuration.

Keep indexing behind iOS 26 availability and provide a no-op lower-runtime path.

## View Annotation Targets

On iOS 26+:

- Annotate saved place rows with `MiataruPlaceEntity`.
- Annotate place markers on maps.
- Annotate the active place in a place detail view.
- Annotate people and places together only when both are already visible and authorized.

These annotations support context like "check whether this person is near this place" without requiring the user to repeat names.

## Watches

Watches are Miataru-native rules, not Shortcuts triggers.

Future watch model:

```swift
struct MiataruPlaceWatchRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var personID: String
    var placeID: UUID
    var condition: MiataruPlaceWatchCondition
    var isEnabled: Bool
    var createdAt: Date
    var lastFiredAt: Date?
}

enum MiataruPlaceWatchCondition: String, Codable, CaseIterable, Sendable {
    case enters
    case leaves
}
```

Watches should:

- Use existing location refresh paths where possible.
- Record `personEnteredPlace` and `personLeftPlace` events in the EventStore.
- Send local notifications when enabled and permitted.
- Avoid high-frequency polling.
- Apply cooldowns to avoid notification spam.

Planned watch intents after the base place model is stable:

- `StartPlaceWatchIntent`
- `StopPlaceWatchIntent`
- `ListActiveWatchesIntent`

## Testing

Add tests for:

- Place persistence round trip.
- Name trimming and duplicate-name handling.
- Radius validation.
- Place query by ID and name.
- Proximity calculation with and without horizontal accuracy.
- Hidden people excluded from proximity checks.
- Spotlight indexing payload excludes private data.
- View annotation builders emit only visible saved places.
- Watch transition detection for outside-to-inside and inside-to-outside state changes.
- Watch cooldown behavior.

## Explicit Deferrals

- Do not implement watches before the EventStore exists.
- Do not trigger user shortcuts directly from proximity checks.
- Do not index place watches.
- Do not infer home/work labels automatically.
- Do not expose person-at-place facts to Spotlight.

