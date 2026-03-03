# Rotation Lock Deprecation Fix (2026-03-03)

## Problem
`miataruApp.swift` used `UIViewController.attemptRotationToDeviceOrientation()`, which is deprecated since iOS 16.

## Root Cause
The rotation lock flow already updated supported interface orientations on root view controllers and, on iOS 16+, requested scene geometry updates.  
The additional deprecated global rotation trigger remained from older rotation handling.

## Change
File: `miataru/miataru/miataruApp.swift`

- Removed `UIViewController.attemptRotationToDeviceOrientation()` from `RotationLockController.setRotationLockEnabled(_:)`.
- Kept modern orientation update path:
  - `setNeedsUpdateOfSupportedInterfaceOrientations()` on root view controllers
  - `UIWindowScene.requestGeometryUpdate(...)` on iOS 16+

## Expected Behavior
- No deprecation warning for `attemptRotationToDeviceOrientation`.
- Rotation lock behavior remains unchanged for users.

## Verification
- Build check:
  - `xcodebuild -project /Users/bietiekay/code/miataru-ios-app/miataru/miataru.xcodeproj -scheme miataru -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - Result: `BUILD SUCCEEDED`
