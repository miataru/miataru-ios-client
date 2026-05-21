# Unknown Visitor Alert Enrichment Filter (2026-05-21)

## Context
Unknown-visitor alerts enrich notification text with supplemental device data such as slogan and city. Before this fix, the enrichment path could fetch `GetLocation` data for visitor-history entries that were already known/allowed devices. Because a `GetLocation` request itself can appear in the reciprocal visitor history, this made it look as if a known device had requested the user's own location.

## Goal
- Keep unknown-visitor alert enrichment available for real unknown devices.
- Prevent known/allowed devices from triggering supplemental `GetLocation` requests during visitor-history processing.
- Keep normal location-update delivery unchanged.
- Use one shared unknown-visitor filter for iPhone and iPad lists.

## Implementation
### Alert Service
`UnknownVisitorAlertService` now separates the processing stages explicitly:

1. Load visitor history for the current device.
2. Evaluate visitors with normalized own, known, and ignored device IDs.
3. Persist the visitor-history watermark.
4. Enrich only `evaluation.candidates`.
5. Schedule notifications only for those unknown candidates.

The supplemental lookup is batched per processing run. Candidate device IDs are normalized and deduplicated, cached slogan/city data is reused first, and one `GetLocation` request is issued only for candidates with missing supplemental data.

Known/allowed devices are excluded before the lookup. A device is considered known when its normalized ID is present in `KnownDeviceStore.shared.devices`; the local allowed-device list uses the same `KnownDevice` entries.

### Shared Visitor Filter
`UnknownVisitorFilter` provides the same normalized filtering behavior for iPhone and iPad unknown-visitor lists:

- trim and uppercase device IDs
- exclude the current device
- exclude known devices
- exclude ignored visitor IDs
- keep the newest visitor entry per device

This keeps UI refreshes from including known/allowed devices in unknown-visitor lists.

## Location Update Isolation
Normal location delivery still sends the user's own update through `LocationUpdateDeliveryCoordinator` and `MiataruAppAPI.updateLocation`. The unknown-visitor alert check remains a post-success hook. The additional supplemental `GetLocation` request can only happen inside visitor-history alert processing, after a visitor-history response has produced unknown candidates.

## Validation
- `UnknownVisitorAlertEvaluatorTests`
- `DeviceLocationCacheStoreTests`
- `VisitorHistoryViewModelTests`
- `LocationUpdateDeliveryCoordinatorTests`

Regression coverage verifies that:

- a known/allowed visitor plus an unknown visitor only enriches the unknown ID
- only known/allowed visitors do not schedule notifications or supplemental location requests
- own, known, ignored, whitespace-padded, and differently cased IDs are normalized before filtering
- iPhone/iPad unknown-visitor list filtering excludes known and ignored IDs consistently
- the normal location-update delivery coordinator behavior still passes its existing test suite
