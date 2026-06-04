# miataru App - Feature and Developer Guide

This document describes the current user-facing and developer-facing feature set of the miataru iOS app as of version **3.2**.

## App Navigation and Views

**For users:**

- iPhone uses three tabs: **Devices**, **QR**, and **Settings**. Group management is embedded inside Devices.
- iPad uses **Devices**, **Groups**, **QR**, and **Settings** tabs with split navigation.
- Device and group rows open map views; device map screens can start navigation, open history, edit devices, or recenter the map.
- On iPad, device details can open in separate windows for multitasking.

**For developers:**

- `MiataruRootView` selects `iPhone_RootView` for compact width and `iPad_RootView` for regular width.
- `iPhone_RootView` owns the compact tab layout; `iPad_RootView` owns the iPad tab layout and split-view entry points.
- `DeviceWindowEntrypoint` supports value-based iPad device windows via `WindowGroup(for: String)`.
- Mac view files are preview/scaffolding only; the shipping product target is iPhone/iPad.

## Location Tracking

**For users:**

- Location sharing is opt-in and controlled from Settings.
- Foreground tracking uses high accuracy. Background tracking defaults to energy-conscious significant-change updates.
- Smart frequent background updates are optional and normally keep the battery-friendly significant-change mode active until movement above a configurable speed threshold is detected.
- Manual frequent background updates remain available as a second stage after Smart frequent updates are enabled. Manual mode overrides Smart and exposes configurable distance, duration, delivery delay, visitor-history check interval, reminders, expiration notifications, and low-battery auto-disable.
- Smart frequent updates can optionally send notifications when the app automatically switches frequent runtime on or back to standard background mode. These notifications are off by default.
- The app reports available altitude, speed, horizontal accuracy, and battery level with location updates.
- Location Tracking Details shows app version/build, permission state, current location, accuracy, speed, battery, daily API/widget counters, route requests, queued updates, background mode, Smart diagnostics, mode-specific location-update counters, and recent update logs.
- Users can request location permission again from Location Tracking Details.

**For developers:**

- `LocationManager` resolves service-level tracking mode centrally (`stopped`, `foregroundHighAccuracy`, `backgroundSignificantChange`, `backgroundFrequent`) and separately exposes user-facing background states (`significant-change`, `Smart waiting`, `Smart frequent active`, `manual frequent active`, `foreground/live`).
- Smart frequent settings are represented by `SmartFrequentBackgroundSpeedThreshold`, `SmartFrequentBackgroundSpeedDetectionMode`, `SmartFrequentBackgroundInactivityWindow`, and the opt-in Smart mode-change notification flag in `SettingsManager`.
- Manual frequent settings are represented by `FrequentBackgroundLocationDistanceFilter`, `FrequentBackgroundLocationUpdateDuration`, `FrequentBackgroundLocationDeliveryMode`, `FrequentBackgroundVisitorCheckInterval`, and low-battery threshold values in `SettingsManager`.
- Existing manual frequent users are migrated so the Smart prerequisite is enabled while preserving manual frequent mode as the effective override.
- Navigation views register explicit navigation location sessions so active navigation keeps high-quality local updates while lifecycle transitions still apply the correct background policy.
- Visual effects are gated by Low Power Mode and scene phase through `animationsGate()`.

## Offline Delivery and Retry

**For users:**

- Temporary network failures do not immediately lose location updates. Failed sends are queued locally and retried later.
- The Location Tracking Details page shows queued update count and can manually flush a larger queue.
- If the Miataru server URL changes while updates are queued, users choose whether to send queued updates to the new server or discard them.

**For developers:**

- `MiataruAppAPI` wraps the local `MiataruAPIClient` with app-level retry and cache-ingest behavior.
- `MiataruRetryPolicy` retries reads, writes, and `updateLocation` once with jittered backoff.
- `LocationUpdateOutboxStore` persists FIFO `updateLocation` payloads in Application Support with dedupe by `Device+Timestamp+Latitude+Longitude`.
- `LocationUpdateDeliveryCoordinator` drains the outbox on app activation, network recovery, deferred submit, delayed frequent-background release, periodic timer, server URL retargeting, and manual flush.
- The widget extension intentionally keeps direct client calls without the app retry/outbox layer.

## Device Management

**For users:**

- Maintain a list of devices with name, ID, and optional color.
- Add devices by scanning Miataru QR codes, opening `miataru://<DEVICE_ID>` links, or entering an ID manually.
- Device rows can show last update, distance, battery, altitude, speed, approximate place, slogan, and recent-visitor indicators.
- Pull-to-refresh updates visible device data and keeps existing cache values visible through transient network failures.
- Deleting a device also updates access-control and cache/widget state where relevant.

**For developers:**

- `KnownDeviceStore` persists devices under Application Support and keeps the current device available.
- Device-list refreshes use consolidated cache snapshots instead of per-row partial updates.
- `DeviceLocationCacheStore` timestamp-ordering prevents older app, history, widget, or background responses from overwriting newer data.
- `DeviceSloganCacheStore` handles slogan fetch/cache/cleanup; `MiataruAppAPI` sanitizes slogan draft/save input.
- `PersistentDataCleanup` prunes orphaned unknown-device locations, slogans, and widget snapshots.

## DeviceKey, Access Control, Unknown Visitors, and Notifications

**For users:**

- DeviceKey can be created, restored, reset, and recovered from onboarding, the current-device screen, and Settings.
- DeviceKey-protected flows cover location updates, visitor history, device slogans, security status, and allowed-device-list operations when the server enforces them.
- Allowed Device List can restrict which devices are allowed to access this device.
- Unknown visitors can be allowed, ignored, or surfaced through optional local notifications.
- Unknown visitor notifications start from activation time and are filtered so own, known, allowed, and ignored devices do not create alerts.
- Frequent background tracking uses local notifications for manual never-ending reminders, temporary-mode expiration, low-battery auto-disable, and optional Smart frequent auto-switch events.

**For developers:**

- `DeviceKeyAuthHandler` coordinates runtime auth-block handling and recovery/reset notifications.
- `AllowedDeviceListManager` performs access-control sync through `MiataruAppAPI`.
- `UnknownVisitorFilter` normalizes the shared unknown visitor filtering logic for iPhone and iPad lists.
- `UnknownVisitorAlertService` evaluates visitor history incrementally, applies 24-hour per-device cooldown, coalesces in-flight processing, and batches supplemental `GetLocation` enrichment for true unknown candidates.
- `FrequentBackgroundTrackingReminderService` owns frequent-background reminder, expiration, low-battery, and Smart mode-change notifications. AppDelegate routes all frequent-background notification types to Advanced Options.

## Group Management

**For users:**

- Create named groups, assign devices, reorder groups, and view group maps.
- iPhone keeps group access inside the Devices flow.
- iPad keeps a dedicated Groups tab with split navigation.

**For developers:**

- `DeviceGroup` and `DeviceGroupStore` persist group membership.
- iPhone group editing uses `iPhone_GroupDetailView` and `GroupEditSheetContainer`.
- iPad group editing uses `iPad_GroupsView` and `iPad_GroupDetailView`.
- Group maps share marker, off-screen-arrow, navigation, and history behavior with device maps.

## Map Views and Navigation

**For users:**

- Maps show device markers, accuracy circles, relative time, distance, and optional speed labels.
- Live speed labels disappear when the backing location sample is older than five minutes.
- Off-screen arrows point toward devices outside the current region.
- Navigation can show route, ETA, distance, arrival time, route progress, turn-by-turn instructions, haptics, and sound cues.
- Standard `device -> user` navigation can show completed/remaining route segments plus a moving ghost marker.
- Focused double-tap navigation keeps a stable base route and intentionally disables ghost/progress segmentation.

**For developers:**

- Shared map components live in `views/Common/Map`.
- `RouteCacheStore` caches routes by device, transport, and direction with endpoint and off-route validation.
- `NavigationRouteRefreshPolicy` centralizes reroute decisions.
- `RouteGhostCalculator` uses direction-specific timestamp/speed sources and polyline geometry for route-progress splitting.
- `RouteGhostPresentationPolicy` keeps cached-route ghost visibility based on the current route seed time.
- `iPhone_DeviceNavigationView` serializes auto-update work and ignores stale `MKDirections` responses after newer route work starts.
- `NavigationOverlayKit` provides turn-by-turn instruction UI for current-device-to-target routing.

## QR Code Sharing and Visitor History

**For users:**

- The QR tab displays this device's QR code, share actions, DeviceKey access, and visitor history.
- Visitor history refreshes when the current-device tab opens and also during foreground auto-refresh cycles.
- Unknown devices from visitor history can be added or ignored.

**For developers:**

- `iPhone_MyDeviceQRCodeView` renders QR codes using `QRCode` and supports `ShareLink` / mail sharing.
- `VisitorHistoryViewModel` and shared visitor sections power both the QR tab and the standalone visitor history view.
- Visitor-history loads ingest recent visitor state into `DeviceLocationCacheStore` when the request is for the current device.

## Widgets

**For users:**

- miataru includes text and map widgets for selected devices.
- Widgets can be configured per device and keep every known device selectable, even before a cached widget location exists.
- Widget maps use cached light/dark snapshots and update from shared app data or configured live fetches.

**For developers:**

- `miataruWidgets` contains `DeviceLocationTextWidget`, `DeviceLocationMapWidget`, AppIntent configuration, shared config/data models, and widget-side snapshot generation.
- The app writes `WidgetSharedPayload` and `SharedWidgetConfig` through the `group.com.miataru.ios` App Group.
- `WidgetDataSyncCoordinator` preserves newer widget-written locations during app sync and imports newer widget locations into the app cache on startup/foreground activation.
- Widget map snapshots are stored under the App Group `Library/Caches/WidgetSnapshots` directory.

## Onboarding Flow

**For users:**

- Full onboarding always includes welcome, permission, server, QR, and completion pages.
- When tracking is enabled, additional pages appear for location history, unknown visitor alerts, DeviceKey, and allowed-device-list setup.
- Existing users with tracking enabled can see a shorter post-update flow focused on DeviceKey setup.

**For developers:**

- `OnboardingContainerView` selects iPhone or iPad onboarding by size class.
- `iPhone_OnboardingContainerView` composes optional pages based on `SettingsManager.shared.trackAndReportLocation`.
- Successful DeviceKey setup sheets close automatically in onboarding after the success state is visible.

## Settings and Configuration

**For users:**

- Root settings cover tracking/history, unknown visitor alerts, DeviceKey, Smart/manual frequent background access, allowed-device-list entry, app behavior, map type/zoom, navigation transport, server URL, Advanced Options, and Location Tracking Details.
- Advanced Options include tracking accuracy/sensitivity, Smart frequent threshold/detection/inactivity options, optional Smart mode-change notifications, manual frequent background details, marker effects, accuracy indicators, off-screen arrows, device-list refresh, speed labels, outbox policy, map update intervals, reverse geocoding threshold, route auto-update, and route progress.
- System Settings also exposes the same registered defaults through `Settings.bundle`.

**For developers:**

- `SettingsManager` is the single source for runtime preferences and side effects.
- `SettingsConfiguration` centralizes defaults, normalization, and one-time existing-install migrations.
- Settings parity is regression-tested against `Settings.bundle/Root.plist` and localized `Root.strings` files.

## Caching and Reverse Geocoding

**For users:**

- Device lists and maps remain useful when temporarily offline because recent locations, places, slogans, and widget data are cached.
- Reverse geocoding updates are centralized and respect a configurable movement threshold.

**For developers:**

- `DeviceLocationCacheStore` manages latest locations, reverse-geocode queueing, timestamp ordering, history promotion, recent visitors, and cache pruning.
- `DeviceSloganCacheStore` caches server-provided slogans and prunes stale unknown-device entries.
- `RouteCacheStore` keeps route reuse independent from location/slogan caches.

## Localization and Accessibility

**For users:**

- The app is localized in Danish, German, English, Spanish, Finnish, French, Italian, Japanese, Dutch, and Simplified Chinese.
- Dynamic Type, accessibility labels/hints, VoiceOver traits, localized alerts, and localized route/status copy are maintained across the main flows.
- Sensitive DeviceKey values are hidden by default and can be revealed temporarily.

**For developers:**

- App strings live primarily in `Assets/Localizable.xcstrings`; system Settings strings live under `Settings.bundle/*.lproj/Root.strings`.
- `InfoPlist.strings` exists for all supported app locales.
- Tests check localization key completeness for settings, Smart frequent explanations/notifications, and unknown visitor alert flows.

## Testing and Documentation

**For users:**

- The app has dedicated regression coverage for core behavior, UI flows, and App Store screenshot capture states.

**For developers:**

- Active targets are `miataruTests`, `miataruUITests`, and `miataruScreenshotUITests`.
- Shared schemes are `miataru-FunctionalUI` and `miataru-Screenshots`.
- Use `scripts/test-unit.sh`, `scripts/test-functional-ui-serial.sh`, `scripts/test-ui.sh`, `scripts/test-screenshots.sh`, or `scripts/test-all.sh`.
- Keep `documentation/test-katalog.md` and `documentation/test-gap-matrix.md` synchronized whenever tests change.

## Historical Platform Drift Decision

The 2026-03-04 iPad/iPhone audit aligned important behavior across form factors while keeping one intentional product difference: iPhone groups remain integrated in Devices, while iPad keeps a dedicated Groups tab. The dated audit remains in `miataru/documentation/audits/ipad-iphone-audit-2026-03-04.md`.
