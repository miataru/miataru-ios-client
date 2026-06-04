# miataru iOS App

**miataru** is an open-source iPhone and iPad app for privacy-focused location sharing, device management, and navigation through Miataru servers chosen by the user.

Current project state: **version 3.2**, iOS deployment target **18.6**, SwiftUI app target plus WidgetKit extension, localized for **da, de, en, es, fi, fr, it, ja, nl, and zh-Hans**.

## Overview

miataru lets users publish their own device location, follow trusted devices, organize devices into groups, share device IDs through QR codes and deep links, and navigate to another device. The app keeps user control at the center: users pick the server, decide whether history is stored, optionally protect server-side operations with a DeviceKey, and can enable an allowed-device list for stricter access control.

The app currently supports iPhone and iPad. Mac-specific view files are present only as preview/scaffolding code; there is no shipping Mac target in the project.

## Core Features

- Location sharing: foreground high-accuracy updates, a battery-saving standard background mode, Smart frequent background updates, and a manual frequent override mode.
- Smart frequent background mode: optional two-stage policy that normally waits in the battery-saving standard mode, temporarily starts frequent background updates after movement above a configurable speed threshold, and returns to standard mode after a shared inactivity window.
- Manual frequent background mode: configurable distance filter, duration, delivery delay, visitor-history check interval, reminder/expiration notifications, optional Smart mode-change notifications with notification-permission gating, and low-battery auto-disable.
- Offline resilience: `updateLocation` calls retry transient failures and then persist to a FIFO outbox with configurable retention and capacity.
- DeviceKey: create, restore, reset, and recover server-side authentication for location writes, visitor history, slogans, and access-control settings.
- Allowed Device List: manage device access controls and sync changes immediately from edit flows.
- Unknown visitor alerts: optional local notifications for new unknown devices that look up this device, filtered against own, known, allowed, and ignored IDs.
- Device info: display and edit short device slogans, show security status, and cache location/slogan metadata centrally.
- Maps and navigation: device/group maps, accuracy circles, off-screen arrows, route planning, live ETA, route-progress ghost rendering in standard navigation, focused double-tap navigation, turn-by-turn overlay, haptics, and sound cues.
- QR and deep links: show the current device QR code, scan Miataru URLs, share IDs, and open `miataru://<DEVICE_ID>` links.
- Widgets: text and map widgets use AppIntent device selection, shared App Group configuration, cached map snapshots, and live fallback fetches where configured.
- Tests: unit, functional UI, and screenshot suites are split into dedicated schemes and scripts.

## Architecture

```text
miataru/
├── miataruApp.swift                 # App entry, global state, deep links, lifecycle
├── views/
│   ├── Common/                      # Shared UI, map components, route helpers
│   ├── iPhone/                      # iPhone tabs, devices, QR, settings, onboarding
│   ├── iPad/                        # iPad split views, groups, device windows
│   └── Mac/                         # Preview/scaffolding only
├── LocationManagers/                # LocationManager, DeviceLocationRefresher, RouteCacheStore
├── Networking/                      # MiataruAppAPI, retry policy, request executor, update outbox
├── Notifications/                   # Unknown visitor alerts, frequent-background reminders
├── SettingsManagers/                # Settings, device/group stores, caches, widget sync, cleanup
├── Assets/                          # String catalogs, icons, onboarding assets, sounds
├── miataruWidgets/                  # WidgetKit extension sources
├── miataruTests/                    # Unit tests
├── miataruUITests/                  # Functional UI tests
└── miataruScreenshotUITests/        # Screenshot capture UI tests
```

## Data Flow

Location updates are coordinated by `LocationManager`. Direct sends use `MiataruAppAPI.updateLocation`; transient failures are retried and then queued by `LocationUpdateDeliveryCoordinator` / `LocationUpdateOutboxStore`. Queued updates retain their original event payload and are flushed on app activation, network recovery, periodic timer, manual flush, delayed frequent-background delivery, or server-URL retargeting.

Successful `GetLocation` and `GetLocationHistory` responses are centrally ingested into `DeviceLocationCacheStore`, `DeviceSloganCacheStore`, recent-visitor state, and widget payloads. This avoids per-view cache drift and preserves newer samples when data is written by the widget extension.

App-owned persistent data lives under Application Support and the shared App Group. `PersistentDataCleanup` prunes orphaned unknown-device location/slogan cache entries and stale widget snapshots on startup and after relevant device-list changes.

## User Flows

### Onboarding

Full onboarding includes the base welcome, permission, server, QR, and done pages. When tracking is enabled, additional pages are inserted for history, unknown visitor alerts, DeviceKey setup, and allowed-device-list setup. Existing users with tracking enabled can see a shorter post-update flow focused on DeviceKey setup.

The Location Tracking Details screen can restart the full authorization flow, including the `When In Use -> Always` escalation when iOS still allows it.

### Devices and Groups

iPhone uses Devices, QR, and Settings tabs, with groups integrated into the Devices flow. iPad uses Devices, Groups, QR, and Settings tabs with split navigation and device detail windows. Device rows show known metadata such as last update, distance, battery, altitude, speed, approximate place, slogan, and recent-visitor status when available.

### Navigation

Navigation supports walking, car, and transit routes. Standard `device -> user` navigation can show progress segmentation and a moving route ghost after enough progress. Reverse `user -> device` navigation uses focused camera behavior and turn-by-turn instructions. Focused double-tap mode intentionally keeps the base route stable and suppresses ghost/progress segmentation.

Live speed labels on map markers are hidden once their location sample is older than five minutes; historical speed displays remain independent of that freshness rule.

### Settings

Root settings cover the most common tracking, DeviceKey, privacy, app behavior, map, navigation, and server options. Advanced Options contain high-detail controls for Smart frequent and manual frequent background updates, tracking accuracy/sensitivity, map refresh intervals, reverse geocoding, route progress, route auto-update, marker animation, outbox retention, and outbox capacity. When manual frequent background updates are currently active, the Smart frequent toggle is locked with explanatory copy because manual mode is the effective override.

## Development

Open `miataru/miataru.xcodeproj` in Xcode. The app target currently uses:

- Xcode 16+
- iOS 18.6 deployment target
- Swift language version 5.0 in project settings
- Target device family: iPhone and iPad
- App Group: `group.com.miataru.ios`

Useful scripts:

```bash
cd miataru
./scripts/test-unit.sh
./scripts/test-functional-ui-serial.sh
./scripts/test-screenshots.sh --languages en --device "iPhone 16 Pro Max"
./scripts/test-all.sh
```

See `miataru/DEVELOPMENT.md`, `documentation/test-katalog.md`, `documentation/test-gap-matrix.md`, and `documentation/screenshot-test-workflow.md` for the detailed workflow.

## Dependencies

- `CodeScanner`: QR code scanning
- `QRCode` and `swift-qrcode-generator`: QR code generation
- `MiataruAPIClient`: local Swift package for Miataru API payloads and requests
- `SwiftImageReadWrite`: image utilities
- `NavigationOverlayKit`: route instruction overlay

Third-party license notes are tracked in `3rd party licenses.md`.

## Privacy and Security

- The app talks to the Miataru server configured by the user.
- DeviceKey protects server-side writes and sensitive reads when configured.
- Allowed Device List can restrict which devices may access this device.
- Unknown visitor alerts are opt-in and start from activation time, avoiding retroactive notifications.
- Local caches are app-owned and pruned; widget data is shared only through the configured App Group.
- No analytics or third-party tracking SDK is part of the app codebase.

## Documentation

The living documentation is maintained in this README, `miataru/PROJECT_OVERVIEW.md`, `miataru/APP_FEATURES.md`, `miataru/DEVELOPMENT.md`, and the test documentation under `documentation/`. Dated implementation notes in `documentation/` and `miataru/documentation/` are retained as historical design records.

## License

This project is licensed under the 2-clause BSD License. See `LICENSE` for details.

**miataru** - Your location, your rules.
