# miataru iOS App

**miataru** is an open-source iOS application for privacy-friendly location tracking, sharing, and device management. It is designed to give users full control over their location data, with a focus on transparency, battery efficiency, and extensibility.

---

## Table of Contents

- [Overview](#overview)
- [Elements and Components](#elements-and-components)
- [Technology Stack](#technology-stack)
- [Core Architecture](#core-architecture)
- [Common Components Overview](#common-components-overview)
- [Basic Concepts and Component Interactions](#basic-concepts-and-component-interactions)
- [User Experience and Flow](#user-experience-and-flow)
- [Development Workflow](#development-workflow)
- [Testing Strategy](#testing-strategy)
- [Debugging Tips](#debugging-tips)
- [Performance Considerations](#performance-considerations)
- [Privacy & Security](#privacy--security)
- [Build Requirements](#build-requirements)
- [Dependencies](#dependencies)
- [Migration from Earlier Versions](#migration-from-earlier-versions)
- [Error Handling and Battery Optimization](#error-handling-and-battery-optimization)
- [License](#license)

---

## Overview

miataru allows users to track their device's location, share it securely with trusted parties, and manage multiple devices and groups. The app targets iOS 18+ and is built with SwiftUI for a smooth, native experience on iPhone and iPad.

---

## Elements and Components

The app is organized into several key components:

- **Root App (`miataruApp.swift`)**: Entry point, manages global state, onboarding, deep-link handling, and scene lifecycle.
- **Views**:
  - `MiataruRootView`: Main navigation and content container.
  - `OnboardingContainerView`: Guides new users through setup.
  - Device, Group, QR, and Settings views for iPhone and iPad, organized under `views/`.
  - Common UI elements (e.g., `ErrorOverlay`, `MapCompass`).
- **Managers**:
  - `LocationManager`: Handles permissions and tracking; runs high-accuracy updates in foreground and significant-change updates in background; starts/stops based on settings.
  - `SettingsManager`: Loads, saves, and observes user settings; registers defaults from `Settings.bundle` and controls behaviors like auto-lock, map config, and tracking.
  - `thisDeviceIDManager`: Manages the unique device identifier and migrates legacy IDs to a modern format under Application Support.
- **Assets**: App icons, colors, and other resources.
- **Libraries**: Integrations for QR code scanning/generation, API client, and image handling:
  - `CodeScanner` for QR code scanning
  - `QRCode` for QR code generation
  - `MiataruClientSwift` (local Swift package) exposing the `MiataruAPIClient` module
  - `SwiftImageReadWrite` for image utilities
- **Tests**: Unit and UI tests for core functionality.

## Technology Stack

- Frontend: SwiftUI (iOS 18.0+)
- State Management: ObservableObject with @Published
- Data Persistence: UserDefaults via SettingsManager; Application Support files for devices/groups and caches
- Location Services: CoreLocation (foreground high-accuracy, background significant-change)
- QR Code: CodeScanner (scan), QRCode (generate)
- Platforms: iPhone and iPad

## Core Architecture

```
miataru/
├── miataruApp.swift          # App entry, onboarding & deep links
├── views/
│   ├── Common/               # Shared UI and map components
│   ├── iPhone/               # iPhone Root, Devices, Groups, QR, Settings
│   ├── iPad/                 # iPad Root, Devices, Groups, Settings
│   └── Mac/                  # Onboarding previews (no Mac target)
├── LocationManagers/         # Location handling (fg/bg) & route caching
├── SettingsManagers/         # User prefs & data stores (Devices/Groups)
│   ├── App Settings/         # SettingsManager, thisDeviceIDManager, Settings.bundle
│   ├── Devices/              # KnownDevice, KnownDeviceStore, DeviceLocationCacheStore
│   └── Groups/               # DeviceGroup, DeviceGroupStore
└── Assets/                   # Resources & localization (xcstrings, icons)
```

## Common Components Overview

- UI building blocks (`views/Common/`):
  - `ErrorOverlay` transient error UI, `ViewModifiers` for adaptive toolbars
  - Device & group rows: `DeviceRowView`, `GroupRowView`, `DeviceNameLabel`, `DeviceBatterySymbol`
  - Map UI (`views/Common/Map/`): `MiataruMapMarker`, `PulsingAccuracyCircle`, `MapScaleBar` (+ `MapScaleBarViewModel`), `MapCompass`, `OffScreenDeviceArrow`, `OffscreenDeviceEdgeHelper`, `RouteGhostCalculator`, `RouteStyle`, `Shimmer`
- Data stores and caches:
  - `KnownDeviceStore`, `DeviceGroupStore` (secure archived storage in Application Support)
  - `DeviceLocationCacheStore` (last known device locations + reverse geocoded placemarks)
  - `RouteCacheStore` (cached MKRoute segments keyed by device/transport)
- Utilities:
  - `thisDeviceIDManager` (ID generation + migration)
  - `Haptic` helpers for success/warning/error feedback

---

---

## Basic Concepts and Component Interactions

- **State Management**: Uses `ObservableObject` and `@Published` properties for reactive UI updates (e.g., onboarding flow).
- **Settings**: Preferences are stored in `UserDefaults` and managed via `SettingsManager`. Observers react to changes (e.g., enabling/disabling tracking, toggling device auto-lock via `UIApplication.isIdleTimerDisabled`).
- **Location Tracking**: `LocationManager` requests permissions and starts/stops tracking in response to `SettingsManager.shared.trackAndReportLocation`. Foreground uses high-accuracy updates; background uses significant-change updates.
- **Device ID**: Managed by `thisDeviceIDManager` with migration from legacy storage (`deviceID.plist`) to a modern text file under Application Support.
- **Onboarding**: Shown until completion; controlled via `UserDefaults.hasCompletedOnboarding`. iPhone/iPad-optimized flows are provided.
- **Deep Link**: Opening `miataru://<DEVICE_ID>` presents an add-device sheet with the ID prefilled.
- **Error Handling**: Transient, user-friendly overlays (`ErrorOverlay`) surface issues; non-critical errors are logged.
- **Battery Optimization**: Tracking runs only when enabled. Background work is minimized; users can optionally disable auto-lock while the app is in foreground.

---

## User Experience and Flow

1. **First Launch**:
   - User is presented with the onboarding flow to set up permissions and preferences.
   - On completion, the main app interface is shown.

2. **Main Interface**:
   - View devices and groups on a map; manage known devices and groups; adjust settings.
   - Share your device via a QR code or deep link; scan others using the built-in scanner.

3. **Settings**:
   - Enable/disable location tracking; configure map and update behavior; control device auto-lock and other preferences.

4. **Error Handling**:
   - If permissions are missing or errors occur, the user is notified and guided to resolve issues.

5. **Platforms**:
   - iPhone and iPad are supported. Mac-specific code paths exist for previews, but there is no Mac target in the project.

---

## Development Workflow

### Code Organization
- Views: Keep UI logic minimal, delegate to managers
- Managers: Handle business logic, persistence, and system services
- Models: Use SwiftUI’s data binding and `ObservableObject`
- Assets: Organize by platform and feature; use string catalogs

### Contributing Guidelines
- Follow Swift style guide; meaningful names; small functions
- Create feature branches; write descriptive commit messages
- Test locally before pushing; update docs as needed

## Testing Strategy

- Unit tests for managers and business logic
- UI tests for critical user flows
- Test on multiple device types (iPhone, iPad)
- Verify location permission flows

## Debugging Tips

- Use Xcode location simulation
- Monitor battery usage during development
- Test background/foreground transitions
- Verify privacy compliance
- Test deep links: `miataru://<DEVICE_ID>` (Simulator: `xcrun simctl openurl booted miataru://ABCDEF`)

## Performance Considerations

### Battery Optimization
- Minimize background work; use significant-change updates for background
- Use appropriate accuracy levels in foreground
- Hook into app lifecycle transitions
- Monitor in Instruments and system battery reports

### Memory Management
- Avoid retain cycles; use weak where needed
- Clean up observers, timers, and cancellables
- Profile with Instruments for leaks and allocations

## Privacy & Security

### Data Handling
- Do not store sensitive location data unencrypted
- Implement retention controls (server-side history is opt-in)
- Provide user control over data sharing
- Follow GDPR and privacy best practices

### Permission Management
- Request only necessary permissions
- Explain why permissions are needed
- Provide clear opt-in/out options
- Handle permission changes gracefully

## Build Requirements

- Xcode 16.0+
- iOS 18.0+ deployment target
- Swift 5+
- macOS 14.0+ (development)

## Dependencies

- CodeScanner: QR code scanning
- MiataruAPIClient (via local `Libraries/MiataruClientSwift`): API client
- QRCode: QR code generation
- SwiftImageReadWrite: Image utilities

---

## Behaviour on Migration from Earlier Versions

- **Settings Migration**: On launch, the app registers defaults from `Settings.bundle/Root.plist`. Existing preferences are preserved.
- **Onboarding State**: If the onboarding flag is missing (e.g., after an update), onboarding will be shown again to ensure proper setup.
- **Location Tracking**: Tracking is controlled by observing settings, not by automatic start on launch. This ensures user intent is respected across updates.
- **Data Integrity**: Device IDs and known devices/groups are preserved. `thisDeviceIDManager` migrates legacy IDs; device/group lists are stored under Application Support using secure archiving, preserving order.

---

## Error Handling and Battery Optimization

- **Error Handling**:
  - All critical operations (location, permissions, settings) are wrapped with error handling.
  - User-facing errors are displayed via overlays or alerts.
  - Non-critical errors are logged for debugging.

- **Battery Optimization**:
  - Location tracking is only active when enabled by the user.
  - The app can disable device auto-lock if requested, but defaults to energy-saving behavior.
  - Background activity is minimized unless explicitly enabled in settings.
  - Observers ensure that tracking and background tasks are only active when necessary.

---

## License

This project is licensed under the 2-clause BSD License. See the `LICENSE` file for details.

---

**miataru** – Your location, your rules. 
