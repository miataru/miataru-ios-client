# Places UI/UX Overview And Concept

## Summary

Places are user-saved named areas attached to a specific tracked device. They make Miataru easier to ask about: "Is Steffi home?", "Is Daniel at work?", and later "Tell me when Daniel leaves work." The first implementation stage provides the data model and App Intents foundation. The visible Places UI is a separate product sprint and should make places feel like first-class parts of each device detail page without exposing raw coordinates unnecessarily.

The future UI should define and manage places from the device detail page. Each device owns its own set of places, so "Home" for Steffi and "Home" for Daniel are separate records. A later aggregate Places overview may exist, but it must not replace the device-detail ownership model.

## Current Foundation

- The local `MiataruPlaceStore` already persists places with an owning `deviceID`.
- App Intents can save the current user location as a place for a selected device, list places for a selected device, and run proximity checks.
- Same-name places are allowed across different devices and rejected within one device.
- Place intent output omits raw coordinates and owning device IDs; those remain internal implementation data.
- The visible in-app Places UI, edit/delete flows, map radius editing, and watches are not implemented yet.

## Product Model

- A place is a local-only saved location with an owning `deviceID`, user-visible name, and radius.
- The default creation path is "save my current location" with a default radius of 150 meters.
- Radius must stay bounded between 50 meters and 5000 meters.
- Place names must be trimmed, non-empty, and unique case/diacritic-insensitively per device.
- The same place name is allowed for different devices.
- Raw coordinates remain implementation data. Show maps and locality-like context where useful, but avoid presenting latitude/longitude as primary UI.
- Device-at-place facts are live proximity results, not persisted place metadata.

## Information Architecture

- Add a Places section inside each device detail page.
- On iPhone, the device detail page should show the device's places below the current status/map content or behind a segmented detail view if space requires it.
- On iPad, the selected device detail/sidebar layout should include a Places section for that selected device.
- The first Places surface should be the usable per-device list, not an educational landing page.
- Keep place creation and management out of Settings; Settings may link to storage/privacy details only.
- A later global Places overview may list all saved places grouped by device, but create/edit/delete belongs to the owning device context.

## Core Screens

- Device Places list: saved places for the selected device sorted by name, each row showing name and radius, with quick access to detail and edit.
- Empty state: concise action to add a place for this device; mention location permission only if permission blocks creation.
- Place detail: map centered on the place, visible radius circle, name, radius, created/updated metadata, owning device context, and future watch summary.
- Create sheet: name field, radius control, current-location preview, owning device shown as context, permission/staleness errors, Save and Cancel.
- Edit sheet: rename and radius edit; coordinates are not editable in v1.
- Delete confirmation: clear wording that deleting a place also disables future watches tied to it when watches exist.
- Error states: current location unavailable, current location too old, duplicate name, invalid radius, and location permission denied.

## Interaction Requirements

- Primary creation flow: from a device detail page, save the current location for that device, then name it and adjust radius if needed.
- Use a numeric radius input or stepped choices that make common values easy: 50 m, 150 m, 300 m, 500 m, 1000 m, and custom.
- Show a radius circle before save so users understand the area being saved.
- If current location is stale, explain that Miataru needs a fresh location and offer retry.
- Do not infer Home, Work, or other sensitive labels automatically.
- Require an owning tracked device for every place.
- Deletion should be explicit and undo-free unless a broader undo system already exists.

## Privacy And System Integration

- Spotlight may index saved place names and non-sensitive radius/locality labels only.
- Never index raw coordinates, DeviceKey, server URL, device IDs, live device presence, watch rules, or callback configuration.
- App Intents may use device ownership internally, but spoken output and JSON should avoid raw coordinates and raw device IDs.
- Device proximity dialogs should speak display names only and use the existing privacy-safe fallback when a display name is effectively the raw device ID.
- iOS 26 view annotations should attach `MiataruPlaceEntity` to saved place rows, place detail, and map markers once the UI exists.
- Device and place annotations may be combined only when both are already visible and authorized in the current UI context.

## Future Watches

- Watches are Miataru-native rules, not Shortcuts personal automation triggers.
- Watch UI belongs in the device-owned place detail and can later add "when this device enters" and "when this device leaves" rules.
- A watch row should show device display name, enter/leave condition, enabled state, last fired time, and notification permission status.
- Watches must use existing refresh paths and cooldowns rather than high-frequency polling.
- Watch events should record `deviceEnteredPlace` and `deviceLeftPlace` in the Automation EventStore only after the base place model is stable.

## Acceptance Criteria

- Users can understand a device's Places from the device detail page without instructional text blocks.
- Saving a current location is possible with one clear primary action when permissions and location freshness allow it.
- Radius editing is visible, bounded, and reflected on a map.
- Raw coordinates and device identifiers are not exposed in normal UI, Spotlight, or spoken responses.
- iPhone and iPad both treat Places as first-class device-detail content while respecting their existing navigation patterns.
- Watches remain visually planned but not implemented until the Places foundation and event recording behavior are reliable.
