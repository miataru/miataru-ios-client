# miataru App – Feature and Developer Guide

This document lists all features offered by the miataru iOS app. Each item is described twice: once for **users** and once for **developers**. The descriptions also outline how the feature behaves in the interface so the flow from view to view is clear.

## App Navigation and Views
**For users:**
- The app launches to a tab bar with **Devices**, **Groups**, **QR**, and **Settings** tabs. Each tab retains its own navigation stack, so returning to a tab restores where you left off.
- Tapping a device or group drills into dedicated map screens, while the QR tab always displays your personal code for quick sharing.

**For developers:**
- `iPhone_RootView` constructs the `TabView` and hosts `iPhone_DevicesView`, `iPhone_GroupsView`, `iPhone_MyDeviceQRCodeView`, and `iPhone_SettingsView`.
- `MiataruRootView` selects platform‑specific root containers so iPad and Mac can embed their own navigation styles.

## Location Tracking
**For users:**
- Enable background and foreground tracking in *Settings* to share your location with a Miataru server.
- The app sends updates even with the screen locked and records a log of recent updates.
- Location sharing can store history on the server and works offline until network connectivity resumes.
- Tracking accuracy, activity type, and sensitivity are configurable in *Settings*, and a "Location Tracking Details" sheet shows the last GPS and server updates.

**For developers:**
- `LocationManager` publishes the current location, permission state, server update status, and a log of recent updates. It switches between high‑accuracy updates in the foreground and significant‑change monitoring in the background, requests authorization when needed, and uploads data using `MiataruAPIClient`.
- `iPhone_LocationStatusView` renders `LocationManager` diagnostics, while `SettingsManager` bindings immediately adjust `CLLocationManager` configuration.

## Device Management
**For users:**
- Maintain a list of devices, each with a name, ID, and optional color.
- Add devices by scanning a Miataru QR code or entering the ID manually.
- Swipe a row to delete, edit, or start navigation, pull down to refresh locations, and the last opened device is reopened automatically on launch.

**For developers:**
- `KnownDeviceStore` persists devices in `Application Support` and ensures the current device is always present.
- `iPhone_DevicesView` uses a `NavigationStack` with `refreshable` and notification hooks to update cached locations and remember the last opened device.
- `iPhone_AddDeviceView` integrates `CodeScanner` to scan `miataru://` QR codes, offers a color picker, and prevents duplicate IDs.

## Group Management
**For users:**
- Create named groups, add or remove devices, reorder groups, and view devices by group. Empty states guide first‑time use, and swiping a group row reveals delete or edit actions.

**For developers:**
- `DeviceGroup` and `DeviceGroupStore` provide persistence for sets of device IDs. Group editing sheets reuse `iPhone_GroupDetailView` and `GroupEditSheetContainer`.
- `iPhone_GroupsView` presents the list inside a `NavigationStack` and navigates to `iPhone_GroupMapView`, which displays all group members with off‑screen arrows and optional navigation sheets per device.

## Map Views and Navigation
**For users:**
- View device positions with accuracy circles, relative time, and distance.
- Off‑screen arrows point toward devices outside the current map region.
- Optional route navigation shows travel time and progress.
- Pull down to refresh a device’s position, tap arrows to recenter or open another device, and network errors are indicated by an overlay and icon.

**For developers:**
- `iPhone_DeviceMapView` draws markers, off‑screen arrows, error overlays, network‑error icons, and handles map camera logic, timers, and edit/navigation sheets.
- `iPhone_DeviceNavigationView` uses `MKRoute` and `SettingsManager.navigationTransportType` to render routes and progress, with auto‑centering and daily route‑request limits.
- `iPhone_GroupMapView` extends the same concepts to multiple devices and supports tap‑to‑recenter off‑screen arrows for group members.

## QR Code Sharing
**For users:**
- Display your own device ID as a QR code, copy it, or share via link or email.
- Add other devices by scanning their Miataru QR code.
- The QR tab offers one‑tap sharing, and the add‑device sheet guides scanning and rejects non‑Miataru codes.

**For developers:**
- `iPhone_MyDeviceQRCodeView` renders customizable QR codes using the `QRCode` package and supports `ShareLink` and `MFMailComposeViewController`.
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

**For developers:**
- `SettingsManager` stores all preferences in `UserDefaults` and triggers side effects such as permission checks and auto‑refresh.
- `iPhone_SettingsView` binds directly to these properties and presents sheets to `iPhone_LocationStatusView` or re-run the onboarding flow via `AppState`.

## Location Status & Error Handling
**For users:**
- A dedicated status view shows permission state, last GPS and server updates, background activity, and a log of recent events.
- If a network or permission error occurs, an overlay explains the problem.
- Map screens additionally display a network-error icon when the server cannot be reached.

**For developers:**
- `LocationManager` posts `didSendOwnLocationUpdate` notifications; `ErrorOverlayManager` and `ErrorOverlay` provide reusable alert UIs, and map views toggle a network icon via `showNetworkErrorIcon` flags.

## Caching and Reverse Geocoding
**For users:**
- Device list rows display last seen time, distance, and approximate place name without requiring a network connection every time.
- Cached data is also used by device and group maps so known positions remain visible offline until refreshed.

**For developers:**
- `DeviceLocationCacheStore` caches coordinates, manages a reverse‑geocoding queue with a configurable distance threshold, and stores results in `Application Support`. Views consult the cache first before hitting the network.

## Haptic Feedback and UI Enhancements
**For users:**
- Actions like successful refresh trigger subtle haptic feedback, pulsing accuracy circles show location precision, and shimmering indicators highlight loading states.

**For developers:**
- The `Haptic` utility abstracts platform differences. Shared UI elements such as `MiataruMapMarker`, `PulsingAccuracyCircle`, `Shimmer`, `MapCompass`, and `MapScaleBar` reside under `views/Common` and are reused across device and group map views.

## Multi‑platform Support
**For users:**
- The interface adapts to iPhone, iPad, and Mac, with platform‑specific root views and onboarding flows. iPhone uses a tab bar, iPad presents split views, and Mac currently mirrors the iPhone experience in a resizable window.

**For developers:**
- `MiataruRootView` selects the appropriate root view using size classes and platform checks. Dedicated onboarding containers exist for each platform, and many components in `views/Common` are platform agnostic.

## Localization and Accessibility
**For users:**
- Available in English, German, and Japanese, with dynamic type and accessibility labels and hints applied to buttons, tab items, and swipe actions.

**For developers:**
- Localizations reside in `en.lproj`, `de.lproj`, and `ja.lproj`. Most text uses `NSLocalizedString` and SwiftUI accessibility modifiers to provide labels, hints, and traits.

---
This document serves as a comprehensive reference for both users and developers of the miataru application.
