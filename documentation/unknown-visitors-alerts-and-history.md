# Unknown Visitors, Alerts, And Visitor History

## Summary

This document consolidates unknown visitor alerts, known-device visitor notifications, known-device access history, unknown visitor list filtering, allowed-list handoff from unknown visitors, add-device locking, DeviceID case preservation, and visitor history slogan behavior.

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
- Known-device visitor notification implementation from 2026-06-15
- Known-device VisitorHistory access log implementation from 2026-06-16

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

## Known-Device Visitor Notifications

Known-device visitor notifications add a per-device opt-in layer on top of the existing VisitorHistory checks. The feature is meant for trusted or known devices where the user explicitly wants to know when that specific device recently looked up their position.

Scope:

- Disabled by default on every `KnownDevice`.
- Stored per device as `notifyOnVisitorHistoryAccess`, with legacy `NSSecureCoding` archives defaulting to false.
- The Edit Device toggle is shown only for other devices, never for the current device.
- The toggle is visible only when Smart Frequent or manual Frequent background updates are enabled in settings.
- Visibility follows the stored settings (`smartFrequentBackgroundLocationUpdatesEnabled` or `frequentBackgroundLocationUpdatesEnabled`), not the current Smart Frequent runtime phase.
- If both Smart Frequent and manual Frequent are disabled, existing per-device opt-ins are preserved but hidden and do not cause extra checks.

User behavior:

- Enabling the per-device toggle requests notification permission when needed.
- If permission is denied, the toggle is reset and the user sees a localized explanation with an app-settings shortcut.
- Notification title: "Positionsabfrage erkannt".
- Notification body format: "%@ hat gerade deine Position abgefragt."
- Tapping a `known_visitor_alert` notification opens the known device when it still exists; otherwise the tap is ignored without starting an add-device flow.

Trigger and fetch behavior:

- Known-device notifications are evaluated only during automatic Smart/manual frequent VisitorHistory checks.
- Foreground app opens, ordinary foreground location uploads, manual VisitorHistory screens, and active-app outbox flushes do not trigger known-device notifications.
- Unknown Visitor Alerts remain independent: they can still use the shared VisitorHistory fetch when enabled.
- When unknown alerts and known-device alerts are both active for the same eligible check, the service performs one shared VisitorHistory fetch.
- For "every update" visitor checks, `minimumInterval` is nil by design; the pipeline therefore carries an explicit `processKnownVisitorAlerts` context flag instead of inferring eligibility from the interval value.
- Queued location updates persist that context flag and re-check foreground/background state before processing, so a background item flushed later while the app is active cannot create a known-device notification.

Evaluation rules:

- DeviceIDs are normalized case-insensitively for comparison and persisted notification state.
- The current device is excluded.
- Only known devices with `notifyOnVisitorHistoryAccess == true` are considered.
- The evaluator keeps the newest VisitorHistory timestamp per watched device.
- A candidate must be inside the same 90-second recent-visitor window used by the device-list eye indicator.
- The same visitor timestamp is never notified twice.
- After a notification is successfully scheduled, the configured per-device cooldown suppresses further notifications until it expires.

Cooldown settings:

- Advanced Options expose "Known visitor notification cooldown".
- Default: 30 minutes.
- Allowed values: 1 minute, 5 minutes, 15 minutes, 30 minutes, 60 minutes.
- Runtime settings and iOS Settings.bundle values share the same key: `known_visitor_notification_cooldown`.

## Known-Device Access History

Known-device access history records when a configured device appears in VisitorHistory for the local device. It is separate from notifications: every known device is eligible for local logging, even if its per-device notification toggle is off.

Storage and retention:

- Stored as `MiataruAutomationEventKind.knownDeviceRequestedLocalPosition` in the local automation event log.
- Event timestamp is the VisitorHistory request time, not the later detection time.
- The access-history writer applies a per-requesting-device cap of 100 summarized records for known-device location requests.
- Duplicate records are suppressed by normalized DeviceID plus VisitorHistory timestamp.
- Requests from the same known device within one 60-minute summary window are stored as one event record. A newer request in that window replaces the existing summary row, increments its summary count, and stores the newest request time plus the currently known requester location at that newest request.
- VisitorHistory itself provides only requester DeviceID and request time. Miataru does not fetch requester location history or backfill older visits for this log; it records only newly observed known-device requests.
- When available, the event stores the currently known location of the requesting device from `DeviceLocationCacheStore` at logging time. The request time remains the VisitorHistory timestamp, while the requester-location timestamp is stored separately in the event payload.
- Each event stores the known device display name, normalized DeviceID, summary count/window metadata, current requester latitude/longitude when a cache snapshot exists, requester place text when reverse-geocoding is available, the requester-location snapshot timestamp, and bounded payload metadata.

Recording sources:

- Device-list location refreshes fetch up to 100 VisitorHistory entries and log known-device matches after updating the recent-visitor indicator.
- The standalone Visitor History view logs known-device matches from the loaded server response.
- Background visitor notification processing also logs known-device matches from the shared VisitorHistory response.
- No migration or extra `GetLocationHistory` request is performed for historic visits.

User-facing surfaces:

- Device Details shows a local "Location Requests" section below the QR code for other devices, listing all locally retained summarized access rows and requester place/coordinates.
- The new "Latest Request" App Shortcut can answer when a selected tracked device last requested the local position.
- General automation event query/export intents can also include the new event kind.
- Storage thresholds, payload bounds, per-device trimming, and cleanup triggers are documented in `known-device-access-history-storage-limits.md`.

## Alert Architecture

`UnknownVisitorAlertService` is an actor responsible for:

- `setFeatureEnabled(_:)`
- `processAfterSuccessfulLocationUpdate(serverURL:minimumInterval:processKnownVisitorAlerts:)`
- notification status evaluation and permission requests through a notifier abstraction
- watermark-based incremental visitor processing
- own/known/ignored-device filtering
- per-device 24-hour cooldown
- known-device recent-visitor evaluation and per-device configurable cooldown
- best-effort enrichment lookup
- local notification scheduling
- in-flight coalescing for parallel trigger calls

`UnknownVisitorAlertEvaluator` owns pure selection logic:

- timestamp parsing and normalization
- DeviceID normalization
- watermark progression
- cooldown checks

`KnownVisitorAlertEvaluator` owns the known-device selection logic:

- watched-device normalization
- current-device exclusion
- newest timestamp per watched device
- 90-second recent-window filtering
- duplicate timestamp suppression
- configurable cooldown checks

Trigger integration:

- After direct successful `updateLocation` submit in `LocationManager`.
- After successful outbox item delivery in `LocationUpdateDeliveryCoordinator`.

Persistence keys:

- `unknown_visitor_alerts_enabled`
- `unknown_visitor_alert_last_processed_ts_ms`
- `unknown_visitor_alert_last_notified_by_device`
- `known_visitor_alert_last_notified_at_by_device`
- `known_visitor_alert_last_notified_visit_ts_by_device`

Localization includes onboarding copy, settings toggles/explanations, permission denied hints/CTA, notification titles/bodies, detailed unknown visitor body, fallback body, and known visitor cooldown option explanations.

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
- `LocationUpdateOutboxStoreTests`
- `LocationTrackingPolicyTests`
- `DeviceLinkResolverTests`
- Full scheme run with 141 unit tests and 5 UI tests for unknown visitor add lock.
- Notification sound tests verifying unknown visitor alerts use `confirm.caf`.
- Earlier refresh/onboarding validation with 115 unit tests passing.
- 2026-06-15 full scheme validation on `miataru Tests - iPhone 16` with 287 tests passing.
- 2026-06-16 focused validation of `KnownVisitorAccessHistoryTests`, `MiataruAutomationEventStoreTests`, and `AppIntentsPreparationTests` with 54 tests passing.

Regression coverage verifies:

- Known VisitorHistory matches record requester location/place data, exclude own and unknown devices, and deduplicate repeated visitor timestamps.
- The access-history writer enforces the 100-record cap per requesting device for known-device location request events without dropping other devices' access rows.
- Known/allowed visitor plus unknown visitor enriches only the unknown ID.
- Only known/allowed visitors schedule no notification and no supplemental lookup.
- Known-device visitor notifications run only from explicit frequent visitor-check context, not from normal app opens or foreground uploads.
- Watched known devices can share the VisitorHistory fetch with unknown visitor alerts without duplicate fetches.
- Known-device alert evaluation excludes unwatched devices and the current device, respects the 90-second recent window, suppresses duplicate timestamps, and honors 1/5/15/30/60-minute cooldown values.
- Queued background updates persist and forward the known-visitor processing context while active-app flushes remain guarded.
- Own, known, ignored, whitespace-padded, and differently cased IDs are normalized before filtering.
- iPhone/iPad unknown visitor list filtering excludes known and ignored IDs consistently.
- URI and scanner parsing preserve mixed-case IDs.
- Known-device routing remains case-insensitive and returns stored canonical ID.
- Unknown-device add requests and notification action requests preserve source and case.
