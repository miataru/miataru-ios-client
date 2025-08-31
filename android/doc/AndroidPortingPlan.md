# Android Porting Analysis and Implementation Plan
This document tracks progress of the Android port. Mark tasks as complete once implemented.


## iOS App Feature Overview
- **Background and foreground tracking** – A shared `LocationManager` switches between high-accuracy updates in the foreground and significant-change monitoring in the background while observing settings and network reachability.
- **Device management** – `KnownDeviceStore` persists all known devices, automatically inserts the current device if missing, and saves the list whenever it changes.
- **QR-based onboarding** – Users can add devices by scanning QR codes with `CodeScanner`; the app validates that codes use the `miataru://` prefix before saving the device ID.
- **Shareable QR code for this device** – A dedicated view generates a QR code containing the local device ID and offers sharing via clipboard, email, or the iOS share sheet.
- **Map UI with off-screen indicators** – The map draws custom arrows for devices located outside the visible region, rotating and snapping intelligently to screen edges for smooth guidance.

## Android Porting Strategy
1. **Platform & Architecture**
   - Use Kotlin with Jetpack Compose to mirror SwiftUI's reactive style.
   - Implement managers as `ViewModel` + `StateFlow` equivalents for location, settings, and device stores.
   - Store preferences in DataStore and persistent entities in Room or serialized files.
2. **Location Tracking**
   - Employ Google's FusedLocationProvider for high-accuracy foreground tracking and a Foreground Service with `ACCESS_BACKGROUND_LOCATION` for background updates.
   - Switch between frequent updates and significant-change requests using distance thresholds or `PendingIntent` triggers.
   - Monitor connectivity via `ConnectivityManager` and throttle server updates when offline.
3. **Miataru Server Communication**
   - Recreate the Swift `MiataruAPIClient` with Retrofit and Kotlinx Serialization (or Ktor client).
   - Provide suspend functions for `GetLocation`, `GetLocationHistory`, and `UpdateLocation` endpoints with authentication and server configuration.
4. **Device ID & Settings**
   - Persist a unique device ID in app-private storage.
   - Build `KnownDeviceStore` and `DeviceGroupStore` equivalents with Room and expose reactive flows.
5. **Map and Navigation Features**
   - Use Google Maps Compose to render device markers, compass, and off-screen arrow indicators.
   - Implement custom composables to draw arrows and compute edge intersections analogous to the Swift implementation.
   - Optionally integrate a Directions API to render route polylines.
6. **QR Code Scanning and Generation**
   - Integrate ML Kit Barcode Scanning or ZXing for scanning `miataru://` codes during onboarding.
   - Generate QR codes with ZXing's encoder and share via Android's `Intent.ACTION_SEND`.
7. **Background Behavior and Battery Optimization**
   - Respect background execution limits by displaying a persistent notification when tracking.
   - Provide user controls to adjust location sensitivity and update intervals.
   - Use WorkManager for periodic sync or cleanup tasks.
8. **Reverse Geocoding & Caching**
   - Utilize Android's `Geocoder` or a third-party API for placemark lookup and cache results until the device moves beyond a threshold.
9. **Onboarding and Permissions**
   - Compose-based onboarding screens guide users through camera, location (foreground & background), and notification permissions.
10. **Testing & Distribution**
   - Unit-test managers and data stores with JUnit; UI-test flows with Espresso.
   - Target API 24+ and configure CI for builds and tests.

## Implementation Checklist
- [ ] **Project and dependency setup**
  - [ ] Integrate Hilt for dependency injection.
  - [ ] Replace custom HTTP logic with Retrofit and Kotlinx Serialization.
  - [ ] Add coroutine and Flow dependencies.
- [ ] **Device identification and persistence**
  - [ ] Implement a persistent device ID manager.
  - [ ] Migrate `KnownDeviceStore` to Room or DataStore with reactive updates.
  - [ ] Add device grouping and CRUD operations.
- [ ] **Location tracking**
  - [ ] Convert `LocationService` into a Foreground Service with notification and background permission handling.
  - [ ] Switch between high-accuracy foreground updates and significant-change background updates.
- [ ] **Miataru API client**
  - [ ] Support `GetLocationHistory`, `UpdateLocation`, and server configuration.
  - [ ] Add error handling, retries, and offline caching of pending updates.
- [ ] **QR code onboarding**
  - [ ] Integrate ML Kit or ZXing for scanning and generating `miataru://` codes.
  - [ ] Build Compose screens to scan codes, validate IDs, and generate shareable QR codes.
- [ ] **Map and UI**
  - [ ] Introduce Google Maps Compose for marker rendering, compass, and off-screen indicators.
  - [ ] Create screens for device list management, map view, and settings.
- [ ] **Settings and permissions**
  - [ ] Store user preferences (server URL, tracking options) with DataStore.
  - [ ] Implement onboarding flow requesting camera, location, and notification permissions.
- [ ] **Background behavior and battery management**
  - [ ] Handle Doze/App Standby with WorkManager for periodic sync.
  - [ ] Allow users to toggle tracking and adjust update intervals.
- [ ] **Testing and CI**
  - [ ] Add unit tests for stores and API client.
  - [ ] Add instrumentation tests for location service and QR scanning.
  - [ ] Configure GitHub Actions to run Gradle builds and tests.

