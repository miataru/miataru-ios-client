# miataru App – Feature and Developer Guide

This document lists all features offered by the miataru iOS app. Each item is described twice: once for **users** and once for **developers**. The descriptions also outline how the feature behaves in the interface so the flow from view to view is clear.

## App Navigation and Views
**For users:**
- The app launches to a tab bar with **Devices**, **Groups**, **QR**, and **Settings** tabs. Each tab retains its own navigation stack, so returning to a tab restores where you left off.
- Tapping a device or group drills into dedicated map screens, while the QR tab always displays your personal code for quick sharing.

- On iPad, you can open a device in a new window from the list or map via context menu, or by dragging the item toward the screen edge.

**For developers:**
- `iPhone_RootView` constructs the `TabView` and hosts `iPhone_DevicesView`, `iPhone_GroupsView`, `iPhone_MyDeviceQRCodeView`, and `iPhone_SettingsView`.
- `MiataruRootView` selects platform‑specific root containers so iPad and Mac can embed their own navigation styles.
- iPad supports opening device detail windows using a value‑based `WindowGroup(for: String)` and context menu/drag interactions.

## Location Tracking
**For users:**
- Enable background and foreground tracking in *Settings* to share your location with a Miataru server.
- The app sends updates even with the screen locked and records a log of recent updates.
- Location sharing can store history on the server and works offline until network connectivity resumes.
- Tracking accuracy, activity type, and sensitivity are configurable in *Settings*, and a "Location Tracking Details" page shows the last GPS and server updates.

- When supported by your device/client, the app also submits altitude (above sea level), speed, and battery level with location updates.
- Visual effects such as pulsing accuracy circles and shimmering indicators pause automatically in Low Power Mode or while the app is in the background.

**For developers:**
- `LocationManager` publishes the current location, permission state, server update status, altitude, speed, battery level (when available), and a log of recent updates. It switches between high‑accuracy updates in the foreground and significant‑change monitoring in the background, requests authorization when needed, and uploads data using `MiataruAPIClient`.
- Low Power Mode and scene phase changes are observed (e.g., `Notification.Name.NSProcessInfoPowerStateDidChange`) to gate animations like shimmer/pulsing without changing data behavior.
- `iPhone_LocationStatusView` renders `LocationManager` diagnostics, while `SettingsManager` bindings immediately adjust `CLLocationManager` configuration.

## Device Management
**For users:**
- Maintain a list of devices, each with a name, ID, and optional color.
- Add devices by scanning a Miataru QR code or entering the ID manually.
- Swipe a row to delete, edit, or start navigation, pull down to refresh locations, and the last opened device is reopened automatically on launch.

- Device rows show last update time, distance, and—when available—battery level and altitude. Units adapt to your locale (metric/imperial).
- Pull‑to‑refresh also triggers reverse geocoding for visible devices to keep place names fresh.

**For developers:**
- `KnownDeviceStore` persists devices in `Application Support` and ensures the current device is always present.
- `iPhone_DevicesView` uses a `NavigationStack` with `refreshable` and notification hooks to update cached locations and remember the last opened device.
- `iPhone_AddDeviceView` integrates `CodeScanner` to scan `miataru://` QR codes, offers a color picker, and prevents duplicate IDs.
- `DeviceRowView` (shared) replaces `iPhone_DeviceRowView`, displays battery/altitude/speed when available, and uses `MeasurementFormatter` with the system `measurementSystem` for localized units.
- `DeviceNameLabel` and static parts of markers are rasterized and cached to improve scrolling/rendering performance.

## Group Management
**For users:**
- Create named groups, add or remove devices, reorder groups, and view devices by group. Empty states guide first‑time use, and swiping a group row reveals delete or edit actions.

- Group detail lists show each device’s last update, distance, and battery status where available. On iPad, the group detail sheet shows a proper Cancel/Save toolbar.

**For developers:**
- `DeviceGroup` and `DeviceGroupStore` provide persistence for sets of device IDs. Group editing sheets reuse `iPhone_GroupDetailView` and `GroupEditSheetContainer`.
- `iPhone_GroupsView` presents the list inside a `NavigationStack` and navigates to `iPhone_GroupMapView`, which displays all group members with off‑screen arrows and optional navigation sheets per device.
- Group detail uses the shared `DeviceRowView`; altitude formatting and labels are aligned with the device list implementation. On iPad, `GroupDetailView` is wrapped in a `NavigationStack` to surface Cancel/Save buttons with localization.

## Map Views and Navigation
**For users:**
- View device positions with accuracy circles, relative time, and distance.
- Off‑screen arrows point toward devices outside the current map region.
- Optional route navigation shows travel time and progress.
- Pull down to refresh a device’s position, tap arrows to recenter or open another device, and network errors are indicated by an overlay and icon.

- Off‑screen arrows can display segmented lengths (1 segment per 50 km, up to 10) and are grouped by map edge for clarity. Their visibility is controlled by a global setting.
- When enabled, other known devices that would be visible at the current zoom level are shown on a device’s map for better context.
- Navigation includes a scale bar and custom compass; auto‑centering pauses while you interact and resumes automatically once idle.
- Route progress can be visualized using completed vs. remaining segments with a moving ghost marker (shown after at least 5% estimated progress).
- Routes are recalculated when transport mode changes or after significant movement; route requests are rate‑limited daily, and the reload action can force a fresh calculation ignoring caches.
- Start navigation by long‑pressing a device pin on the map or swiping right on a device row. Your own device never offers navigation. Apple Maps handoff uses proper destination names.
- When you switch navigation to route from your device toward a selected device, a top overlay displays turn‑by‑turn instructions.

**For developers:**
- `iPhone_DeviceMapView` draws markers, off‑screen arrows, error overlays, network‑error icons, and handles map camera logic, timers, and edit/navigation sheets. Auto‑centering gating is unified across views.
- `iPhone_DeviceNavigationView` uses `MKRoute`, `RouteCacheStore`, and `SettingsManager.navigationTransportType` to render routes and progress; it recalculates on transport changes or movement thresholds and enforces a daily route‑request limit.
- `NavigationOverlayKit` is used in `iPhone_DeviceNavigationView` to show live turn‑by‑turn instructions when routing from the current device toward the target device.
- `RouteGhostCalculator` estimates remote progress along the route using last update timestamps and current/estimated speed; progress overlay rendering splits polylines into completed/remaining segments.
- `MapScaleBar` is backed by `MapScaleBarViewModel` for cached updates; `MapCompass` is shared.
- `OffscreenDeviceEdgeHelper` groups arrow indicators by edge and scales coordinates; segments represent ~50 km and are capped at 10.
- `MiataruMapMarker` and label components use rasterized caching keyed by color/icon/height/colorScheme/scale and respect Dynamic Type and color scheme.

## QR Code Sharing
**For users:**
- Display your own device ID as a QR code, copy it, or share via link or email.
- Add other devices by scanning their Miataru QR code.
- The QR tab offers one‑tap sharing, shows visitor history directly below your code, and the add‑device sheet guides scanning and rejects non‑Miataru codes.

- The share sheet includes additional options, and email sharing attaches the QR image reliably.

**For developers:**
- `iPhone_MyDeviceQRCodeView` renders customizable QR codes using the `QRCode` package and supports `ShareLink` and `MFMailComposeViewController`.
- `VisitorHistoryViewModel` and `VisitorHistorySection` power inline visitor history within the QR tab, while `iPhone_VisitorHistoryView` reuses the same data loader.
- `iPhone_AddDeviceView` validates the `miataru://` prefix from scanned codes before accepting an ID and allows manual entry with color selection.

## Onboarding Flow
**For users:**
- A six‑step wizard guides through welcome, permissions, server URL, history settings, personal QR code display, and completion.
- Each step shows illustrations and contextual explanations; server selection validates custom HTTPS URLs, and completion flag controls whether the wizard reappears on next launch.

**For developers:**
- Platform‑specific containers (`iPhone_OnboardingContainerView`, `iPad_OnboardingContainerView`, `Mac_OnboardingContainerView`) embed the individual onboarding pages and update `SettingsManager` and `UserDefaults.hasCompletedOnboarding` as the user progresses.

## Settings and Configuration
**For users:**
- Control tracking, data retention, server URL, device autolock, accuracy indicators, map type, zoom level, update interval, group zoom‑to‑fit, off‑screen arrows, auto‑refresh, reverse geocoding threshold, navigation mode, and route progress.
- View location tracking details or replay the onboarding wizard.
- Settings are grouped into tracking, app behavior, map configuration, and navigation sections for easier discovery.

- All app preferences are also available in the system Settings app.
- New options include: navigation route auto‑update, route progress visualization toggle, a global pulsing/shimmer switch for map markers, and off‑screen arrow visibility.
- Bicycle transport mode was removed; existing values fall back to walking for directions and car icons where applicable.

**For developers:**
- `SettingsManager` stores all preferences in `UserDefaults` and triggers side effects such as permission checks and auto‑refresh.
- `iPhone_SettingsView` binds directly to these properties and navigates to `iPhone_LocationStatusView` (now a page) or re-runs the onboarding flow via `AppState`.
- Defaults are registered from `Settings.bundle`, enabling control from the system Settings app. The manager observes low‑power state and scene phase for UI effect gating.
- Reverse geocoding threshold is user‑configurable (off/100 m/1 km/10 km; default 1 km) and applied centrally.

## Location Status & Error Handling
**For users:**
- A dedicated status view shows permission state, last GPS and server updates, background activity, and a log of recent events.
- If a network or permission error occurs, an overlay explains the problem.
- Map screens additionally display a network-error icon when the server cannot be reached.

- The status view lists speed and battery (when available) and tracks route‑request statistics over the last 24 hours.

**For developers:**
- `LocationManager` posts `didSendOwnLocationUpdate` notifications; `ErrorOverlayManager` and `ErrorOverlay` provide reusable alert UIs, and map views toggle a network icon via `showNetworkErrorIcon` flags.
- Status is presented as a dedicated page; related counters (e.g., daily route requests) are maintained in settings/state for diagnostics.

## Caching and Reverse Geocoding
**For users:**
- Device list rows display last seen time, distance, and approximate place name without requiring a network connection every time.
- Cached data is also used by device and group maps so known positions remain visible offline until refreshed.

**For developers:**
- `DeviceLocationCacheStore` caches coordinates, manages a centralized reverse‑geocoding queue with a configurable distance threshold, and stores results in `Application Support`. Views consult the cache first before hitting the network and throttle UI updates to the configured map update interval.
- Own‑device updates trigger immediate cache writes to kick off reverse geocoding promptly. A `RouteCacheStore` caches routes by device and transport, with distance‑based invalidation.
- Static map elements such as `MiataruMapMarker` and `DeviceNameLabel` are rasterized and cached with keys that include color scheme and display scale; renderers respect Dynamic Type and set `isOpaque=false` where appropriate.

## Haptic Feedback and UI Enhancements
**For users:**
- Actions like successful refresh trigger subtle haptic feedback, pulsing accuracy circles show location precision, and shimmering indicators highlight loading states.

- Animations for pulsing/shimmer are automatically reduced in Low Power Mode or when the app is backgrounded to save energy.

**For developers:**
- The `Haptic` utility abstracts platform differences. Shared UI elements such as `MiataruMapMarker`, `PulsingAccuracyCircle`, `Shimmer`, `MapCompass`, and `MapScaleBar` reside under `views/Common` and are reused across device and group map views.

## Multi‑platform Support
**For users:**
- The interface adapts to iPhone, iPad, and Mac, with platform‑specific root views and onboarding flows. iPhone uses a tab bar, iPad presents split views, and Mac currently mirrors the iPhone experience in a resizable window.

- On iPad, you can open device details in separate windows for multitasking.

**For developers:**
- `MiataruRootView` selects the appropriate root view using size classes and platform checks. Dedicated onboarding containers exist for each platform, and many components in `views/Common` are platform agnostic.

## Localization and Accessibility
**For users:**
- Available in English, German, and Japanese, with dynamic type and accessibility labels and hints applied to buttons, tab items, and swipe actions.

- VoiceOver support has been improved across lists and map controls. Alerts and route‑limit messages are localized.

**For developers:**
- Localizations reside in `en.lproj`, `de.lproj`, and `ja.lproj`. Most text uses `NSLocalizedString` and SwiftUI accessibility modifiers to provide labels, hints, and traits.
- Units adapt using the system `measurementSystem`. New strings (e.g., daily route‑limit reached) are provided in the string catalog for all supported languages.

---
This document serves as a comprehensive reference for both users and developers of the miataru application.
