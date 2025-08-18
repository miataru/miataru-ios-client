# Miataru iOS Development Guidelines

## Table of Contents
- [Localization Guidelines](#localization-guidelines)
- [Code Style & Standards](#code-style--standards)
- [File Naming Conventions](#file-naming-conventions)
- [Architecture Patterns](#architecture-patterns)
- [Testing Guidelines](#testing-guidelines)

## Localization Guidelines

### String Localization
**ALWAYS** use `NSLocalizedString` for all user-facing text strings with proper English descriptions.

#### ✅ Correct Implementation
```swift
Text(NSLocalizedString("no_groups_available_create_new", comment: "No groups available. Create a new group to get started."))
```

#### ❌ Incorrect Implementation
```swift
Text("No groups available. Create a new group to get started.")
```

### Localization Key Naming Convention
- Use descriptive, lowercase keys with underscores
- Follow the pattern: `context_action_description`
- Examples:
  - `group_empty_add_devices_message`
  - `no_groups_available_create_new`
  - `edit_device`
  - `delete_group`

### Comment Guidelines
- Provide clear, descriptive English text in the comment parameter
- Use proper English grammar and punctuation
- Make the comment self-explanatory for translators
- Avoid technical jargon in comments

### Adding New Localized Strings
1. Add the `NSLocalizedString` call in your Swift code
2. Add the key-value pair to `Localizable.xcstrings`
3. Provide translations for all supported languages (en, de, ja)

## Code Style & Standards

### SwiftUI View Naming
- iPhone views: `iPhone_ViewName.swift`
- iPad views: `iPad_ViewName.swift`
- Mac views: `Mac_ViewName.swift`
- Common/Shared views: `ViewName.swift`

### Property Wrappers
- Use `@StateObject` for objects that are created and owned by the view
- Use `@ObservedObject` for objects passed in from parent views
- Use `@EnvironmentObject` for objects injected through the environment
- Use `@State` for simple value types owned by the view

### Variable Naming
- Use camelCase for variables and functions
- Use descriptive names that explain the purpose
- Avoid abbreviations unless they are widely understood

## File Naming Conventions

### Directory Structure
```
miataru/
├── views/
│   ├── iPhone/
│   ├── iPad/
│   ├── Mac/
│   └── Common/
├── LocationManagers/
├── SettingsManagers/
└── Libraries/
```

### File Naming
- Group related files in descriptive directories
- Use clear, descriptive names for files
- Follow the established pattern for platform-specific views

## Architecture Patterns

### MVVM with SwiftUI
- Use `@StateObject` for ViewModels
- Keep business logic separate from UI code
- Use `@Published` properties for reactive updates

### Dependency Injection
- Use `@EnvironmentObject` for shared services
- Pass dependencies through initializers when appropriate
- Keep dependencies minimal and focused

### State Management
- Use local `@State` for view-specific state
- Use `@ObservedObject` for shared state
- Consider using `@StateObject` for complex state objects

## Testing Guidelines

### Unit Tests
- Test business logic separately from UI
- Mock dependencies for isolated testing
- Use descriptive test names that explain the scenario

### UI Tests
- Test user workflows end-to-end
- Use accessibility identifiers for reliable element selection
- Test on different device sizes when possible

## Common Patterns

### Error Handling
```swift
private func showErrorOverlay(_ debugMessage: String, _ userMessage: String) {
    print("Error: \(debugMessage)")
    errorOverlayManager.show(message: userMessage)
}
```

### API Calls
```swift
Task { 
    await fetchAllLocations() 
}
```

### Animation
```swift
withAnimation(.easeInOut(duration: 0.5)) {
    cameraPosition = .region(newRegion)
}
```

## Best Practices

### Performance
- Use `LazyVStack` and `LazyHStack` for large lists
- Avoid expensive operations in `body` computed property
- Use `@State` sparingly and only for view-specific state

### Memory Management
- Cancel timers and publishers in `onDisappear`
- Use weak references when appropriate
- Avoid retain cycles in closures

### Accessibility
- Provide meaningful labels for interactive elements
- Use semantic colors and fonts
- Test with VoiceOver and other accessibility features

## Code Review Checklist

- [ ] All user-facing strings use `NSLocalizedString`
- [ ] Proper error handling implemented
- [ ] Memory leaks prevented (timers, publishers cancelled)
- [ ] Code follows established naming conventions
- [ ] Appropriate property wrappers used
- [ ] Performance considerations addressed
- [ ] Accessibility features implemented

## Resources

- [Apple Localization Guide](https://developer.apple.com/documentation/xcode/localization)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [iOS Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/ios)

---

**Remember**: Always prioritize user experience, maintainability, and code quality. When in doubt, follow the established patterns in the existing codebase.
