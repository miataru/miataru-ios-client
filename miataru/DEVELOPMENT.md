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

### Network Retry Policy (Guideline)
- Add retries only for transient failures (`URLError.timedOut`, `networkConnectionLost`, `cannotConnectToHost`, HTTP `408/429/5xx`).
- Do not retry `encodingError`, `decodingError`, `invalidURL`, or auth/device-key validation failures.
- Prefer a short exponential backoff with jitter (for example 1-2 retries) and keep `updateLocation` conservative to avoid duplicate history entries.

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
