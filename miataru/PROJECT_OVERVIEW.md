# miataru iOS App - Project Overview

## Current State

miataru is a privacy-focused iPhone and iPad app for location sharing through user-selected Miataru servers. The current app metadata is **3.2.1** with an iOS deployment target of **18.6**. The app target is SwiftUI-based, includes a WidgetKit extension, and is localized for ten app locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, and `zh-Hans`.

Mac-specific view files exist for previews/scaffolding only. The shipping project targets iPhone and iPad.

## Architecture

```text
miataruApp.swift
├── MiataruRootView
│   ├── iPhone_RootView
│   └── iPad_RootView
├── OnboardingContainerView
├── LocationManagers/
│   ├── LocationManager.swift
│   ├── LocationManager+Types.swift
│   ├── LocationManager+PolicyCompatibility.swift
│   ├── LocationTrackingPolicy.swift
│   ├── SmartFrequentBackgroundPolicy.swift
│   ├── LocationSamplePolicy.swift
│   ├── LocationBackgroundForensics.swift
│   ├── LocationBackgroundForensicsRecorder.swift
│   ├── CoreLocationServiceController.swift
│   ├── LocationUpdateUploadService.swift
│   ├── LocationUpdateMetricsStore.swift
│   ├── HeadingSmoother.swift
│   ├── DeviceLocationRefresher.swift
│   └── RouteCacheStore.swift
├── Networking/
│   ├── MiataruAppAPI.swift
│   ├── MiataruRequestExecutor.swift
│   ├── MiataruRetryPolicy.swift
│   ├── LocationUpdateDeliveryCoordinator.swift
│   └── LocationUpdateOutboxStore.swift
├── Notifications/
│   ├── UnknownVisitorAlertService.swift
│   ├── UnknownVisitorFilter.swift
│   └── FrequentBackgroundTrackingReminderService.swift
├── AppIntents/
│   ├── Entities/
│   ├── Queries/
│   ├── Intents/
│   └── MiataruAppShortcutsProvider.swift
├── Services/
│   └── IntentLocationService.swift
├── SettingsManagers/
│   ├── App Settings/
│   ├── Devices/
│   ├── Groups/
│   ├── SharedWidgetData.swift
│   ├── WidgetDataSyncCoordinator.swift
│   └── PersistentDataCleanup.swift
├── views/
│   ├── Common/
│   ├── iPhone/
│   ├── iPad/
│   └── Mac/
├── miataruWidgets/
└── Assets/
```

## Core Domains

### Location Tracking

`LocationManager` is the app-facing ObservableObject facade for permission state, local GPS updates, heading updates, app lifecycle hooks, Core Location delegate glue, published UI state, and upload status. It keeps the public API stable while delegating pure decisions and small stateful responsibilities to focused internal components:

- `LocationTrackingPolicy` resolves service modes, background configuration, service command plans, restore/reconcile decisions, delivery intervals, and low-battery frequent-mode disablement.
- `SmartFrequentBackgroundPolicy` owns Smart runtime phase decisions, activation evidence, speed/derived movement checks, exit-fence behavior, inactivity timeouts, and watchdog recovery.
- `LocationSamplePolicy` owns location batch sorting, invalid/stale/future/out-of-order sample rejection, sensitivity bypass, and upload deduplication keys.
- `LocationBackgroundForensics` owns background gap assessment, foreground-recovery burst decisions, and significant-change re-arm policy.
- `LocationManager+Types` and `LocationManager+PolicyCompatibility` keep UI-facing nested names, typealiases, and existing static policy wrappers stable while the facade shrinks.
- `LocationBackgroundForensicsRecorder` persists forensic state, significant-change re-arm status, and gap/recovery-burst evidence.
- `CoreLocationServiceController` applies the selected tracking mode to the primary and frequent `CLLocationManager` instances, Core Location service sessions, background indicator state, and stale frequent-callback cleanup.
- `LocationUpdateUploadService`, `LocationUpdateMetricsStore`, and `HeadingSmoother` encapsulate upload payload/background-task handling, 24-hour counter persistence, and heading/course smoothing.

The service-level resolver still produces one of four modes:

- stopped
- foreground high accuracy
- background significant-change monitoring
- frequent background updates with configured distance/accuracy

Foreground tracking uses high accuracy. Background tracking defaults to the battery-saving standard mode backed by significant-change monitoring. Smart frequent updates add a policy layer on top of that default: when enabled, Smart waits in the standard mode, enters a probing frequent-runtime phase from exit-fence, trusted GPS-speed, or trusted derived-movement evidence, confirms active frequent mode only after accepted frequent-background movement, and deactivates again after the shared inactivity window when no relevant movement is confirmed. Missing frequent callbacks are treated as watchdog/reassert recovery, not as stillness. The full if-then resolver and Smart phase machine are documented in `documentation/location-tracking-state-machines-2026-06-07.md`.

Manual frequent background updates remain available as Stage 2 after Smart frequent updates are enabled. The manual mode overrides Smart runtime decisions and is bounded by user-configured distance, duration, delivery delay, visitor-check interval, reminder/expiration notifications, and low-battery auto-disable. Smart frequent runtime uses the same frequent-mode distance, delivery-delay, and visitor-check interval policies. Existing installs that had manual frequent mode enabled are migrated with both the Smart prerequisite and manual mode enabled; the UI locks Smart while the manual override is active.

The location-status UI reports the user-facing background policy separately from the underlying service mode: significant-change, Smart waiting, Smart frequent active, manual frequent active, and foreground/live. Diagnostic counters are persisted by update mode and reset together after 24 hours.

### Miataru API Access

The local `MiataruAPIClient` package exposes typed protocol calls. App code uses `MiataruAppAPI` wrappers for centralized retry behavior, cache ingestion, DeviceKey handling, and app-level side effects.

Transient network and server failures are classified by `MiataruRetryClassifier`. Reads, writes, and `updateLocation` each retry once with short jittered backoff. Uncertain `updateLocation` failures, including decoding errors and invalid responses without clear 401/403 auth context, are persisted in `LocationUpdateOutboxStore` and drained by `LocationUpdateDeliveryCoordinator` without rewriting original event metadata.

### Device Identity, DeviceKey, and Access Control

`thisDeviceIDManager` owns current-device identity and legacy migration. DeviceKey flows allow create, restore, reset, recovery, and emergency identity reset. DeviceKey protects update writes, visitor history, device slogans, security status, and allowed-device-list access where the server supports it.

Allowed Device List behavior is integrated into add/edit/delete flows and uses immediate sync from edit screens. Unknown visitors can be allowed, ignored, or surfaced through opt-in notifications.

### Devices, Groups, and Caches

`KnownDeviceStore` and `DeviceGroupStore` persist user-managed devices and groups under Application Support. `DeviceLocationCacheStore`, `DeviceHistoryCacheStore`, and `DeviceSloganCacheStore` provide current location, history, reverse-geocode, recent-visitor, and slogan data.

Successful server responses are centrally ingested so device rows, maps, navigation, visitor flows, and widgets share the same freshness rules. Startup and device-list cleanup prune stale unknown-device locations, slogans, and legacy widget snapshots.

### Widgets

The widget extension contains text and map widgets. Device selection is AppIntent-based and reads `WidgetDeviceSelectionData` so every known device remains selectable even if no widget location snapshot exists yet. The app and widget exchange JSON payloads, configuration, and map snapshots through the `group.com.miataru.ios` App Group.

Widgets can use cached app data and, when configured, live server fetches via shared server URL, known device IDs, own device ID, and own DeviceKey.

### App Intents, Siri, and Shortcuts

The first App Intents layer prepares configured Miataru devices as user-friendly `TrackedPersonEntity` values. Queries are backed by `KnownDeviceStore` through `IntentLocationService` and only return records with a non-empty DeviceID and current-location access. The shipping shortcut parameters currently use `TrackedPersonOptionsProvider` dynamic string options because Shortcuts can fail to serialize dynamic `AppEntity` selections with "not a registered AppEntity identifier" runtime errors.

`FindPersonLocationIntent` fetches the latest server location on demand through `MiataruAppAPI.getLocation`, reuses cached placemark context from `DeviceLocationCacheStore`, and returns privacy-friendly dialog text. `OpenRouteToPersonIntent` fetches the same latest location and opens Apple Maps with a destination coordinate. Dialogs and route URLs avoid DeviceKeys, raw DeviceIDs, and full API responses.

The prepared snippet view is not currently wired to `ShowsSnippetView` because the locally available AppIntents API marks that protocol as iOS 26+. Place entities and the "is person near place" shortcut are deferred until a real persisted places source exists.

### Maps and Navigation

Shared map components live in `views/Common/Map`. Device and group maps reuse marker rendering, accuracy circles, compass, scale bar, off-screen arrows, route style, and speed/relative-time helpers.

The iPhone device history map keeps the existing MapKit route, point annotation, range selection, scrubber, and playback model, and extends the bottom timeline panel with compact speed and altitude analysis. `HistoryAnalyzer` maps `MiataruLocationData` into neutral samples, filters invalid speed/accuracy data, derives speed where possible, and produces time buckets for a speed histogram and altitude sparkline. `DeviceHistoryMapViewModel` prepares and caches analysis sources, per-range analysis results, visible-history counts, downsampled annotations, and polyline segments so 10,000-point histories do not rebuild full map or graph data on each scrub or panel-state update. The panel can be hidden with a downward swipe on its handle and restored from a bottom pill without interrupting playback.

`iPhone_DeviceNavigationView` coordinates `MKRoute`, `RouteCacheStore`, `NavigationRouteRefreshPolicy`, route overlays, ETA updates, focused navigation, and `NavigationOverlayKit` instructions. Standard `device -> user` navigation can show a route-progress ghost; focused double-tap navigation deliberately keeps only the base route and optional mutual-navigation overlay.

### Notifications

`UnknownVisitorAlertService` evaluates visitor history incrementally from activation time, filters own/known/ignored IDs, applies a per-device cooldown, enriches true unknown candidates with cached or batched `GetLocation` data, and schedules local notifications.

`FrequentBackgroundTrackingReminderService` manages reminder, expiry, low-battery auto-disable, and optional Smart frequent mode-change notifications for frequent background tracking. Smart activation/deactivation notifications default to off, request notification permission before the setting is enabled, and are sent only when Smart itself turns frequent runtime on or off.

## Platform Layout

- iPhone: Devices, QR, Settings tabs; groups live inside the Devices flow.
- iPad: Devices, Groups, QR, Settings tabs; split views and separate device windows are supported.
- Mac: source files exist for preview/scaffolding only; no active Mac product target.

## Testing

Active app tests are split into:

- `miataruTests` for unit tests
- `miataruUITests` for deterministic functional UI tests
- `miataruScreenshotUITests` for explicit screenshot capture

Shared schemes and scripts:

- `miataru-FunctionalUI` / `FunctionalSerial.xctestplan` / `scripts/test-functional-ui-serial.sh`
- `miataru-Screenshots` / `Screenshots.xctestplan` / `scripts/test-screenshots.sh`
- `scripts/test-unit.sh`, `scripts/test-ui.sh`, and `scripts/test-all.sh`

The current catalog and remaining gaps are maintained in `documentation/test-katalog.md` and `documentation/test-gap-matrix.md`.

## Dependencies

- Local packages: `Libraries/CodeScanner-main`, `Libraries/QRCode-main`, `Libraries/MiataruClientSwift`
- Remote SwiftPM packages: `NavigationOverlayKit`, `swift-qrcode-generator`, `SwiftImageReadWrite`

`Package.resolved` pins `NavigationOverlayKit` 1.1.0, `swift-qrcode-generator` 2.0.2, and `SwiftImageReadWrite` 1.9.2.

## Development Priorities

Recent 2026 work focused on:

- DeviceKey, allowed-device list, device slogans, and security status
- visitor history, unknown visitor alerts, and recent-visitor indicators
- robust navigation, focused camera behavior, route-progress ghost rendering, and route request limits
- compact device history speed/altitude analytics, hideable history controls, and 10,000-point history performance caching
- Smart/manual background tracking controls, retry/outbox resilience, and persistent cleanup
- widgets and App Group data synchronization
- App Intents for Siri and Shortcuts around existing known-device/location services
- localization coverage across all supported languages
- active unit/UI/screenshot test infrastructure

The current highest-value test gaps are integration coverage for the location/routing pipeline, unknown-visitor trigger wiring, allowed-device sync, persistence-store error paths, and widget payload contracts.
