# Mutual Navigation Bottom Accessory Separator Fix (2026-03-06)

## Problem
In the iOS 26 bottom navigation accessory, the mutual-navigation symbol was appended directly after the ETA segment.
The standard row separator used elsewhere in the same line was missing between ETA/arrival text and the mutual-navigation icon.

## Change
Updated the bottom accessory route-info rendering in:

- `miataru/miataru/views/Common/BottomAccessoryModifier.swift`

Implementation details:

- Added a localized reusable separator value based on `device_row_separator`.
- Replaced the hardcoded `" • "` joiner in `routeSummaryText()` with the localized separator.
- Inserted the same separator before `person.line.dotted.person.fill` when `isMutualNavigation` is active.
- Marked the visual separator before the symbol as `.accessibilityHidden(true)` to avoid redundant speech output.

## Expected Behavior
- Route-info segments remain visually consistent in the bottom accessory.
- Mutual-navigation state still appears as compact symbol, now separated like other segments.
- Screen-reader users keep the existing accessibility label for the mutual-navigation symbol.

## Verification
- Confirmed separator is now rendered before the mutual-navigation symbol in the bottom accessory.
- Confirmed `device_row_separator` is used consistently for route-info segment joining and symbol separation.
