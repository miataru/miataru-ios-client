# UI Animation and Transition Pass

This pass adds small, state-driven SwiftUI transitions to places where Miataru previously changed UI state abruptly.

## Goals

- Improve orientation during setup, device editing, visitor-history updates, and navigation-map state changes.
- Keep movement subtle and functional.
- Respect the existing `animationsAllowed` environment so animation is disabled when the app gates it off, such as Low Power Mode.

## Covered areas

- Onboarding pages now get a gentle page entry motion while preserving the native `TabView` page interaction.
- QR/My Device state changes crossfade the QR code, slogan content, loading affordances, and visitor-history states.
- Add/Edit Device forms animate validation warnings, slogan/security loading, ACL progress, and error rows.
- Visitor History crossfades loading, empty, error, and content states, and animates row-level known/ignored state changes.
- Device History Map uses a subtle marker/detail transition when selecting history entries.
- Device Navigation applies consistent transitions to the turn overlay, summary chrome, compass, and scale bar.
- Advanced Settings animates the frequent-background options that appear after enabling the feature.
- Allowed Device List status changes animate lock/progress/checkmark/error states.

## Verification

Verified with:

```sh
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 16' build
```
