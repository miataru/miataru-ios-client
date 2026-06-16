# Known-Device Access History Storage Limits

This document records the local storage limits and cleanup thresholds for known-device VisitorHistory access logging.

## Scope

Known-device access history records when a configured known device appears in VisitorHistory for the local device. It is stored locally as `MiataruAutomationEventKind.knownDeviceRequestedLocalPosition` in the automation event log.

The log is intentionally compact:

- No migration or historical backfill is performed.
- No extra `GetLocationHistory` request is made for old visits.
- Only newly observed VisitorHistory responses can create or update access-history rows.
- The stored requester location is the currently known location from `DeviceLocationCacheStore` at logging time, when available.

## Per-Device Retention

Known-device access history is retained per requesting device:

- Maximum summary rows per requesting known device: `100`.
- Retention unit: one summarized automation event row.
- Device matching is case-insensitive and uses normalized DeviceID matching.
- Trimming one device's access history must not remove another device's access history.

When a new row would exceed the per-device limit, the oldest matching summary row for that same requesting device is removed.

## Summary Window

Requests from the same known device are summarized inside a rolling 60-minute window:

- Summary window: `60 minutes`.
- A newer request inside the same window replaces the existing summary row.
- The replacement row keeps the same event identity and stores the newest request timestamp.
- The replacement row stores the currently known requester location at the newest request's logging time, when available.
- The summary count is incremented for newer requests merged into the row.
- Older or duplicate requests inside the same existing window do not replace the row.

Stored summary payload fields include:

- `visitTimestampMs`: newest VisitorHistory request timestamp in milliseconds.
- `summaryAccessCount`: number of merged requests represented by the row.
- `summaryEarliestTimestampMs`: earliest request timestamp represented by the row.
- `summaryWindowMinutes`: summary window size, currently `60`.
- `requestingDeviceLocationTimestamp`: timestamp of the requester-location snapshot, when available.
- `requestingDevicePlace`: reverse-geocoded requester place, when available.
- `source`: local logging source.

## Automation Event Store Bounds

The general automation event store still applies its global safety limits:

- Maximum total automation records: `2,500`.
- Default age retention: `90 days`.
- Payload entries per record: `12`.
- Payload key length: `48` characters.
- Payload value length: `160` characters.
- Identifier length: `128` characters.
- Display name length: `96` characters.
- Sensitive payload keys containing DeviceKey, authorization, auth, token, raw response, or API response markers are rejected.

The known-device access-history limit is enforced by the access-history writer with a device-scoped filter after append or replacement. The generic kind-cap mechanism remains available for other event-store uses, but known-device access history does not use a global kind-wide `100` cap.

## Approximate Storage Size

Each summarized row is JSON with compact metadata, optional coordinates, optional place text, and bounded payload fields. A full set of `100` rows for one device should normally be in the range of a few tens of kilobytes, with longer localized place names and display names pushing it upward. The global automation event file remains bounded by the `2,500` record limit and the sanitizer field limits above.

## Cleanup Triggers

Cleanup happens locally and opportunistically:

- The store prunes age and global count limits when it loads.
- The store prunes before and after appending or replacing records.
- Access history trims the affected requesting device after each new or replaced summary row.
- Queries prune stale records before returning results.
- Clearing all automation events removes the backing file when no records remain.
