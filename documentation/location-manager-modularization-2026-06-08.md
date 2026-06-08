# LocationManager Modularization - 2026-06-08

## Intent

This refactor reduces the size and responsibility of `LocationManager.swift` without changing the app-facing API, `UserDefaults` keys, notification names, or runtime behavior. `LocationManager.shared`, published UI state, permission entry points, lifecycle hooks, tracking start/stop methods, navigation location sessions, and Core Location delegate glue remain on the facade.

The first modularization pass extracted pure decisions into policy types and small stateful helpers. This follow-up pass moves low-risk facade-only declarations, persisted background-forensics recording, and Core Location service orchestration out of the main facade file.

## Current Boundaries

- `LocationManager.swift` remains the ObservableObject facade. It coordinates published state, app lifecycle, Smart frequent runtime callbacks, upload decisions, and delegate entry points.
- `LocationManager+Types.swift` keeps UI-facing nested types, constants, and typealiases available under `LocationManager` so views and tests do not need broad call-site churn.
- `LocationManager+PolicyCompatibility.swift` keeps the existing static policy wrapper functions available while newer code and tests can call the extracted policy types directly.
- `LocationTrackingPolicy`, `SmartFrequentBackgroundPolicy`, `LocationSamplePolicy`, and `LocationBackgroundForensics` own behavior decisions that are deterministic and easy to unit test.
- `LocationBackgroundForensicsRecorder` owns persisted forensic state, significant-change re-arm status, background-gap logging, foreground-recovery burst logging, Smart activation/deactivation timestamps, and the related `UserDefaults` keys.
- `CoreLocationServiceController` owns the primary and frequent `CLLocationManager` instances, shared activity type configuration, background indicator sync, `CLServiceSession`, `CLBackgroundActivitySession`, significant-change recovery-anchor state, frequent standard-update state, and stale frequent-callback cleanup.
- `LocationUpdateUploadService`, `LocationUpdateMetricsStore`, and `HeadingSmoother` continue to own upload payload/background-task handling, 24-hour counter persistence, and heading/course smoothing.

## Compatibility

The refactor intentionally preserves:

- `LocationManager.shared`
- public and `@Published` properties used by SwiftUI
- nested names such as `LocationManager.ServerUpdateStatus`, `LocationManager.UpdateLogEntry`, and `LocationManager.BackgroundTrackingDisplayMode`
- static policy wrapper methods used by existing tests and call sites
- `UserDefaults` keys used for Smart frequent seeds, metrics, diagnostics, forensics, and significant-change re-arm status
- notification names and app lifecycle entry points

## Deferred Work

`SmartFrequentRuntimeController` remains a good future extraction, but it should be a separate change. The runtime still touches published diagnostics, timers, notifications, movement anchors, frequent callbacks, and tracking-mode application. Moving it after the Core Location controller split keeps this change behavior-preserving and easier to validate.

The Core Location delegate methods can also become thinner later, but a mechanical extension split would require widening too many private members. The preferred next step is to extract processing seams that own location callback decisions before moving delegate code by file.

## Validation

Validation run for this modularization:

```bash
xcodebuild build -project miataru/miataru.xcodeproj -scheme miataru -destination 'id=9701FE64-5BE0-4377-8E82-14C43F80E6C9'
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'id=9701FE64-5BE0-4377-8E82-14C43F80E6C9' -only-testing:miataruTests/LocationTrackingPolicyTests -only-testing:miataruTests/SmartFrequentBackgroundPolicyTests -only-testing:miataruTests/LocationSamplePolicyTests -only-testing:miataruTests/LocationBackgroundForensicsTests -only-testing:miataruTests/LocationUpdateMetricsStoreTests
xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'id=9701FE64-5BE0-4377-8E82-14C43F80E6C9' -only-testing:miataruTests
```

The full `miataruTests` suite passed with 186 tests.
