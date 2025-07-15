# miataru iOS App

**miataru** is an open-source iOS application for privacy-friendly location tracking, sharing, and device management. It is designed to give users full control over their location data, with a focus on transparency, battery efficiency, and extensibility.

---

## Table of Contents

- [Overview](#overview)
- [Elements and Components](#elements-and-components)
- [Basic Concepts and Component Interactions](#basic-concepts-and-component-interactions)
- [User Experience and Flow](#user-experience-and-flow)
- [Migration from Earlier Versions](#migration-from-earlier-versions)
- [Error Handling and Battery Optimization](#error-handling-and-battery-optimization)
- [License](#license)

---

## Overview

miataru allows users to track their device's location, share it securely with trusted parties, and manage multiple devices and groups. The app is built with SwiftUI and leverages modern iOS frameworks for a smooth, native experience.

---

## Elements and Components

The app is organized into several key components:

- **Root App (`miataruApp.swift`)**: Entry point, manages global state, onboarding, and scene lifecycle.
- **Views**:
  - `MiataruRootView`: Main navigation and content container.
  - `OnboardingContainerView`: Guides new users through setup.
  - Device, Group, and Settings views for iPhone, iPad, and Mac, organized under `views/`.
  - Common UI elements (e.g., `ErrorOverlay`, `MapCompass`).
- **Managers**:
  - `LocationManager`: Handles location permissions, tracking, and reporting.
  - `SettingsManager`: Loads, saves, and observes user settings.
  - `thisDeviceIDManager`: Manages unique device identifiers.
- **Assets**: App icons, colors, and other resources.
- **Libraries**: Integrations for QR code scanning/generation, API clients, and image handling.
- **Tests**: Unit and UI tests for core functionality.

---

## Basic Concepts and Component Interactions

- **State Management**: Uses `ObservableObject` and `@Published` properties for reactive UI updates (e.g., onboarding flow).
- **Settings**: User preferences are stored in `UserDefaults` and managed via `SettingsManager`. Changes are observed and trigger updates in other components (e.g., enabling/disabling location tracking).
- **Location Tracking**: `LocationManager` requests permissions and manages tracking based on user settings. It does not start tracking automatically on launch; instead, it observes the relevant setting and acts accordingly.
- **Device ID**: Each device has a unique identifier managed by `thisDeviceIDManager`, used for sharing and tracking.
- **Onboarding**: The onboarding flow is shown until the user completes it, tracked via a flag in `UserDefaults`.
- **Error Handling**: Errors (e.g., permission issues) are surfaced to the user via overlays and handled gracefully in the background.
- **Battery Optimization**: The app respects user preferences for background activity and can disable the device's auto-lock feature if requested.

---

## User Experience and Flow

1. **First Launch**:
   - User is presented with the onboarding flow to set up permissions and preferences.
   - On completion, the main app interface is shown.

2. **Main Interface**:
   - Users can view their device's location, manage known devices and groups, and adjust settings.
   - QR codes are used for easy device sharing and onboarding.

3. **Settings**:
   - Users can enable/disable location tracking, control background behavior, and manage device auto-lock.

4. **Error Handling**:
   - If permissions are missing or errors occur, the user is notified and guided to resolve issues.

5. **Multi-Platform**:
   - The app provides tailored views for iPhone, iPad, and Mac, ensuring a consistent experience across devices.

---

## Behaviour on Migration from Earlier Versions

- **Settings Migration**: On launch, the app loads settings from the current `Settings.bundle`. If migrating from an older version, it attempts to preserve user preferences and device IDs.
- **Onboarding State**: If the onboarding flag is missing (e.g., after an update), onboarding will be shown again to ensure proper setup.
- **Location Tracking**: Tracking is now controlled by observing the settings, not by automatic start on launch. This ensures user intent is always respected, even after updates.
- **Data Integrity**: Device IDs and known devices are preserved across updates, unless the user resets the app.

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

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

**miataru** – Your location, your rules. 