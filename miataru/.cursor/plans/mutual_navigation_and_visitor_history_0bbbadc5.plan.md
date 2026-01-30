---
name: Mutual Navigation and Visitor History
overview: Implement mutual navigation detection with UI indicators in the navigation screen, and add a Visitor History screen accessible from the Device QR Code screen with the ability to add unknown visitor devices.
todos:
  - id: localization-strings
    content: Add all required localization strings to Localizable.xcstrings for all 10 supported languages (en, de, da, es, fi, fr, it, ja, nl, zh-Hans)
    status: completed
  - id: mutual-detector
    content: Create MutualNavigationDetector with polling, hysteresis logic, and visitor history caching
    status: completed
  - id: mutual-integration
    content: Integrate mutual detection into iPhone_DeviceNavigationView - track active navigation and use detector (all text must use NSLocalizedString)
    status: completed
  - id: bottom-status-mutual
    content: Update RouteInfoState and BottomAccessoryModifier to show localized mutual navigation indicator when mutual is active
    status: completed
  - id: route-highlight
    content: Implement dual-stroke route rendering in iPhone_DeviceNavigationView when mutual navigation is active
    status: completed
  - id: visitor-history-view
    content: Create iPhone_VisitorHistoryView with list, known/unknown device resolution, and error/empty states (all text must use NSLocalizedString)
    status: completed
  - id: qr-code-button
    content: Add localized 'Visitor History' button to iPhone_MyDeviceQRCodeView and wrap in NavigationStack
    status: completed
  - id: add-device-reuse
    content: Implement add device flow reuse - show iPhone_AddDeviceView sheet with prefillDeviceID from visitor history (with localized labels)
    status: completed
  - id: unit-tests
    content: Create unit tests for MutualNavigationDetector hysteresis and VisitorHistoryViewModel device resolution
    status: completed
  - id: verify-localization
    content: Verify all user-facing strings are properly internationalized using NSLocalizedString and translated to all 10 languages
    status: completed
---

# Implementation Plan: Mutual Navigation and Visitor History

## Overview

This plan implements two features:

- **A) Mutual Navigation UI**: Detects when both devices are navigating to each other and shows visual indicators
- **B) Visitor History UI**: Lists devices that have accessed our location, with ability to add unknown devices

## Internationalization Requirements

**CRITICAL**: All user-facing text MUST be internationalized using `NSLocalizedString` with proper English descriptions. No hardcoded strings are allowed.

### Supported Languages

The app supports **10 languages** and all new strings must be translated to all of them:

- English (en) - source language
- German (de)
- Danish (da)
- Spanish (es)
- Finnish (fi)
- French (fr)
- Italian (it)
- Japanese (ja)
- Dutch (nl)
- Simplified Chinese (zh-Hans)

### Implementation Requirements

1. **All text must use NSLocalizedString**:
   ```swift
   // ✅ CORRECT
   Text(NSLocalizedString("beidseitig_aktiv", comment: "Indicates that both devices are actively navigating to each other"))
   
   // ❌ INCORRECT - Hardcoded string
   Text("beidseitig aktiv")
   ```

2. **Add all strings to Localizable.xcstrings**:

   - File location: `miataru/Assets/Localizable.xcstrings`
   - Add entries for all 10 supported languages
   - Use descriptive English comments for translators
   - Follow existing key naming conventions (lowercase with underscores)

3. **String Key Naming Convention**:

   - Use descriptive, lowercase keys with underscores
   - Pattern: `context_action_description`
   - Examples: `mutual_navigation_active`, `visitor_history_title`, `unknown_device_label`

4. **Relative Time Formatting**:

   - Use `DateComponentsFormatter` or similar for relative time
   - Ensure format strings support all languages
   - Example: `NSLocalizedString("time_ago_minutes", comment: "Time ago in minutes, e.g., '5 min ago'")`

### Text Elements Requiring Localization

- Button labels ("Besucherprotokoll", "Hinzufügen")
- Status text ("beidseitig aktiv")
- Device labels ("Unbekanntes Gerät")
- Empty state messages ("Keine Zugriffe")
- Error messages
- Relative time strings ("vor 5 Min.")
- Accessibility labels and hints

## Platform Support

**Important**: The views used for this implementation are already shared between iPhone and iPad:

- `iPhone_DeviceNavigationView` is used on both platforms (iPad accesses it via `iPad_DevicesView` navigation destination)
- `iPhone_MyDeviceQRCodeView` is used on both platforms (both root views include it in their TabView)

Therefore, the implementation will automatically work on both iPhone and iPad without requiring separate view files. The only consideration is that `iPhone_MyDeviceQRCodeView` already handles landscape/portrait differences, and the new visitor history view should follow the same pattern.

## Architecture

### A) Mutual Navigation Detection

**Components:**

1. `MutualNavigationDetector`: ObservableObject that manages mutual navigation state

   - Polls `GetVisitorHistory` every 15-30s while navigation is active
   - Implements hysteresis logic (T_enter=60s, T_exit=90s)
   - Caches visitor history to avoid unnecessary UI updates

2. Integration in `iPhone_DeviceNavigationView`:

   - Track navigation active state (view is visible and polling)
   - Use `MutualNavigationDetector` to check if target device appears in visitor history
   - Update UI when mutual state changes
   - **Note**: This view is shared between iPhone and iPad, so mutual navigation will work on both platforms

**Files to modify:**

- `miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift` (shared, works on both platforms)
- Create `miataru/views/Common/MutualNavigationDetector.swift`

**UI Changes:**

1. Bottom status line: Append " - beidseitig aktiv" when mutual is active

   - Modify `BottomAccessoryModifier.swift` to accept optional mutual state
   - Update `RouteInfoState` to include mutual navigation flag

2. Route highlight: Dual-stroke rendering when mutual is active

   - Modify route rendering in `iPhone_DeviceNavigationView` to add overlay stroke
   - Preserve existing segmentation (done/todo) logic

### B) Visitor History UI

**Components:**

1. `iPhone_VisitorHistoryView`: New SwiftUI view

   - Fetches `GetVisitorHistory` on appear
   - Displays list sorted by most recent first
   - Shows device name if known, "Unbekanntes Gerät" + shortened ID if unknown
   - Handles empty and error states
   - **Note**: Despite the "iPhone_" prefix, this view will work on both platforms since it's accessed from the shared `iPhone_MyDeviceQRCodeView`

2. Integration in `iPhone_MyDeviceQRCodeView`:

   - Wrap in NavigationStack (if not already)
   - Add button with localized label: `NSLocalizedString("visitor_history_title", comment: "Title for visitor history screen")`
   - Push to `iPhone_VisitorHistoryView` on tap
   - **Note**: This view is already used on both iPhone and iPad, so the visitor history feature will be available on both platforms

3. Add Device Flow Reuse:

   - Create helper to trigger add device flow programmatically
   - Reuse `miataruApp.handleIncomingURL` logic or directly show sheet
   - After successful add, refresh visitor history to show updated device name

**Files to create:**

- `miataru/views/iPhone/iPhone_VisitorHistoryView.swift` (shared, works on both platforms)
- `miataru/views/Common/VisitorHistoryViewModel.swift` (optional, for testability)

**Files to modify:**

- `miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift` (shared, works on both platforms)
- `miataru/miataruApp.swift` (extract deep link handler logic if needed)

## Implementation Details

### Mutual Navigation Detection Logic

```swift
func isMutualNavigation(targetDeviceId: String) -> Bool {
    guard navigationActiveTo(targetDeviceId) else { return false }
    
    let lastSeen = newestVisitorHistoryEntry(visitorDeviceId: targetDeviceId)
    guard let lastSeen else { return false }
    
    let age = Date().timeIntervalSince(lastSeen.TimeStampDate)
    
    // Hysteresis: different thresholds for enter/exit
    if isCurrentlyMutual {
        return age <= 90.0  // T_exit
    } else {
        return age <= 60.0  // T_enter
    }
}
```

### Visitor History Row Display

- Known device: Show `KnownDevice.DeviceName` prominently
- Unknown device: Show localized "Unknown Device" label + shortened deviceId (first 6 + last 4 chars)
  - Use: `NSLocalizedString("unknown_device_label", comment: "Label for unknown/unrecognized device")`
- Timestamp: Relative time using localized format string
  - Use: `NSLocalizedString("time_ago_minutes", comment: "Time ago format, e.g., '5 min ago' or 'vor 5 Min.'")`
  - Format with `DateComponentsFormatter` for proper localization
  - Optionally show absolute timestamp as secondary text

### Add Device Flow Reuse

Two approaches:

1. **Direct sheet presentation** (simpler):
   ```swift
   @State private var showAddDeviceSheet = false
   @State private var pendingDeviceID: String? = nil
   ```


Show sheet with `iPhone_AddDeviceView(store: KnownDeviceStore.shared, isPresented: $showAddDeviceSheet, prefillDeviceID: pendingDeviceID)`

2. **Deep link simulation** (reuses existing flow):

Create URL `miataru://{deviceID}` and call `handleIncomingURL`

Prefer approach 1 for simplicity and direct control.

## Testing

**Unit Tests:**

1. `MutualNavigationDetectorTests`:

   - Test hysteresis logic (enter at 60s, exit at 90s)
   - Test state transitions
   - Test polling behavior

2. `VisitorHistoryViewModelTests`:

   - Test known vs unknown device resolution
   - Test that after adding unknown device, same entry resolves to known device name
   - Mock `KnownDeviceStore` updates

**Test Files:**

- `miataruTests/MutualNavigationDetectorTests.swift`
- `miataruTests/VisitorHistoryViewModelTests.swift`

## Localization - Required Strings

**MANDATORY**: All strings below must be added to `miataru/Assets/Localizable.xcstrings` with translations for all 10 supported languages (en, de, da, es, fi, fr, it, ja, nl, zh-Hans).

### String Keys and English Source Values

1. **Mutual Navigation**:

   - `"mutual_navigation_active"` = "mutual active" (comment: "Indicates that both devices are actively navigating to each other")
   - Example usage: `NSLocalizedString("mutual_navigation_active", comment: "Indicates that both devices are actively navigating to each other")`

2. **Visitor History**:

   - `"visitor_history_title"` = "Visitor History" (comment: "Title for visitor history screen")
   - `"visitor_history_empty"` = "No Access" (comment: "Empty state message when no visitors have accessed the device")
   - `"visitor_history_error"` = "Failed to load visitor history" (comment: "Error message when visitor history fails to load")
   - `"visitor_history_retry"` = "Retry" (comment: "Button to retry loading visitor history")

3. **Device Labels**:

   - `"unknown_device_label"` = "Unknown Device" (comment: "Label for unknown/unrecognized device")
   - `"add_device_action"` = "Add" (comment: "Button label to add an unknown device")

4. **Time Formatting**:

   - `"time_ago_minutes"` = "%d min ago" (comment: "Time ago format for minutes, e.g., '5 min ago'")
   - `"time_ago_hours"` = "%d hr ago" (comment: "Time ago format for hours, e.g., '2 hr ago'")
   - `"time_ago_days"` = "%d days ago" (comment: "Time ago format for days, e.g., '3 days ago'")
   - `"time_just_now"` = "Just now" (comment: "Indicates very recent time, within the last minute")

5. **Accessibility**:

   - `"visitor_history_accessibility_label"` = "Visitor History" (comment: "Accessibility label for visitor history button")
   - `"add_device_accessibility_hint"` = "Adds this unknown device to your device list" (comment: "Accessibility hint for add device button")

### Implementation Checklist

- [ ] All user-facing strings use `NSLocalizedString` with descriptive English comments
- [ ] All string keys added to `Localizable.xcstrings`
- [ ] Translations provided for all 10 supported languages
- [ ] String keys follow naming convention (lowercase with underscores)
- [ ] Relative time formatting uses localized format strings
- [ ] Accessibility labels and hints are localized
- [ ] No hardcoded strings in Swift code

## File Structure

```
miataru/
├── views/
│   ├── iPhone/
│   │   ├── iPhone_MyDeviceQRCodeView.swift (modify - shared, works on both platforms)
│   │   ├── iPhone_DeviceNavigationView.swift (modify - shared, works on both platforms)
│   │   └── iPhone_VisitorHistoryView.swift (new - shared, works on both platforms)
│   └── Common/
│       ├── MutualNavigationDetector.swift (new)
│       └── BottomAccessoryModifier.swift (modify)
├── SettingsManagers/
│   └── App Settings/
│       └── RouteInfoState.swift (modify)
miataruTests/
├── MutualNavigationDetectorTests.swift (new)
└── VisitorHistoryViewModelTests.swift (new)
```

**Note on Platform Support:**

- All views with "iPhone_" prefix are actually shared between iPhone and iPad
- iPad root view (`iPad_RootView`) uses `iPhone_MyDeviceQRCodeView` directly
- iPad devices view (`iPad_DevicesView`) navigates to `iPhone_DeviceNavigationView` 
- No separate iPad implementations needed - the views adapt automatically

## Implementation Order

1. **Add all localization strings** to `Localizable.xcstrings` first (en, de, da, es, fi, fr, it, ja, nl, zh-Hans)
2. Create `MutualNavigationDetector` with polling and hysteresis logic
3. Integrate mutual detection into `iPhone_DeviceNavigationView`
4. Update bottom status line to show mutual state (using localized string)
5. Implement dual-stroke route highlight
6. Create `iPhone_VisitorHistoryView` with list display (all text must use NSLocalizedString)
7. Add localized "Visitor History" button to QR Code screen
8. Implement add device flow reuse (with localized labels)
9. Add unit tests
10. Verify all strings are properly internationalized and translated