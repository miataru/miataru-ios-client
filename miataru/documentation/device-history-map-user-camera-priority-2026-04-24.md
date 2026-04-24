# Device History Map User Camera Priority

## Problem

The device history view refreshes its history data while it is open. For the owner's own device this can happen during movement: a new location enters the shared location cache, the history view fetches fresh server history, and `viewModel.history` publishes the updated entries.

Before this change, every history publication called `updateRegion(animated: false)`. That was correct for the initial view setup, but wrong after manual map interaction: if the user had panned or zoomed the history map, the next live refresh immediately refit the camera around the visible history points.

## Change

`iPhone_DeviceHistoryMapView` now tracks whether the user has adjusted the map camera by observing non-suppressed center or zoom changes from `onMapCameraChange`.

History reloads still update the timeline, annotations, and route polyline, but automatic region fitting now goes through `updateRegionIfUserCameraAllows(animated:)`. Once the user has panned or zoomed, live history refreshes no longer override the current camera.

Programmatic camera updates keep using the existing suppression window so the initial fit, playback focus, and other explicit camera moves do not mark the map as manually adjusted.

Quick range selection resets the manual-camera flag because selecting a new range is an explicit request to refit the visible history slice.

## Verification

Built successfully with:

```sh
xcodebuild -project miataru.xcodeproj -scheme miataru -destination 'generic/platform=iOS Simulator' build
```
