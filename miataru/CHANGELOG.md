version 3.1.2
- Changed location-tracking statistics counters from rolling 24-hour windows to "today" (since local midnight) with daily reset semantics.
- Replaced per-request timestamp storage with compact persisted daily counters for API and widget statistics, including migration from legacy timestamp data.
- Updated location-tracking statistics labels and translations across supported languages from "last 24 hours" to "today".
- Incremented iOS app build number (`CURRENT_PROJECT_VERSION`) from 1 to 2.
- Fixed focused double-tap navigation rendering so temporary route recalculation failures no longer clear the currently visible route.
- Added speed-aware minimum camera distance in focused navigation mode to prevent over-zooming at higher travel speeds.
- Improved focused navigation camera framing by shifting the camera center forward in travel direction so more route ahead remains visible.
- Stabilized programmatic follow-camera updates to avoid unintended disabling of auto-zoom during animated camera transitions.

version 3.1.1
- Fixed navigation refresh after app background/foreground transitions so route, ETA, and distance update without manually restarting navigation.
- Stabilized route rendering during mutual-navigation state changes by using a dedicated overlay polyline copy to prevent temporary truncation/flicker in focused reversed navigation mode.

version 3.1
- Stabilized full-screen focused navigation mode (double-tap) to always render the route reliably, including during mutual-navigation state changes.
- Disabled route ghost/progress segmentation in focused navigation mode and render only the base route plus mutual-navigation overlay when active.
- Added continuous ETA and distance updates in focused navigation mode based on remaining distance along the currently active route polyline.
- Ensured ETA/distance recalculation immediately follows route refreshes (newly calculated or cached routes), so bottom overlay values stay in sync with the latest route.

version 3.0
- Fixed `MiataruAPIClient` error propagation so API/request failures are no longer reclassified as `encodingError` in the generic `Encodable` POST helper.
- Suppressed user-facing overlays for technical request-encoding failures in map/history fetch flows and logged them as debug diagnostics instead.
- Documented retry guidance for transient network failures (timeouts/connection-loss) and explicitly excluded retries for encoding/decoding/auth errors.
- Extended Cursor rules: added changelog-on-commit rule and memory so CHANGELOG.md is updated at the top with the main app marketing version when committing, with a short summary of changes.
- Extended GetLocation and GetLocationHistory requests to send the requesting device key (`RequestMiataruDeviceKey`) from app and widgets, enabling server-side deviceID/deviceKey validation.
- Extended `MiataruClientSwift` for the new Device Slogan API (`setDeviceSlogan` / `getDeviceSlogan`) with typed request and response models.
- Added device info text support across My Device, Add Device, Edit Device, Visitor History, and Unknown Visitors with cached/fresh server sync for slogan and location updates on refresh intervals.
- Updated device info labeling from “Slogan/Device Slogan” to concise “Info” in add/edit flows and completed localization coverage, including the “Max 40 characters” helper text.
- Fixed remaining slogan localization gaps by replacing the hardcoded “Tap to set a slogan” hint and aligning invalid-server error messages to localized string keys in My Device and Edit Device flows.

version 2.9
- Added DeviceKey authentication and key management with generate, reset and restore
- Added a separate update interval for any non-map device refreshes in settings.
- Added an optional toggle to show current device speed above map markers.
- Added subtle sound cues and haptic feedback when mutual navigation activates or deactivates.
- Added a navigation instruction overlay when routing from the current device to a selected device.
- Added a one-time post-update onboarding (Welcome, Device Key, Done)
- New DeviceKey onboarding step when location tracking is enabled.
- Some Onboarding steps are ownly shown when  when location tracking is enabled.
- Moved the iPhone groups list below devices with an inline add button.
- Auto-refreshing the visitor history list
- Fixed route progress ghost and segmentation to follow the active navigation direction.
- Disabled shimmer, pulsing, and UI animations while Low Power Mode is enabled.
