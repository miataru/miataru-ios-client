# miataru iOS App - Project Overview

## Current State

miataru is a privacy-focused iPhone and iPad app for location sharing through user-selected Miataru servers. The current app metadata is **3.1.14** with an iOS deployment target of **18.6**. The app target is SwiftUI-based, includes a WidgetKit extension, and is localized for ten app locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, and `zh-Hans`.

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

`LocationManager` owns permission state, local GPS updates, heading updates, tracking mode resolution, background behavior, and upload status. It resolves one of four modes:

- stopped
- foreground high accuracy
- background significant-change monitoring
- frequent background updates with configured distance/accuracy

Foreground tracking uses high accuracy. Background tracking defaults to significant-change monitoring unless the user opts into frequent background updates. Frequent background mode is bounded by user-configured distance, duration, delivery delay, visitor-check interval, reminder/expiration notifications, and low-battery auto-disable.

### Miataru API Access

The local `MiataruAPIClient` package exposes typed protocol calls. App code uses `MiataruAppAPI` wrappers for centralized retry behavior, cache ingestion, DeviceKey handling, and app-level side effects.

Transient network and server failures are classified by `MiataruRetryClassifier`. Reads, writes, and `updateLocation` each retry once with short jittered backoff. Failed `updateLocation` payloads are persisted in `LocationUpdateOutboxStore` and drained by `LocationUpdateDeliveryCoordinator` without rewriting original event metadata.

### Device Identity, DeviceKey, and Access Control

`thisDeviceIDManager` owns current-device identity and legacy migration. DeviceKey flows allow create, restore, reset, recovery, and emergency identity reset. DeviceKey protects update writes, visitor history, device slogans, security status, and allowed-device-list access where the server supports it.

Allowed Device List behavior is integrated into add/edit/delete flows and uses immediate sync from edit screens. Unknown visitors can be allowed, ignored, or surfaced through opt-in notifications.

### Devices, Groups, and Caches

`KnownDeviceStore` and `DeviceGroupStore` persist user-managed devices and groups under Application Support. `DeviceLocationCacheStore`, `DeviceHistoryCacheStore`, and `DeviceSloganCacheStore` provide current location, history, reverse-geocode, recent-visitor, and slogan data.

Successful server responses are centrally ingested so device rows, maps, navigation, visitor flows, and widgets share the same freshness rules. Startup and device-list cleanup prune stale unknown-device locations, slogans, and legacy widget snapshots.

### Widgets

The widget extension contains text and map widgets. Device selection is AppIntent-based and reads `WidgetDeviceSelectionData` so every known device remains selectable even if no widget location snapshot exists yet. The app and widget exchange JSON payloads, configuration, and map snapshots through the `group.com.miataru.ios` App Group.

Widgets can use cached app data and, when configured, live server fetches via shared server URL, known device IDs, own device ID, and own DeviceKey.

### Maps and Navigation

Shared map components live in `views/Common/Map`. Device and group maps reuse marker rendering, accuracy circles, compass, scale bar, off-screen arrows, route style, and speed/relative-time helpers.

`iPhone_DeviceNavigationView` coordinates `MKRoute`, `RouteCacheStore`, `NavigationRouteRefreshPolicy`, route overlays, ETA updates, focused navigation, and `NavigationOverlayKit` instructions. Standard `device -> user` navigation can show a route-progress ghost; focused double-tap navigation deliberately keeps only the base route and optional mutual-navigation overlay.

### Notifications

`UnknownVisitorAlertService` evaluates visitor history incrementally from activation time, filters own/known/ignored IDs, applies a per-device cooldown, enriches true unknown candidates with cached or batched `GetLocation` data, and schedules local notifications.

`FrequentBackgroundTrackingReminderService` manages reminder, expiry, and low-battery auto-disable notifications for frequent background tracking.

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
- background tracking controls, retry/outbox resilience, and persistent cleanup
- widgets and App Group data synchronization
- localization coverage across all supported languages
- active unit/UI/screenshot test infrastructure

The current highest-value test gaps are integration coverage for the location/routing pipeline, unknown-visitor trigger wiring, allowed-device sync, persistence-store error paths, and widget payload contracts.
