# Mutual Navigation Indicator Symbol Update (2026-03-04)

## Problem
The mutual-navigation state was appended as localized text (`mutual_navigation_active`) inside compact route-info UI areas.
This made the line longer and visually heavier than necessary in top and bottom navigation overlays.

## Change
Replaced the textual suffix with an SF Symbol indicator in both affected views:

- `miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`
- `miataru/miataru/views/Common/BottomAccessoryModifier.swift`

Implementation details:

- Removed string concatenation (`" - \(NSLocalizedString(...))"`).
- Added conditional SF Symbol rendering when mutual navigation is active:
  - `Image(systemName: "person.line.dotted.person.fill")`
- Kept accessibility semantics by retaining:
  - `.accessibilityLabel(Text(NSLocalizedString("mutual_navigation_active", ...)))`

## Expected Behavior
- When mutual navigation is active, a compact people-connection symbol is shown instead of extra inline text.
- Screen-reader users still receive the localized mutual-navigation state announcement.
- Route info remains shorter and easier to scan in narrow UI contexts.

## Verification
- Confirmed both navigation overlays use `person.line.dotted.person.fill`.
- Confirmed `mutual_navigation_active` is still used as accessibility label on the symbol.
