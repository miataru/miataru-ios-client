# Development Guide - miataru iOS App

## Quick Start for Developers

### Prerequisites
- Xcode 15.0+ (iOS 17.0+ deployment target)
- iOS 17.0+ device or simulator
- Swift 5.9+
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
├── miataruApp.swift          # App entry point & global state
├── views/                    # UI components
│   ├── Common/              # Shared UI elements
│   ├── iPhone/              # iPhone-specific views
│   ├── iPad/                # iPad-specific views
│   └── Mac/                 # Mac-specific views
├── LocationManagers/         # Location handling
├── SettingsManagers/         # User preferences
└── Assets/                   # Resources & localization
```

### Key Dependencies
- **CodeScanner**: QR code scanning functionality
- **MiataruClientSwift**: API client for Miataru protocol
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
- Test on multiple device types (iPhone, iPad, Mac)
- Verify location permission flows

### Debugging Tips
- Use Xcode's location simulation for testing
- Monitor battery usage during development
- Test background/foreground transitions
- Verify privacy compliance

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
