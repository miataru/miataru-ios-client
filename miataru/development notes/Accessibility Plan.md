### Accessibility Plan for Miataru (VoiceOver, Switch Control, Keyboard)

This document defines a practical, phased plan to achieve comprehensive accessibility across Miataru on iPhone, iPad, and Mac (Catalyst). It focuses on VoiceOver, Switch Control, keyboard navigation, Dynamic Type, contrast, reduced motion/transparency, and robust testing.

## Goals
- Ensure all primary flows are fully operable with VoiceOver, Switch Control, and keyboard/AssistiveTouch.
- Provide clear, descriptive accessibility labels, hints, traits, and meaningful focus order.
- Respect user settings: Dynamic Type, Increase Contrast, Reduce Motion, Reduce Transparency.
- Deliver repeatable quality via Accessibility Inspector audits and UI tests with stable accessibility identifiers.

## Scope
- iPhone, iPad, and Mac Catalyst builds.
- Core app areas: Onboarding, Groups, Devices, Maps, Settings.
- Shared views and custom components.

## Principles
- Prefer semantic SwiftUI controls and system fonts/colors.
- Describe what actions do, not how to perform them.
- Hide decorative visuals from accessibility; label interactive elements.
- Use `NSLocalizedString` for ALL user-facing accessibility text (en/de/ja).
- Hit targets are at least 44 × 44 points.

## Phase 0 — Audit & Guidelines (short, in parallel)
1) Create project guidelines at `docs/AccessibilityGuide.md`:
   - Labeling and hint rules; when to use traits; when to hide elements
   - Focus order conventions, headings and rotor usage
   - Dynamic Type, color/contrast, reduced motion/transparency
   - Haptics fallback when Reduce Motion enabled
2) Build an audit checklist per view cluster: iPhone, iPad, Mac, Shared components.
3) Tooling: Xcode Accessibility Inspector, Dynamic Type previews, Contrast checker, VoiceOver shortcuts.
4) Localization: centralize accessibility string keys and provide English comments for translators.

## Phase 1 — Core Interactions (lists, toolbars, buttons)
- Add `.accessibilityLabel`, `.accessibilityHint`, and appropriate `.accessibilityAddTraits` to all interactive `Image(systemName:)` and toolbar items.
- Mark purely decorative elements as `.accessibilityHidden(true)`.
- Ensure consistent hit areas (≥ 44×44) across all tap targets.
- Introduce a reusable modifier:

```swift
import SwiftUI

struct AccessibleIcon: ViewModifier {
    let labelKey: String
    let hintKey: String?
    let traits: AccessibilityTraits

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(NSLocalizedString(labelKey, comment: "Accessibility label"))
            .accessibilityHint(hintKey.map { NSLocalizedString($0, comment: "Accessibility hint") } ?? "")
            .accessibilityAddTraits(traits)
    }
}

extension View {
    func accessibleIcon(labelKey: String, hintKey: String? = nil, traits: AccessibilityTraits = .isButton) -> some View {
        modifier(AccessibleIcon(labelKey: labelKey, hintKey: hintKey, traits: traits))
    }
}
```

## Phase 2 — Maps and Location Presentation
- Map annotations should expose meaningful information:
  - Label: device or group name
  - Value: last update time, distance, or status
  - Hint: what activation does (e.g., opens details) if not obvious
- Combine related subviews into a single accessibility element to simplify navigation.
- Hide decorative overlays like pulsing accuracy visuals at the point of use with `.accessibilityHidden(true)`.
- For legacy `MKMapView` representables, set accessibility on `MKAnnotationView` (label/traits) and ensure callouts are navigable.

## Phase 3 — Onboarding & QR
- Onboarding images (`yourlocationyourcontrol`, `mapandpin`, `locationhistory`, `qrcode`, `done`):
  - If essential: add concise, descriptive labels and optional hints.
  - If redundant decoration: use `.accessibilityHidden(true)`.
- QR code screens: describe the purpose (e.g., “Your device QR code for pairing”), and ensure Copy/Share buttons are clearly labeled with hints.

## Phase 4 — Settings, Groups, Devices
- Text fields (e.g., server URL): add `.accessibilityLabel`, `.accessibilityHint`, appropriate `submitLabel`, and ensure logical focus progression.
- Lists and rows: primary text as label; secondary information as `.accessibilityValue`. Provide `.accessibilityAction` names for swipe actions if needed.
- Toggles, pickers, color selectors: provide semantic labels and avoid color-only encoding of state.

## Phase 5 — System Preferences & Visual Support
- Dynamic Type: use system fonts; ensure no truncation/overlap at larger sizes (XL–XXXL). Apply line-wrapping and `minimumScaleFactor` conservatively.
- Contrast: use semantic colors; verify sufficient contrast in light/dark modes and with Increased Contrast.
- Reduce Motion/Transparency: respect `.accessibilityReduceMotion` and `.accessibilityReduceTransparency`; reduce animations and haptics when enabled.
- Headings and Rotor: mark section headers with `.accessibilityHeading(.h1/.h2)` and use `.accessibilitySortPriority` to fine-tune reading order where needed.

## Phase 6 — Testing & Quality Assurance
- Manual VoiceOver passes across onboarding, groups, devices, maps, and settings.
- UI tests based on accessibility identifiers (not labels) for stability.
- Accessibility Inspector audits: labels, contrast, and hit targets must pass with no errors.
- Test matrix: iPhone (multiple sizes), iPad (portrait/landscape), Mac Catalyst.

## Quick Wins (file pointers to prioritize)
- iPhone
  - `views/iPhone/iPhone_GroupsView.swift`: ensure all pencil/plus icons have labels and hints; unify naming.
  - `views/iPhone/iPhone_DevicesView.swift`: label and hint for `pencil` and `plus` buttons.
  - `views/iPhone/Devices Views/iPhone_DeviceMapView.swift` and `views/iPhone/Groups Views/iPhone_GroupMapView.swift`:
    - Provide annotation labels/values; hide decorative overlays at the integration point.
  - `views/iPhone/Onboarding/*`: add labels or hide images when purely decorative.
  - `views/iPhone/iPhone_MyDeviceQRCodeView.swift`: add clear labels/hints to copy/share confirmation icons.
- iPad
  - `views/iPad/iPad_GroupsView.swift`, `views/iPad/iPad_DevicesView.swift`: re-enable/standardize `.accessibilityLabel` on pencil icons; label plus/refresh.
  - `views/iPad/Devices Views/iPad_DeviceMapView.swift`, `views/iPad/Groups Views/iPad_GroupMapView.swift`: same map rules as iPhone.
- Shared
  - `views/Common/MapCompass.swift`: retain current label/value usage and apply consistently.
  - `views/Common/PulsingAccuracyCircle.swift`: hide at call sites; parent annotation carries the description.
  - `views/Common/MiataruMapMarker.swift`: add label/value/hint to `Image(systemName: iconName)` reflecting device name and state.

## Localization
- All accessibility strings must use `NSLocalizedString` with clear English comments.
- Add keys to `Localizable.xcstrings` and provide translations for en, de, ja.
- Key naming pattern: `context_action_description` (e.g., `grouplist_editbutton`, `map_marker_open_details`, `qr_copy_hint`).

## Definition of Done (Measurable)
- 0 unlabeled interactive elements (Inspector).
- VoiceOver flows have no dead-ends or irrelevant focus stops.
- 0 contrast warnings in light and dark modes.
- Dynamic Type at XL–XXXL shows no clipping/overlap; all content remains reachable.
- Reduce Motion: non-essential animations/haptics suppressed when enabled.
- Stable UI tests using accessibility identifiers.

## Tools & Verification
- Xcode Accessibility Inspector (labels, hit targets, contrast, traits).
- Color contrast checker; Dynamic Type previews; simulators with VoiceOver + real device spot checks.
- UI test assertions using accessibility identifiers.

## Next Steps
1) Complete Phase 0 (guidelines and audit matrix) in 0.5–1 day.
2) Implement Phases 1–2 (core interactions and maps) for the largest impact.
3) Address Phase 3–5 items, followed by a focused testing pass (Phase 6).
4) Keep guidelines updated; add accessibility to code review checklist as a required item.


