# Places, Proximity, And Watches

## Summary

Places are the largest product expansion in the Intent Sprint. They enable questions like "Is Steffi home?" and later watches like "Tell me when Steffi reaches the hotel."

This stage happened after status intents and the EventStore foundation. Places are schema-ready entities from the start, but watches still wait until the visible Places UI and event recording behavior are reliable enough for notifications.

Implementation status: the base saved-place store, `MiataruPlaceEntity`, place query, and proximity App Intents are implemented. Places are device-scoped in the data model and intent layer so the future UI can define each device's own saved places from the device detail page. The visible Places UI is planned separately in `../Places-Sprint/00-overview-concept.md`. Watches remain deferred.

Implemented files:

- `miataru/miataru/SettingsManagers/App Settings/Places/MiataruPlaceStore.swift`
- `miataru/miataru/AppIntents/Entities/MiataruPlaceEntity.swift`
- `miataru/miataru/AppIntents/Queries/MiataruPlaceQuery.swift`
- `miataru/miataru/AppIntents/Intents/PlaceIntents.swift`
- `miataru/miataru/AppIntents/Services/IntentLocationService.swift`

## Place Model

The implemented local place store persists records shaped as:

```swift
struct MiataruPlaceRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var deviceID: String
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
- Every place belongs to one tracked device via `deviceID`.
- Coordinates are stored locally only.
- Place names are user-visible, unique per device, and may be indexed only after the user saves the place.
- The same place name may exist for different devices.
- Empty device IDs are rejected.

The store uses Application Support JSON persistence through `places.json`. Invalid or corrupt store contents are discarded rather than surfaced to App Intents.

## Place Entity

`MiataruPlaceEntity` has:

- Stable ID.
- Owning device ID for app-internal scoping and future device-detail UI grouping.
- Display name.
- Radius subtitle.
- `EntityQuery` for exact ID lookup.
- `EntityStringQuery` for name search.
- iOS 26 schema conformance remains deferred unless a neutral place/location entity schema fits.
- `IndexedEntity` only for user-saved place names and non-sensitive metadata.

Do not index live device presence at a place.

## Proximity Intents

Implemented intents:

- `SaveCurrentPlaceIntent`
- `ListPlacesIntent`
- `IsDeviceNearPlaceIntent`
- `FindDevicesNearPlaceIntent`

Behavior:

- `SaveCurrentPlaceIntent` saves the user's current location as a named place for one selected tracked device with a radius.
- `ListPlacesIntent` returns saved places for one selected tracked device.
- `IsDeviceNearPlaceIntent` checks the latest authorized location for one selected device against one saved place owned by that device.
- `FindDevicesNearPlaceIntent` checks all visible devices with current-location access against one saved place.
- Save and list use `TrackedDeviceOptionsProvider` so the device parameter has the same Shortcuts reliability profile as the other device-selection intents.
- Place JSON output omits raw coordinates and owning device IDs; the owning `deviceID` is internal scoping metadata.

Distance calculation should use a shared Haversine helper or existing map helper. A device is near a place when the center distance is less than or equal to the place radius plus the reported horizontal accuracy when accuracy exists.

## Schema Fit

Default schema decisions:

- `MiataruPlaceEntity` should be built to support an Apple place/location entity schema if the SDK exposes one that matches saved user places.
- Proximity intents remain custom because "is this Miataru-tracked device near this saved place" is app-specific.
- `SaveCurrentPlaceIntent` may be evaluated for a schema only if the schema represents saving a user-defined place and does not imply adding a contact address or calendar location.

## Spotlight Indexing

Index only:

- Place ID.
- Place name.
- Optional locality or user-visible label.

Do not index:

- DeviceKey.
- Server URL.
- Raw device locations.
- Device presence at a place.
- Watch rules.
- Private callback configuration.

Keep indexing behind iOS 26 availability and provide a no-op lower-runtime path.

## View Annotation Targets

On iOS 26+:

- Annotate saved place rows with `MiataruPlaceEntity` once the visible UI exists.
- Annotate place markers on maps once the visible UI exists.
- Annotate the active place in a place detail view once the visible UI exists.
- Annotate devices and places together only when both are already visible and authorized.

These annotations support context like "check whether this device is near this place" without requiring the user to repeat names.

## Watches

Watches are Miataru-native rules, not Shortcuts triggers.

Future watch model:

```swift
struct MiataruPlaceWatchRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var deviceID: String
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
- Record `deviceEnteredPlace` and `deviceLeftPlace` events in the EventStore.
- Send local notifications when enabled and permitted.
- Avoid high-frequency polling.
- Apply cooldowns to avoid notification spam.

Planned watch intents after the base place model is stable:

- `StartPlaceWatchIntent`
- `StopPlaceWatchIntent`
- `ListActiveWatchesIntent`

## Testing

Implemented coverage:

- Place persistence round trip.
- Name trimming and duplicate-name handling.
- Duplicate place names rejected within one device and allowed across different devices.
- Radius validation.
- Place query by ID and name.
- Proximity calculation with and without horizontal accuracy.
- Hidden devices excluded from proximity checks.
- Spotlight indexing payload excludes private data.
- Current-location save rejects stale user locations.
- Place intent dialogs and JSON omit raw coordinates, raw device IDs, DeviceKey, and server URLs.

Deferred coverage:

- View annotation builders emit only visible saved places once the visible UI exists.
- Watch transition detection for outside-to-inside and inside-to-outside state changes.
- Watch cooldown behavior.

## Explicit Deferrals

- Do not implement watches before the EventStore exists.
- Do not trigger user shortcuts directly from proximity checks.
- Do not index place watches.
- Do not infer home/work labels automatically.
- Do not expose device-at-place facts to Spotlight.
