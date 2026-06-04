# Development Guide - miataru iOS App

## Quick Start

### Prerequisites

- Xcode 16+
- iOS 18.6 device or simulator
- macOS 14+ development host
- Swift language version 5.0 in project settings

### Setup

1. Clone the repository.
2. Open `miataru/miataru.xcodeproj` in Xcode.
3. Select a development team if signing needs to be changed locally.
4. Build and run the `miataru` scheme on an iPhone or iPad simulator/device.

The current main app metadata is version **3.2**. The project targets iPhone and iPad; Mac files are preview/scaffolding only.

## Project Structure

```text
miataru/
├── miataruApp.swift                 # App entry, lifecycle, deep links, test launch state
├── views/
│   ├── Common/                      # Shared UI, map components, route helpers
│   ├── iPhone/                      # iPhone tabs and flows
│   ├── iPad/                        # iPad tabs, split views, device windows
│   └── Mac/                         # Preview/scaffolding only
├── LocationManagers/                # Tracking, refresh, route cache
├── Networking/                      # API wrappers, retry, outbox
├── Notifications/                   # Unknown visitor and frequent-background notifications
├── SettingsManagers/                # Settings, stores, caches, widget sync, cleanup
├── Assets/                          # String catalogs, sounds, icons, onboarding assets
├── miataruWidgets/                  # WidgetKit extension
├── miataruTests/                    # Unit tests
├── miataruUITests/                  # Functional UI tests
└── miataruScreenshotUITests/        # Screenshot UI tests
```

## Core Components

### App Bootstrap

- `miataruApp` applies UI-test launch configuration, settings migration, settings default registration, widget import/sync, persistent cleanup, app lifecycle tracking, deep links, and device detail windows.
- `AppState` controls full and post-update onboarding.
- `AppDelegate` manages notification presentation and routes frequent-background reminder, expiration, low-battery, and Smart mode-change notification taps to Advanced Options.
- Rotation lock is controlled by `RotationLockController` and the `prevent_screen_rotation` setting.

### Settings

- `SettingsManager` owns runtime preferences and side effects.
- `SettingsConfiguration` / `SettingsDefaultValues` centralize defaults, normalization, and one-time existing-install migrations.
- Defaults are registered from `Settings.bundle/Root.plist`.
- Settings parity with `Settings.bundle` and localization catalogs is covered by unit tests.

### Location Tracking

- `LocationManager` resolves tracking mode centrally:
  - stopped
  - foreground high accuracy
  - background significant-change monitoring
  - frequent background updates
- Smart frequent background updates are a policy layer over the background resolver: Smart waits in significant-change mode, starts frequent runtime only after movement above the configured speed threshold, and stops runtime after the shared inactivity window.
- Manual frequent background mode is still available as the Stage 2 override after Smart frequent updates are enabled. Manual mode ignores Smart activation/deactivation criteria and uses its configured duration.
- Frequent background settings include Smart speed threshold/detection/inactivity, optional Smart mode-change notifications, manual distance/duration, delivery delay, visitor-check cadence, reminder/expiry notifications, and low-battery auto-disable.
- Existing installs with manual frequent mode enabled are normalized/migrated so the Smart prerequisite is also enabled.
- Navigation views call `beginNavigationLocationSession()` / `endNavigationLocationSession(_:)` so focused navigation gets immediate local location updates without bypassing lifecycle background policy.
- `latestRawLocation` exists for UI that needs immediate local movement; `currentLocation` remains sensitivity-filtered.

### API and Retry

- `MiataruAPIClient` is the local Swift package that encodes/decodes Miataru API requests.
- `MiataruAppAPI` is the app-facing wrapper. Use it for app target calls so retry behavior, DeviceKey handling, counters, and cache ingestion remain centralized.
- `MiataruRetryPolicy` retries reads, writes, and `updateLocation` once with short jittered backoff.
- Retryable failures: transient `URLError` values, HTTP `408`, `429`, and `5xx`.
- Non-retryable failures: invalid URL, encoding/decoding errors, auth/ACL failures, and other functional `4xx`.

### Location Update Outbox

- `LocationUpdateDeliveryCoordinator` serializes `updateLocation` delivery.
- `LocationUpdateOutboxStore` persists queued payloads in Application Support.
- Defaults: max 500 items, TTL 24 hours.
- User-configurable policy: 24h, 7d, 30d, unlimited; max 500, 1000, 2500, 5000, 10000.
- Dedupe key: `Device+Timestamp+Latitude+Longitude`.
- Queued payloads preserve original event timestamp and metadata.
- Flush triggers: app activation, network recovery, submit behind pending queue, periodic timer, delayed frequent-background release, manual flush, and server URL retargeting.
- If server URL changes while items are pending, Settings asks whether to retarget pending items or discard them.

### Caches and Cleanup

- `DeviceLocationCacheStore` owns latest device locations, reverse geocoding, history promotion, recent visitors, and timestamp-ordering.
- `DeviceSloganCacheStore` owns slogan cache/freshness and cleanup.
- `WidgetDataSyncCoordinator` writes App Group payload/config and imports newer widget-written locations into the app cache.
- `PersistentDataCleanup` removes stale unknown-device location/slogan cache entries and stale widget snapshots.

### Widgets

- Widget target sources live in `miataruWidgets/`.
- Text and map widgets use `AppIntentConfiguration` with `DeviceSelectionIntent`.
- Shared App Group: `group.com.miataru.ios`.
- Main app writes `WidgetSharedPayload` and `SharedWidgetConfig`.
- Widget selections are separate from cached location entries so devices remain selectable before first widget location data exists.
- Map snapshots are stored under `Library/Caches/WidgetSnapshots` in the App Group container.
- Widget extension calls the API client directly and intentionally does not use the app retry/outbox actor.

### Unknown Visitor Alerts

- `UnknownVisitorAlertService` is an actor that processes current-device visitor history after successful location delivery.
- It starts at enable time, filters own/known/ignored devices, applies a 24-hour per-device cooldown, and coalesces in-flight runs.
- Supplemental notification details are best-effort and only fetched for true unknown candidates.
- `UnknownVisitorFilter` keeps unknown visitor list filtering shared between iPhone and iPad.

### Navigation

- `NavigationRouteRefreshPolicy` centralizes route refresh decisions.
- `RouteCacheStore` caches `MKRoute` values by device, transport, and direction with endpoint/off-route validation.
- `RouteGhostCalculator` computes progress and route splits using polyline geometry.
- `RouteGhostPresentationPolicy` controls ghost visibility with fresh route seed time.
- Focused double-tap navigation intentionally suppresses route-progress ghost/segmentation and periodically re-establishes the base overlay without extra `MKDirections` calls.
- `NavigationOverlayKit` renders turn-by-turn instruction UI when routing from current device to target device.

## Testing

### Scripts

```bash
cd miataru
./scripts/test-unit.sh
./scripts/test-ui.sh
./scripts/test-functional-ui-serial.sh
./scripts/test-screenshots.sh --list
./scripts/test-screenshots.sh --test root-qr --device "iPhone 16 Pro Max" --languages en
./scripts/test-all.sh
```

### Schemes and Plans

- `miataru-FunctionalUI` uses `FunctionalSerial.xctestplan` for unit + functional UI tests.
- `miataru-Screenshots` uses `Screenshots.xctestplan` for explicit screenshot captures.
- Screenshot output goes to `miataru/artifacts/screenshots/<version-build-tag>/`.

### Test Documentation Rule

Whenever tests are added, removed, renamed, moved, or materially changed:

1. Update `documentation/test-katalog.md`.
2. Update `documentation/test-gap-matrix.md`.
3. Keep counters, coverage notes, and prioritized gaps consistent.

## Development Workflow

- Keep UI logic thin and move business behavior into managers, actors, stores, and helpers.
- Use `SettingsManager` for user preferences and side effects.
- Use `MiataruAppAPI` for app API calls.
- Use cache/store APIs instead of ad hoc file or `UserDefaults` access.
- Add localization strings for every supported locale.
- Preserve iPhone/iPad product differences intentionally; do not assume both roots should be identical.
- Update living docs when behavior changes.

## Debugging

- Deep link test:

```bash
xcrun simctl openurl booted miataru://ABCDEF
```

- Use Xcode location simulation to test tracking and navigation.
- Use Console.app and Xcode logs for location permission and background-mode issues.
- Watch Location Tracking Details for daily API counters, route requests, queued updates, and server status.
- For server URL changes with pending outbox items, verify the confirmation dialog and retarget/discard behavior.
- For screenshot issues, inspect `miataru/artifacts/xcresult/`.

## Troubleshooting

### Location not updating

- Confirm `track_and_report_location` is enabled.
- Confirm iOS permission state in Location Tracking Details.
- Use "Request Location Permission Again" if the user selected a limited permission path.
- Check DeviceKey auth banner if writes are blocked by server authentication.

### Background updates not frequent enough

- Standard background mode uses significant-change monitoring by design.
- Enable Smart frequent updates when the app should automatically switch to frequent runtime only after detected movement.
- Enable manual frequent background updates only when the higher battery cost is acceptable and Smart criteria should be bypassed.
- Check Smart threshold/detection mode, Smart inactivity window, manual expiration duration, low-battery threshold, and whether the app returned to standard background mode.
- Location Tracking Details shows the current background mode, Smart activation reason, last relevant Smart movement, next inactivity timeout, and mode-specific update counters.

### Queued location updates remain pending

- Check network availability.
- Check server URL validity.
- Use the manual flush button if more than one update is queued.
- Retryable head errors intentionally stop a flush cycle to preserve FIFO ordering.

### Unexpected "encoding" errors

- `MiataruAPIClient.performPostRequest<T: Encodable>` should rethrow existing `APIError` values unchanged.
- Encoding failures are technical diagnostics and should not be shown as large user-facing map/history overlays unless actionable.

### Widget displays the wrong device

- Verify `DeviceSelectionIntent` uses the selected AppIntent entity ID.
- Verify `WidgetSharedPayload.deviceSelections` includes all known devices.
- Verify app/widget payloads are written into the same App Group container.
- Check that stale root-level map snapshots were cleaned up and current snapshots are in `Library/Caches/WidgetSnapshots`.

## Dependencies

- `CodeScanner`: QR scanning
- `QRCode` and `swift-qrcode-generator`: QR generation
- `MiataruAPIClient`: Miataru protocol client
- `SwiftImageReadWrite`: image utilities
- `NavigationOverlayKit`: turn-by-turn navigation overlay

Third-party license details are tracked in `../3rd party licenses.md`.

## Resources

- `README.md`: project-level overview
- `miataru/PROJECT_OVERVIEW.md`: architecture overview
- `miataru/APP_FEATURES.md`: user/developer feature guide
- `documentation/README.md`: documentation map and audit scope
- `documentation/test-katalog.md`: active test catalog
- `documentation/test-gap-matrix.md`: prioritized test gaps
- `documentation/screenshot-test-workflow.md`: screenshot capture workflow
