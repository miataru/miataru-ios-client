# Widget Device Selection Fix (2026-05-21)

## Context

The configurable Miataru widgets could show a stale device after the user selected a different device in the widget configuration. Reopening the configuration showed the newly selected device, but the rendered widget content and map still displayed the previously selected device.

## Root Cause

The widget configuration stored the selected device as an `AppEntity`. The configuration UI could persist and rehydrate the entity selection, but the timeline rendering path still depended on resolving that entity back into the current shared widget payload. When the payload only contained cached location entries for some devices, or when WidgetKit reused an older timeline entry, the rendered widget could fall back to the previous cached device.

The shared widget payload also used `devices` as both:

- the selectable device list
- the list of devices with cached location data

Those two lists have different lifecycles. A device should be selectable even when it does not yet have cached widget location data.

## Changes

### Stable Selection Payload

`WidgetSharedPayload` now carries a separate `deviceSelections` list in both the app target and the widget extension. The app-side sync coordinator writes all known devices into that list in `KnownDeviceStore` order, independent from cached location availability.

### Direct Widget Parameter

`DeviceSelectionIntent.device` now stores the selected device as a raw `String` device ID with a `DynamicOptionsProvider`. The options provider still presents friendly device names in the widget configuration UI, but the timeline provider receives the exact selected device ID directly.

This avoids relying on `AppEntity` rehydration during timeline generation.

### Timeline Selection Resolution

`WidgetTimelineDataLoader` now:

- starts from the configured device ID as the primary target
- canonicalizes IDs case-insensitively against known shared IDs
- preserves configured IDs even when no cached widget payload entry exists yet
- keeps location entries ordered by the stable selection list
- preserves selection metadata when merging fresh widget-fetched locations

### Device Store Ordering

`KnownDeviceStore` now normalizes table positions after load, add, move, and removal operations. The iPhone device list now routes drag reordering through `KnownDeviceStore.move(...)`, ensuring moves update persisted positions and resync widget data.

## Validation

Validated with:

```sh
xcodebuild build -project miataru/miataru.xcodeproj -scheme miataruWidgets -destination 'platform=iOS Simulator,id=7ED97B9D-79EA-45DD-B5E7-5E7E51BBD515'
```

Result: build succeeded and AppIntents metadata was generated for `miataruWidgets`.

```sh
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,id=7ED97B9D-79EA-45DD-B5E7-5E7E51BBD515' -only-testing:miataruTests/WidgetDataSyncCoordinatorTests
```

Result: the targeted widget data sync test passed.

```sh
git diff --check
```

Result: no whitespace errors.
