# iOS 15 Compatibility Path

This project keeps the current `miataru` target as the primary modern app path and adds a separate `miataru-iOS15` target for iOS/iPadOS 15 compatibility.

## Ownership

- Modern app work stays in `miataru/miataru`.
- iOS 15 UI and app lifecycle work stays in `miataru/miataruLegacy`.
- Shared non-UI behavior is pulled into the legacy target from an explicit project allowlist.
- Do not move modern SwiftUI views into the legacy target. In particular, keep `NavigationStack`, `NavigationSplitView`, modern SwiftUI `Map`, `ShareLink`, widget code, and AppIntents out of `miataru-iOS15`.

## Release Model

- The `miataru-iOS15` target uses `IPHONEOS_DEPLOYMENT_TARGET = 15.0`.
- Release builds use the same bundle identifier as the modern app: `com.miataru.ios`.
- The legacy target intentionally does not embed the `miataruWidgets` extension. Widgets remain an iOS 17+ capability of the modern app path.

## Feature Boundary

The legacy app targets core functionality only:

- onboarding and location permission entry
- location tracking/reporting settings
- server and device key settings
- device list, add/remove/edit, QR scan, QR display, and share
- group list, add/remove/edit, and group membership
- basic `MKMapView` maps for devices and groups

Modern visual polish, multiwindow behavior, widget configuration, AppIntents, and current SwiftUI MapKit features are out of scope for the legacy path.

## Backport Rule

When shared core behavior changes, build both schemes before merging:

```sh
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS' build
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru-iOS15 -destination 'generic/platform=iOS' build
```

If a modern feature needs iOS 16+ or iOS 17+ APIs, keep it inside the modern target or add a small compatibility facade. Avoid touching the legacy source tree unless the change is intentionally part of the iOS 15 app surface.
