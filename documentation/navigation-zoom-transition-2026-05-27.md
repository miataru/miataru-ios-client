# SwiftUI Zoom Navigation Transition

Miataru now uses SwiftUI's zoom navigation transition for the iPhone list-to-map flows where the user moves from a visible entity row into the matching detail map.

## Scope

- Device rows in the iPhone device list zoom into `iPhone_DeviceMapView`.
- Group rows in the iPhone device and group lists zoom into `iPhone_GroupMapView`.
- A shared `MiataruZoomTransitionSource` keeps device and group source identifiers typed and stable.

## Intentionally excluded

- Sheets keep the standard sheet presentation because add/edit/device-key flows are modal tasks, not spatial drill-downs from a persistent row.
- iPad device and group views use `NavigationSplitView` sidebar selection rather than stack pushes, so zoom transitions would conflict with the split-view interaction model.
- Map actions such as history and navigation are launched from annotations, action dialogs, or picker sheets where there is no single reliable source view.

## Verification

Verified with:

```sh
xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 16' build
```
