# miataru iOS App - Project Overview

## 🎯 Project Purpose
miataru is a privacy-focused iOS application that enables users to track their device location, share it securely with trusted parties, and manage multiple devices and groups. The app prioritizes user privacy, battery efficiency, and cross-platform compatibility.

## 🏗️ Architecture Overview

### Technology Stack
- **Frontend**: SwiftUI (iOS 17.0+)
- **State Management**: ObservableObject pattern with @Published properties
- **Data Persistence**: UserDefaults via SettingsManager
- **Location Services**: CoreLocation framework
- **QR Code**: Custom QR scanning and generation
- **Platforms**: iPhone, iPad, Mac (universal app)

### Core Components
```
miataruApp.swift (Entry Point)
├── MiataruRootView (Main Navigation)
├── OnboardingContainerView (User Setup)
├── LocationManagers/
│   └── LocationManager.swift
├── SettingsManagers/
│   └── App Settings/
├── views/
│   ├── Common/ (Shared UI)
│   ├── iPhone/ (iPhone-specific)
│   ├── iPad/ (iPad-specific)
│   └── Mac/ (Mac-specific)
└── Assets/ (Resources & Localization)
```

## 🔑 Key Features

### Location Management
- **Privacy-First**: User controls all location sharing
- **Battery Optimized**: Smart location updates
- **Permission Handling**: Graceful permission management
- **Background Support**: Configurable background location

### Device Management
- **Multi-Device**: Track multiple devices
- **Group Support**: Organize devices into groups
- **QR Code Sharing**: Easy device onboarding
- **Cross-Platform**: iPhone, iPad, and Mac support

### User Experience
- **Onboarding Flow**: Guided setup process
- **Settings Control**: Comprehensive user preferences
- **Error Handling**: User-friendly error messages
- **Localization**: German, English, and Japanese support

## 📱 Platform-Specific Considerations

### iPhone
- Touch-optimized interface
- Location permission workflows
- Background app refresh handling
- Battery optimization features

### iPad
- Larger screen layouts
- Split view support
- Enhanced device management
- Optimized for productivity

### Mac
- Desktop-appropriate controls
- Keyboard and mouse support
- Menu bar integration
- Native macOS appearance

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
- Xcode 15.0+
- iOS 17.0+ deployment target
- Swift 5.9+
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
- **MiataruClientSwift**: API client
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
