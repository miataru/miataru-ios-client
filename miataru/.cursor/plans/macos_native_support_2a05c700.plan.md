---
name: macOS Native Support
overview: Enable the miataru app to run natively on macOS with full feature set, excluding background location reporting. This involves updating project configuration, creating macOS-specific views, adapting platform-specific APIs, and ensuring all features work appropriately for macOS.
todos:
  - id: project-config
    content: Update Xcode project configuration to support macOS platform (SDKROOT, SUPPORTED_PLATFORMS, deployment target)
    status: completed
  - id: app-lifecycle
    content: Update miataruApp.swift to support NSApplicationDelegate on macOS and handle platform-specific lifecycle events
    status: completed
  - id: location-manager
    content: "Adapt LocationManager.swift to work on macOS: replace UIKit APIs, disable background tracking, handle battery level (nil on macOS)"
    status: completed
  - id: mac-root-view
    content: Implement Mac_RootView.swift with full TabView containing Devices, Groups, QR, and Settings tabs
    status: completed
  - id: mac-devices-view
    content: Create Mac_DevicesView.swift with macOS-appropriate UI (context menus instead of swipe actions)
    status: completed
  - id: mac-device-map
    content: Create Mac_DeviceMapView.swift adapting iPhone/iPad map views for macOS
    status: completed
  - id: mac-groups-view
    content: Create Mac_GroupsView.swift and Mac_GroupMapView.swift for group management
    status: completed
  - id: mac-qr-view
    content: Create Mac_MyDeviceQRCodeView.swift with file picker/drag-drop for QR scanning instead of camera
    status: completed
  - id: mac-add-device
    content: Create Mac_AddDeviceView.swift with file picker for QR code images and manual entry fallback
    status: completed
  - id: mac-settings
    content: Create Mac_SettingsView.swift and Mac_LocationStatusView.swift, removing autolock setting
    status: completed
  - id: platform-utilities
    content: Update BottomAccessoryModifier.swift and ViewModifiers.swift to work on macOS
    status: completed
  - id: qr-scanning-alt
    content: Implement file-based QR code scanning alternative for macOS (file picker + CoreImage QR detection)
    status: completed
  - id: pasteboard-mail
    content: Replace UIPasteboard with NSPasteboard and MFMailComposeViewController with NSSharingService/Mail.app URL scheme
    status: completed
  - id: window-management
    content: Update DeviceWindowEntrypoint and window management for macOS multi-window support
    status: completed
  - id: common-components
    content: Review and test all Common view components for macOS compatibility
    status: completed
  - id: entitlements-permissions
    content: Verify and update Info.plist and entitlements for macOS location permissions
    status: completed
  - id: platform-view-isolation
    content: Wrap all iPhone and iPad view files with
    status: completed
  - id: common-view-dependencies
    content: Extract shared utilities from iOS-only views so Common views can work on all platforms (DeviceHistoryFormatters.swift)
    status: completed
  - id: mac-view-independence
    content: Update Mac views to remove references to iPhone/iPad views and implement full macOS versions
    status: pending
  - id: multi-platform-build
    content: Ensure project builds successfully for macOS, iOS, and iPadOS simultaneously
    status: pending
---

# macOS Native Support Implementation Plan

## Branch Strategy

**All implementation work must be done on a separate branch named `macos`.**

Before starting any implementation:

1. Create and checkout the `macos` branch from the current master/main branch
2. All commits should be made to this branch
3. The branch can be merged back to master/main after completion and testing

## Overview

Transform the miataru iOS/iPadOS app into a universal app that also targets macOS natively. All features will be available except background location reporting (which is not applicable to macOS).

## Architecture Changes

### 1. Project Configuration

- **File**: `miataru.xcodeproj/project.pbxproj`
- Add macOS as a supported platform in build settings
- Update `SUPPORTED_PLATFORMS` to include `macosx` while keeping `iphoneos` and `ipados`
- Update `SDKROOT` to support both `iphoneos` and `macosx`
- Add macOS deployment target (macOS 14.0+ to match iOS 18.0+)
- Configure universal binary settings
- Ensure the project builds for all platforms: macOS, iOS, and iPadOS

### 2. App Entry Point & Lifecycle

- **File**: `miataru/miataruApp.swift`
- Replace `UIApplicationDelegate` with platform-agnostic approach:
- Use `#if os(iOS)` for iOS-specific AppDelegate
- Use `#if os(macOS)` for `NSApplicationDelegate` on macOS
- Update `UIApplication.shared.applicationState` checks to use `NSApplication.shared.isActive` on macOS
- Remove or conditionally compile autolock timer code (macOS doesn't have autolock)
- Update scene phase handling for macOS window lifecycle
- Ensure `fullScreenCover` works on macOS (use `.sheet` as fallback if needed)

### 3. Location Manager

- **File**: `miataru/LocationManagers/LocationManager.swift`
- Replace UIKit dependencies:
- `UIApplication.shared.applicationState` → Platform-agnostic check or `NSApplication.shared.isActive` on macOS
- `UIDevice.current.batteryLevel` → Use `IOKit` on macOS or return `nil` (battery not applicable)
- `UIApplication.didBecomeActiveNotification` → `NSApplication.didBecomeActiveNotification` on macOS
- Disable background location tracking on macOS:
- Wrap `allowsBackgroundLocationUpdates` in `#if os(iOS)`
- Skip significant-change monitoring on macOS
- Only enable foreground location tracking
- Update notification observers to use platform-appropriate notification names
- Ensure `openAppSettings()` uses `NSWorkspace.shared.open()` on macOS instead of `UIApplication.shared.open()`

### 4. Platform-Specific View Isolation

- **Strategy**: Wrap all iPhone and iPad view files with `#if os(iOS)` guards to exclude them from macOS builds
- This ensures clean separation: Mac views won't accidentally reference iOS-only views
- Shared views in `views/Common/` should have minimal `#if os` conditionals - only where absolutely necessary
- **Status**: ✅ Completed - All 23 iPhone view files and 8 iPad view files wrapped with `#if os(iOS)` guards

**Files wrapped with `#if os(iOS)`:**

- All files in `miataru/views/iPhone/` directory (23 files) - ✅ Completed
- All files in `miataru/views/iPad/` directory (8 files) - ✅ Completed
- Each file wrapped as:
  ```swift
  #if os(iOS)
  // ... entire view implementation ...
  #endif
  ```


**Important Notes:**

- Avoid nested `#if os(iOS)` conditionals inside files already wrapped - remove redundant inner conditionals
  - Example: `iPhone_GroupMapView.swift` had nested `#if os(iOS)` that caused syntax errors - removed inner conditionals and simplified toolbar placement
- When wrapping, ensure Preview blocks are also inside the `#if os(iOS)` guard
- Files that reference iOS-only views internally should have those conditionals removed if the entire file is wrapped
- Toolbar placement and navigation bar modifiers can be simplified when the entire file is iOS-only (no need for `#if os(iOS)` conditionals)

**Mac views that currently reference iPhone/iPad views need to be updated:**

- `Mac_DeviceMapView.swift` - currently uses `iPad_DeviceMapView`, needs full macOS implementation
- `Mac_DeviceNavigationView.swift` - currently uses `iPhone_DeviceNavigationView`, needs full macOS implementation
- `Mac_GroupMapView.swift` - currently uses `iPhone_GroupMapView`, needs full macOS implementation
- `Mac_GroupDetailView.swift` - currently uses `iPhone_GroupDetailView`, needs full macOS implementation
- `Mac_OnboardingContainerView.swift` - currently uses iPhone onboarding views, needs macOS-specific onboarding views or shared components

### 5. Root View Selection

- **File**: `miataru/views/MiataruRootView.swift`
- Already correctly uses `#if os(macOS)` for Mac_RootView and `#else` for iPhone/iPad views
- Ensure proper environment object injection

### 6. macOS Root View Implementation

- **File**: `miataru/views/Mac/Mac_RootView.swift`
- Already implemented with full TabView containing four tabs
- Uses Mac-specific views only (no iPhone/iPad references)

### 7. Device Views for macOS

- **Files**: 
- `miataru/views/Mac/Devices Views/Mac_DevicesView.swift` - Already implemented
- `miataru/views/Mac/Devices Views/Mac_DeviceMapView.swift` - **Needs update**: Currently references `iPad_DeviceMapView`, must implement full macOS version
- `miataru/views/Mac/Devices Views/Mac_AddDeviceView.swift` - Already implemented
- `miataru/views/Mac/Devices Views/Mac_EditDeviceView.swift` - Already implemented
- `miataru/views/Mac/Devices Views/Mac_DeviceNavigationView.swift` - **Needs update**: Currently references `iPhone_DeviceNavigationView`, must implement full macOS version
- Mac views must be completely independent - no references to iPhone/iPad views
- Use macOS-appropriate UI patterns (context menus, toolbar buttons, etc.)
- Ensure map views work with MapKit on macOS

### 8. Group Views for macOS

- **Files**:
- `miataru/views/Mac/Groups Views/Mac_GroupsView.swift` - Already implemented
- `miataru/views/Mac/Groups Views/Mac_GroupMapView.swift` - **Needs update**: Currently references `iPhone_GroupMapView`, must implement full macOS version
- `miataru/views/Mac/Groups Views/Mac_GroupDetailView.swift` - **Needs update**: Currently references `iPhone_GroupDetailView`, must implement full macOS version
- Mac views must be completely independent - no references to iPhone/iPad views

### 9. QR Code View for macOS

- **File**: `miataru/views/Mac/Mac_MyDeviceQRCodeView.swift` - Already implemented
- Must be completely independent - no references to iPhone views
- Uses file picker for QR scanning instead of camera
- Manual device ID entry (already supported)
- Drag-and-drop QR code images
- Uses `NSPasteboard.general` instead of `UIPasteboard`
- Uses `NSSharingService` or `Mail.app` URL scheme instead of `MFMailComposeViewController`
- Uses `NSImage` instead of `UIImage`

### 10. Settings View for macOS

- **File**: `miataru/views/Mac/Settings Views/Mac_SettingsView.swift` - Already implemented
- Must be completely independent - no references to iPhone views
- Removes autolock setting (not applicable on macOS)
- Uses macOS-appropriate form styling
- Updates navigation to settings app (different on macOS)

### 11. Location Status View for macOS

- **File**: `miataru/views/Mac/Settings Views/Mac_LocationStatusView.swift` - Already implemented
- Must be completely independent - no references to iPhone views
- Removes background-specific metrics (not applicable on macOS)

### 12. Platform-Specific Utilities

- **File**: `miataru/views/Common/BottomAccessoryModifier.swift`
- Already updated with platform-specific code
- Keep `#if os` conditionals minimal - only where necessary for platform differences
- **File**: `miataru/views/Common/ViewModifiers.swift`
- Already updated with platform-specific toolbar modifiers
- Keep `#if os` conditionals minimal

### 13. Map View Representables

- **Files**: 
- `miataru/views/iPhone/Devices Views/iPhone_LegacyMapViewRepresentable.swift` - Will be wrapped with `#if os(iOS)`
- `miataru/views/iPad/Devices Views/iPad_LegacyMapViewRepresentable.swift` - Will be wrapped with `#if os(iOS)`
- Mac views should use MapKit directly or create macOS-specific map representables if needed
- Ensure MapKit works correctly on macOS (should be compatible)

### 14. Haptic Feedback

- **File**: `miataru/Haptic/Haptics.swift`
- Already supports macOS via `NSHapticFeedbackManager` - verify it works correctly

### 15. Window Management

- **File**: `miataru/miataruApp.swift`
- Update `DeviceWindowEntrypoint` to work on macOS
- Ensure window opening/closing works with macOS window management
- Consider using `WindowGroup` with value-based windows for device detail views

### 16. Info.plist & Entitlements

- **File**: `miataru/Info.plist`
- Add macOS-specific keys if needed
- Update location usage descriptions for macOS
- **File**: `miataru/miataru.entitlements`
- Ensure location services entitlements work on macOS
- Remove background location entitlement on macOS (if platform-specific)

### 17. Common View Components

- **Status**: ✅ Partially completed - Shared utilities extracted for platform-agnostic Common views
- Review all files in `miataru/views/Common/`:
- Ensure they work on macOS (most SwiftUI should be compatible)
- Update any UIKit-specific code
- Test map markers, compass, scale bar, etc. on macOS

**Shared Utilities Created:**

- **File**: `miataru/views/Common/DeviceHistoryFormatters.swift` - ✅ Created
  - Extracted `DeviceHistoryFormatters` enum with date formatters (timelineDateFormatter, timelineTimeFormatter, timelineDayFormatter)
  - Extracted `DeviceHistoryColors` enum with `historyColor(for:)` function
  - These utilities are platform-agnostic and available on all platforms
  - Updated `TimelineRangeSlider.swift` to use shared utilities instead of `iPhone_DeviceHistoryMapView`
  - Updated `DeviceHistoryTimelineOverlay.swift` to use shared utilities
  - Updated `iPhone_DeviceHistoryMapView.swift` to use shared utilities via computed properties (maintains backward compatibility)

**Key Learning:**

- Common views cannot reference iOS-only views (like `iPhone_DeviceHistoryMapView`) even if they're wrapped
- Shared functionality must be extracted into platform-agnostic utilities in `views/Common/`
- This ensures Common views compile and work on all platforms (iOS, iPadOS, macOS)

### 18. Settings Manager

- **File**: `miataru/SettingsManagers/App Settings/SettingsManager.swift`
- Remove or conditionally compile `disableDeviceAutolock` on macOS
- Ensure all other settings work cross-platform

### 19. Onboarding

- **File**: `miataru/views/Mac/Mac_OnboardingContainerView.swift`
- **Needs update**: Currently references iPhone onboarding views (`iPhone_1_OnboardingWelcomeView`, etc.)
- Must either:
  - Create macOS-specific onboarding views, OR
  - Extract shared onboarding content into platform-agnostic components
- Update permission requests for macOS (location permissions work differently)
- All referenced iPhone onboarding views will be wrapped with `#if os(iOS)`, so Mac view cannot reference them

### 20. Dependencies

- Verify all dependencies support macOS:
- `CodeScanner` - iOS only, need alternative for macOS
- `QRCode` - should work on macOS
- `MiataruAPIClient` - should work on macOS
- `SwiftImageReadWrite` - verify macOS support

## Implementation Strategy

1. **Phase 1: Platform Isolation** ✅ Completed

- ✅ Wrapped all iPhone view files with `#if os(iOS)` guards (23 files in `views/iPhone/`)
- ✅ Wrapped all iPad view files with `#if os(iOS)` guards (8 files in `views/iPad/`)
- ✅ Fixed syntax errors from nested `#if os(iOS)` conditionals (removed redundant inner conditionals)
- ✅ Created shared utilities (`DeviceHistoryFormatters.swift`) for Common views that were referencing iOS-only views
- ✅ Updated Common views (`TimelineRangeSlider`, `DeviceHistoryTimelineOverlay`) to use shared utilities
- ✅ Verified project still builds for iOS and iPadOS
- ⚠️ Verify project builds for macOS (should exclude iOS/iPad views, but may need Mac view updates)

2. **Phase 2: Complete Mac View Implementations**

- Update `Mac_DeviceMapView.swift` - remove `iPad_DeviceMapView` reference, implement full macOS version
- Update `Mac_DeviceNavigationView.swift` - remove `iPhone_DeviceNavigationView` reference, implement full macOS version
- Update `Mac_GroupMapView.swift` - remove `iPhone_GroupMapView` reference, implement full macOS version
- Update `Mac_GroupDetailView.swift` - remove `iPhone_GroupDetailView` reference, implement full macOS version
- Update `Mac_OnboardingContainerView.swift` - remove iPhone onboarding view references, create macOS-specific onboarding or shared components

3. **Phase 3: Verification**

- Verify all Mac views are independent (no iPhone/iPad references)
- Verify minimal `#if os` conditionals in shared views
- Test macOS build compiles successfully
- Test iOS build compiles successfully
- Test iPadOS build compiles successfully

4. **Phase 4: Testing**

- Test all features on macOS
- Test all features on iOS
- Test all features on iPadOS
- Ensure proper window management on macOS
- Verify entitlements and permissions on all platforms

## Key Considerations

- **Platform Isolation**: ✅ All iPhone/iPad views are wrapped with `#if os(iOS)` to exclude them from macOS builds
- **Mac View Independence**: Mac views must not reference iPhone/iPad views - they won't exist in macOS builds
- **Shared Views**: Keep `#if os` conditionals minimal in `views/Common/` - only where absolutely necessary for platform differences
- **Common View Dependencies**: Common views cannot reference iOS-only views, even if wrapped. Extract shared functionality into platform-agnostic utilities in `views/Common/`
- **Avoid Nested Conditionals**: When a file is wrapped with `#if os(iOS)`, remove redundant inner `#if os(iOS)` conditionals to avoid syntax errors
- **Multi-Platform Build**: Project must build successfully for macOS, iOS, and iPadOS simultaneously
- **Background Location**: Explicitly disabled on macOS - only foreground tracking
- **QR Scanning**: Use file picker/drag-drop instead of camera on macOS
- **Battery Level**: Not applicable on macOS - return nil or hide UI
- **Autolock**: Not applicable on macOS - hide setting
- **Haptics**: Already supported via NSHapticFeedbackManager
- **Window Management**: macOS supports multiple windows natively
- **Share Sheet**: Use NSSharingService instead of UIActivityViewController on macOS
- **Pasteboard**: Use NSPasteboard instead of UIPasteboard on macOS
- **Mail**: Use Mail.app URL scheme or NSSharingService instead of MFMailComposeViewController on macOS

## Testing Checklist

**macOS Build:**

- [ ] Project builds for macOS target
- [x] No compilation errors referencing iPhone/iPad views (views are wrapped with `#if os(iOS)`)
- [x] Common views don't reference iOS-only views (shared utilities extracted)
- [ ] App launches on macOS
- [ ] Location tracking works (foreground only)
- [ ] Device list displays and functions
- [ ] Device map displays correctly (full macOS implementation)
- [ ] Device navigation works (full macOS implementation)
- [ ] Group management works
- [ ] Group map displays correctly (full macOS implementation)
- [ ] Group detail view works (full macOS implementation)
- [ ] QR code display works
- [ ] QR code scanning via file picker works
- [ ] Settings are accessible and functional
- [ ] Onboarding flow works (macOS-specific or shared components)
- [ ] Window management works
- [ ] All navigation flows work
- [ ] Share functionality works
- [ ] Copy/paste works

**iOS Build:**

- [ ] Project builds for iOS target
- [ ] All iPhone views compile correctly (wrapped with `#if os(iOS)`)
- [ ] App launches on iOS
- [ ] All features work as before

**iPadOS Build:**

- [ ] Project builds for iPadOS target
- [ ] All iPad views compile correctly (wrapped with `#if os(iOS)`)
- [ ] App launches on iPadOS
- [ ] All features work as before