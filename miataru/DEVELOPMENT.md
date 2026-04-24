# Development Guide - miataru iOS App

## Quick Start for Developers

### Prerequisites
- Xcode 16.0+ (iOS 18.0+ deployment target)
- iOS 18.0+ device or simulator
- Swift 5+
- macOS 14.0+ (for development)

### Setup
1. Clone the repository
2. Open `miataru/miataru.xcodeproj` in Xcode
3. Select your development team in project settings
4. Build and run on target device/simulator

## Project Structure Deep Dive

### Core Architecture
```
miataru/
├── miataruApp.swift          # App entry, global state, onboarding & deep links
├── views/                    # UI components
│   ├── Common/               # Shared UI elements
│   ├── iPhone/               # Root, devices, groups, settings, QR
│   ├── iPad/                 # Root, devices, groups, settings
│   └── Mac/                  # Onboarding previews (no Mac target)
├── LocationManagers/         # Location handling (fg/bg, significant-change)
├── SettingsManagers/         # User preferences & data stores
│   ├── App Settings/         # SettingsManager, Settings.bundle
│   ├── Devices/              # KnownDevice, KnownDeviceStore
│   └── Groups/               # DeviceGroup, DeviceGroupStore
└── Assets/                   # Resources & localization (xcstrings, icons)
```

### Common Components Overview

- Shared UI (`views/Common/`):
  - `ErrorOverlay` (transient errors), `ViewModifiers` (`adaptiveToolbarBackground`, `adaptiveNavigationBackground`)
  - `DeviceRowView`, `GroupRowView`, `DeviceNameLabel` (label caching), `DeviceBatterySymbol`
  - Map helpers (`views/Common/Map/`): `MiataruMapMarker`, `PulsingAccuracyCircle`, `MapScaleBar` + `MapScaleBarViewModel`, `MapCompass`, `OffScreenDeviceArrow`, `OffscreenDeviceEdgeHelper`, `RouteGhostCalculator`, `RouteStyle`, `Shimmer`
- Stores & caches:
  - `KnownDeviceStore`, `DeviceGroupStore` (secure archiving to Application Support)
  - `DeviceLocationCacheStore` (last locations + reverse geocode queue)
  - `RouteCacheStore` (cached `MKRoute` by device & transport; distance-based validity)
- Utilities:
  - `thisDeviceIDManager` (device ID generation + legacy migration)
  - `Haptic` (success/warning/error feedback)

### Key Dependencies
- **CodeScanner**: QR code scanning functionality
- **MiataruAPIClient** (via local `Libraries/MiataruClientSwift`): Miataru protocol client
- **QRCode**: QR code generation
- **SwiftImageReadWrite**: Image handling utilities

## Development Workflow

### Code Organization
- **Views**: Keep UI logic minimal, delegate to managers
- **Managers**: Handle business logic and data persistence
- **Models**: Use SwiftUI's built-in data binding
- **Assets**: Organize by platform and feature

### Testing Strategy
- Unit tests for managers and business logic
- UI tests for critical user flows
- Test on multiple device types (iPhone, iPad)
- Verify location permission flows

### Debugging Tips
- Use Xcode's location simulation for testing
- Monitor battery usage during development
- Test background/foreground transitions
- Verify privacy compliance
 - Test deep links: `miataru://<DEVICE_ID>` (Simulator: `xcrun simctl openurl booted miataru://ABCDEF...`)

### Navigation Route Refresh Behavior
- Auto-refresh route decisions are centralized in `views/Common/NavigationRouteRefreshPolicy.swift`.
- Hard refresh triggers: auto-update enabled + missing route, or user off-route.
- Standard navigation mode (`isRouteFromDeviceToUser == true`): target movement only triggers reroute when target moved significantly **and** is off the current route.
- In standard navigation mode, bottom accessory ETA/arrival values are continuously updated from elapsed time since the route seed timestamp, so the displayed route time does not appear frozen between route recalculations.
- Reverse navigation mode keeps movement-trigger behavior compatible with prior logic after the significant-movement check.
- Route reuse still goes through `RouteCacheStore` (`useCachedRouteIfValid`) before issuing new `MKDirections` requests.
- Focused double-tap navigation mode (`isNavigationMode == true`) intentionally renders a stable base route (plus optional mutual-navigation overlay) without ghost/progress segmentation.
- Focused mode periodically re-establishes the already-available route polyline on the map (~6s cadence) to prevent transient disappearing overlays; this is a render refresh and does **not** trigger additional `MKDirections` API calls.

### Widget Intent String Extraction
- `DeviceSelectionIntent.parameterSummary` uses key-path summary syntax (`Summary { \.$device }`) to avoid generating a fragile interpolated key (`"Show ${device}"`) that can become stale in `miataruWidgets/Localizable.xcstrings`.

## Common Development Tasks

### Adding New Features
1. Create view in appropriate platform folder
2. Add manager if business logic is needed
3. Update settings if user preferences are involved
4. Add localization strings
5. Test on all target platforms

### Location Permission Handling
- Always check authorization status before requesting
- Provide clear user feedback
- Handle denied permissions gracefully
- Respect user's privacy choices

### Settings Management
- Use `SettingsManager` for all user preferences
- Observe changes and update UI accordingly
- Provide sensible defaults
- Validate user input
 - Register defaults from `Settings.bundle/Root.plist` via `SettingsManager.registerDefaultsFromSettingsBundle()`

## Performance Considerations

### Battery Optimization
- Minimize background location updates
- Use appropriate accuracy levels
- Implement proper app lifecycle handling
- Monitor battery usage in development

### Memory Management
- Avoid retain cycles in closures
- Use weak references where appropriate
- Clean up observers and timers
- Monitor memory usage in Instruments

## Privacy & Security

### Data Handling
- Never store sensitive location data unencrypted
- Implement proper data retention policies
- Provide user control over data sharing
- Follow GDPR and privacy best practices

### Permission Management
- Request only necessary permissions
- Explain why permissions are needed
- Provide clear opt-out options
- Handle permission changes gracefully

## Troubleshooting

### Common Issues
- **Location not updating**: Check permission status and settings
- **QR code not scanning**: Verify camera permissions
- **Settings not persisting**: Check UserDefaults implementation
- **Background location issues**: Verify background modes in Info.plist
- **"Error while encoding the location update" shown unexpectedly**:
  - This message is considered a technical/debug signal and should not be surfaced as a prominent user-facing overlay.
  - Verify `MiataruAPIClient.performPostRequest<T: Encodable>` rethrows existing `APIError` values unchanged, so transient request failures are not mislabeled as encoding issues.
  - For map/history fetch UI, log encoding failures via `debugLog` and avoid large red error overlays unless a user-actionable issue exists.

### Network Retry Policy (Implemented)
- Miataru API retries are centralized in app code:
  - `miataru/Networking/MiataruRetryPolicy.swift`
  - `miataru/Networking/MiataruRequestExecutor.swift`
  - `miataru/Networking/MiataruAppAPI.swift`
- Retryable failures:
  - transient `URLError` (`timedOut`, `networkConnectionLost`, `notConnectedToInternet`, `cannotConnectToHost`, `cannotFindHost`, `dnsLookupFailed`)
  - HTTP `408`, `429`, and `5xx`
- Non-retryable failures:
  - `invalidURL`, `encodingError`, `decodingError`
  - auth/ACL failures (`401`, `403`) and other functional `4xx`
- Profiles:
  - Reads: `1` retry, `0.8s` backoff, `±25%` jitter
  - Writes: `1` retry, `1.0s` backoff, `±25%` jitter
  - `updateLocation`: `1` retry, `1.2s` backoff, `±25%` jitter, then persistent outbox
- `updateLocation` outbox:
  - persisted in App Support (`locationUpdateOutbox.json`)
  - FIFO, default cap `500`, default TTL `24h`, user-configurable up to higher caps and unlimited TTL, dedupe by `Device+Timestamp+Latitude+Longitude`
  - while pending items exist, new `updateLocation` submissions are appended to the outbox instead of being sent ahead of older updates
  - queued items keep the original `UpdateLocationPayload`, including the event timestamp from the location update; retry sends must not rewrite metadata to the later send time
  - user controls live in Advanced Options > App behavior and are persisted via `location_update_outbox_retention_mode` and `location_update_outbox_max_items`
  - Settings > location status shows the current pending outbox count as "Queued location updates"
  - flush triggers: app active, network recovery, periodic timer (`60s`) while pending items exist
- Widget extension intentionally keeps direct client calls without retries.

### Debug Commands
- Enable location simulation in Xcode
- Use Console app for system logs
- Monitor network requests in Network tab
- Check device logs for permission issues

## Contributing Guidelines

### Code Style
- Follow Swift style guide
- Use meaningful variable names
- Add comments for complex logic
- Keep functions focused and small

### Git Workflow
- Create feature branches for new work
- Write descriptive commit messages
- Test before pushing
- Update documentation as needed

## Resources

### Documentation
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Location Services Programming Guide](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/)

### Tools
- Xcode Instruments for performance profiling
- Simulator for testing different devices
- TestFlight for beta distribution
- App Store Connect for release management
