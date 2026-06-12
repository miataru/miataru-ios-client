# Unknown Visitors, Alerts, And Visitor History

## Summary

This document consolidates unknown visitor alerts, unknown visitor list filtering, allowed-list handoff from unknown visitors, add-device locking, DeviceID case preservation, and visitor history slogan behavior.

## Source Notes Consolidated

This document consolidates:

- `unknown-visitor-alerts-phase1-2026-03-09.md`
- `unknown-visitor-allowed-device-list-flow-2026-03-25.md`
- `unknown-visitor-alert-enrichment-filter-2026-05-21.md`
- `unknown-visitor-add-device-lock-2026-05-25.md`
- `unknown-device-case-preservation-2026-05-27.md`
- `visitor-history-slogan-display-2026-03-11.md`
- Visitor refresh details from `location-permission-devicekey-onboarding-refresh-2026-05-13.md`
- Unknown visitor sound mapping from `notification-sounds-2026-06-07.md`

## Unknown Visitor Alerts

Unknown Visitor Alerts are an opt-in local notification feature that informs users when an unknown device requests their location.

Scope:

- Disabled by default.
- Can be enabled from Settings and full onboarding.
- Uses one centralized permission flow.
- Runs after successful location delivery.
- Dedupe/cooldown is per unknown device for 24 hours.
- Localized across all supported app locales.

User behavior:

- Setting: `unknownVisitorAlertsEnabled`, default false.
- If notification permission is `notDetermined`, enabling requests permission.
- If permission is authorized, provisional, or ephemeral, the feature stays enabled.
- If denied, the feature switches back off and shows a hint with an app-settings shortcut.
- Foreground notifications present with banner/list/sound.
- Notification body can include slogan and city when enrichment succeeds; otherwise it uses a generic fallback.
- Unknown visitor notifications use `confirm.caf` through `MiataruNotificationSounds`.

## Alert Architecture

`UnknownVisitorAlertService` is an actor responsible for:

- `setFeatureEnabled(_:)`
- `processAfterSuccessfulLocationUpdate(serverURL:)`
- notification status evaluation and permission requests through a notifier abstraction
- watermark-based incremental visitor processing
- own/known/ignored-device filtering
- per-device 24-hour cooldown
- best-effort enrichment lookup
- local notification scheduling
- in-flight coalescing for parallel trigger calls

`UnknownVisitorAlertEvaluator` owns pure selection logic:

- timestamp parsing and normalization
- DeviceID normalization
- watermark progression
- cooldown checks

Trigger integration:

- After direct successful `updateLocation` submit in `LocationManager`.
- After successful outbox item delivery in `LocationUpdateDeliveryCoordinator`.

Persistence keys:

- `unknown_visitor_alerts_enabled`
- `unknown_visitor_alert_last_processed_ts_ms`
- `unknown_visitor_alert_last_notified_by_device`

Localization includes onboarding copy, settings toggle/explanation, permission denied hint/CTA, notification title, detailed body, and fallback body.

## Enrichment And Filtering

Unknown visitor enrichment must never cause known or allowed devices to look like new reciprocal visitors.

The alert service now separates processing:

1. Load visitor history for the current device.
2. Evaluate visitors with normalized own, known, and ignored IDs.
3. Persist the watermark.
4. Enrich only unknown candidates.
5. Schedule notifications only for unknown candidates.

Supplemental lookup:

- Batched per processing run.
- Candidate IDs are normalized and deduplicated.
- Cached slogan/city data is reused first.
- One `GetLocation` request is issued only for unknown candidates with missing supplemental data.
- Known/allowed devices are excluded before lookup.

`UnknownVisitorFilter` provides shared normalized filtering for iPhone and iPad lists:

- trim and uppercase DeviceIDs for comparison
- exclude current device
- exclude known devices
- exclude ignored visitor IDs
- keep newest visitor entry per device

Normal location delivery remains isolated: own-location upload still goes through `LocationUpdateDeliveryCoordinator` and `MiataruAppAPI.updateLocation`. The supplemental `GetLocation` request can only happen after visitor-history alert processing produces unknown candidates.

## Unknown Visitor Lists And Allowed Device List Flow

Unknown visitors are visible in device lists on iPhone and iPad even when the Allowed Device List is disabled.

Behavior:

- Unknown visitor section is not coupled to `settings.allowedDeviceListEnabled`.
- `UnknownVisitorRow` accepts a configurable add action title.
- Add action label is contextual:
  - Allowed Device List active: "Add and Allow"
  - Allowed Device List inactive: "Add"

Add Device flow:

- If Allowed Device List is active, the existing ACL section remains visible.
- If inactive, the form shows an activation block with enable button, loading state, inline error, and disabled explanation.
- After activation, security status for the currently entered device reloads.
- Save is disabled during activation.

Edit Device flow:

- If Allowed Device List is inactive, Edit Device shows the same activation block.
- After activation, the dialog switches into normal ACL configuration without losing context.
- Close/Save is disabled during activation.

Result:

- Users can add an unknown device without enabling access control first.
- Users can also enable access control directly from Add/Edit and immediately configure ACL settings.

## Unknown Visitor Add Device Lock

Unknown visitor add flows now lock the source DeviceID because the app is adopting a specific visitor from context.

Affected entry points:

- Unknown Visitor list in Devices tab.
- Unknown-device action sheet.
- Notification action.
- Visitor History in the QR tab.
- Standalone Visitor History.

Implementation:

- `AddDeviceRequest` carries source `.general` or `.unknownVisitor`.
- `AppNavigationCoordinator.openAddDevice` defaults to `.general`.
- Unknown visitor entry points pass `.unknownVisitor`.
- `iPhone_AddDeviceView` accepts `allowsDeviceIDEditing`, default true.
- When editing is false, the DeviceID section shows a monospaced, text-selectable value; the QR scan button and text field are hidden.

Preserved behavior:

- Plus button add flow remains editable and keeps QR scan.
- Unknown `miataru://<DeviceID>` deep links remain prefilled but editable.

## DeviceID Case Preservation

Unknown devices can arrive through lists, action sheets, notifications, scanner input, and external links. Comparison paths intentionally normalize DeviceIDs, but display/persistence paths must preserve source casing.

Current rules:

- `DeviceLinkResolver.trimmedDeviceID(_:)` removes surrounding whitespace while preserving letter case.
- `deviceID(from:)` and `deviceID(fromCanonicalCode:)` return trimmed original casing.
- `normalizedDeviceID(_:)` still uppercases for comparison and cache-like keys.
- `AppNavigationCoordinator` uses the trimmed DeviceID for add-device and unknown-device action requests.
- Known-device routing stays case-insensitive and returns the stored canonical DeviceID when a match exists.

Result:

- Unknown visitors with lowercase or mixed-case IDs preserve original spelling when opened from list or action sheet.
- External links and QR scanner input preserve case for unknown devices.
- Known devices still resolve case-insensitively.

## Visitor History Slogans

Visitor history rows now display slogans more consistently:

- Known-device visitor rows render cached slogans when available.
- `fetchSloganIfNeeded()` is no longer restricted to unknown devices.
- Refresh throttling remains through `DeviceSloganCacheStore.refreshSloganIfStale(..., minimumRefreshInterval: 300)`.
- Unknown visitor behavior is unchanged: slogan remains the preferred primary subtitle.
- Known visitor rows can show slogan information without losing last-seen, distance, or location details.

## My Device Visitor History Refresh

The My Device tab forces a visitor-history refresh when it appears. If visitor data is already present, the refresh runs without the loading state so the UI does not visibly reset. This keeps the visible visitor list aligned with the recent-visitor indicator used elsewhere in the app.

Affected views:

- `iPhone_MyDeviceQRCodeView`
- `iPhone_VisitorHistoryView`

## Validation History

Validation included:

- App build validation for iOS target.
- Unit tests for evaluator and notification permission flow.
- Localization completeness tests for alert keys.
- `UnknownVisitorAlertEvaluatorTests`
- `DeviceLocationCacheStoreTests`
- `VisitorHistoryViewModelTests`
- `LocationUpdateDeliveryCoordinatorTests`
- `DeviceLinkResolverTests`
- Full scheme run with 141 unit tests and 5 UI tests for unknown visitor add lock.
- Notification sound tests verifying unknown visitor alerts use `confirm.caf`.
- Earlier refresh/onboarding validation with 115 unit tests passing.

Regression coverage verifies:

- Known/allowed visitor plus unknown visitor enriches only the unknown ID.
- Only known/allowed visitors schedule no notification and no supplemental lookup.
- Own, known, ignored, whitespace-padded, and differently cased IDs are normalized before filtering.
- iPhone/iPad unknown visitor list filtering excludes known and ignored IDs consistently.
- URI and scanner parsing preserve mixed-case IDs.
- Known-device routing remains case-insensitive and returns stored canonical ID.
- Unknown-device add requests and notification action requests preserve source and case.
