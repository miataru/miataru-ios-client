# miataru iOS App - Project Overview

## 🎯 Project Purpose
miataru is a privacy-focused iOS application that enables users to track their device location, share it securely with trusted parties, and manage multiple devices and groups. The app prioritizes user privacy, battery efficiency, and cross-platform compatibility.

## 🏗️ Architecture Overview

### Technology Stack
- **Frontend**: SwiftUI (iOS 18.0+)
- **State Management**: ObservableObject pattern with @Published properties
- **Data Persistence**: UserDefaults via SettingsManager; Application Support files for devices/groups
- **Location Services**: CoreLocation framework (foreground and significant-change background)
- **QR Code**: CodeScanner (scan), QRCode (generate)
- **Platforms**: iPhone and iPad

### Core Components
```
miataruApp.swift (Entry Point)
├── MiataruRootView (Main Navigation)
├── OnboardingContainerView (User Setup)
├── LocationManagers/
│   └── LocationManager.swift
├── SettingsManagers/
│   └── App Settings/ (SettingsManager, thisDeviceIDManager, Settings.bundle)
│   └── Devices/ (KnownDevice, KnownDeviceStore)
│   └── Groups/ (DeviceGroup, DeviceGroupStore)
├── views/
│   ├── Common/ (Shared UI)
│   ├── iPhone/ (iPhone-specific)
│   ├── iPad/ (iPad-specific)
│   └── Mac/ (onboarding previews only)
└── Assets/ (Resources & Localization)
```

### Common Components Overview

- Shared UI (`views/Common/`):
  - `ErrorOverlay`, `ViewModifiers` (adaptive toolbars/navigation)
  - Device & group UI: `DeviceRowView`, `GroupRowView`, `DeviceNameLabel`, `DeviceBatterySymbol`
  - Map UI & helpers (`views/Common/Map/`): `MiataruMapMarker`, `PulsingAccuracyCircle`, `MapScaleBar` (+ `MapScaleBarViewModel`), `MapCompass`, `OffScreenDeviceArrow`, `OffscreenDeviceEdgeHelper`, `RouteGhostCalculator`, `RouteStyle`, `Shimmer`
- Data & Caching:
  - `KnownDeviceStore`, `DeviceGroupStore` (secure archiving under Application Support)
  - `DeviceLocationCacheStore` (latest device locations + reverse geocoded placemarks)
  - `RouteCacheStore` (cached routes keyed by device/transport; distance threshold validation)
- Utilities:
  - `thisDeviceIDManager` (device ID generation + legacy migration)
  - `Haptic` (feedback utilities)

## 🔑 Key Features

### Location Management
- **Privacy-First**: User controls all location sharing
- **Battery Optimized**: High-accuracy foreground; significant-change background
- **Permission Handling**: Staged requests (WhenInUse → Always when opted-in)
- **Background Support**: Significant-change updates

### Device Management
- **Multi-Device**: Track multiple devices
- **Group Support**: Organize devices into groups
- **QR Code Sharing**: Share own device, scan to add others
- **Deep Link**: `miataru://<DEVICE_ID>` adds devices via sheet

### User Experience
- **Onboarding Flow**: Guided setup (iPhone/iPad-optimized)
- **Settings Control**: Comprehensive preferences via SettingsManager
- **Error Handling**: Transient overlays
- **Localization**: German, English, and Japanese

## 📱 Platform-Specific Considerations

### iPhone
- Touch-optimized interface
- Location permission workflows
- Deep-link and QR onboarding
- Battery optimization features

### iPad
- Larger screen layouts
- Split view support
- Enhanced device management
- Optimized for productivity

### Mac
- Not currently targeted (Mac directory hosts onboarding previews only)

## 🛠️ Development Guidelines

### Code Organization
- **Views**: Minimal UI logic, delegate to managers
- **Managers**: Handle business logic and data
- **Models**: Use SwiftUI data binding
- **Assets**: Organized by platform and feature

### State Management
- Use ObservableObject for view models
- Implement proper MVVM pattern
- Handle app lifecycle changes
- Manage user preferences reactively

### Testing Strategy
- Unit tests for business logic
- UI tests for critical flows
- Multi-device testing
- Permission flow verification

## 🔒 Privacy & Security

### Data Protection
- Location data encryption
- User consent requirements
- Data retention policies
- GDPR compliance

### Permission Management
- Minimal permission requests
- Clear permission explanations
- Graceful permission denial
- User control over data

## 📊 Performance Considerations

### Battery Optimization
- Smart location updates
- Background task management
- Auto-lock control
- Energy-efficient operations

### Memory Management
- Proper observer cleanup
- Weak reference usage
- Resource deallocation
- Memory leak prevention

## 🚀 Deployment & Distribution

### Build Requirements
- Xcode 16.0+
- iOS 18.0+ deployment target
- Swift 5+
- macOS 14.0+ (development)

### Distribution
- App Store distribution
- TestFlight beta testing
- Enterprise deployment support
- Universal binary support

## 🔧 Common Development Tasks

### Adding Features
1. Create platform-specific views
2. Implement business logic in managers
3. Update settings if needed
4. Add localization strings
5. Test on all platforms

### Debugging
- Location simulation in Xcode
- Permission status checking
- Battery usage monitoring
- Background task verification

### Performance Tuning
- Instruments profiling
- Memory usage analysis
- Battery impact assessment
- Background task optimization

## 📚 Resources & References

### Documentation
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [CoreLocation Framework](https://developer.apple.com/documentation/corelocation)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)

### Dependencies
- **CodeScanner**: QR code scanning
- **MiataruAPIClient** (via local `Libraries/MiataruClientSwift`): API client
- **QRCode**: QR generation
- **SwiftImageReadWrite**: Image handling

## 🎯 Future Roadmap

### Planned Features
- Enhanced privacy controls
- Advanced device grouping
- Improved battery optimization
- Extended platform support

### Technical Improvements
- Performance optimizations
- Enhanced error handling
- Better testing coverage
- Documentation updates

---

*This overview provides Cursor with comprehensive context about the miataru iOS app project, enabling better code assistance and development guidance.*
