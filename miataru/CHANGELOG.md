version 3.1.4
- Extended `MiataruClientSwift` with typed support for `getDeviceSecurityStatus` (`MiataruGetDeviceSecurityStatus` request and `MiataruDeviceSecurityStatus` response model).
- Added `MiataruAPIClient.getDeviceSecurityStatus(...)` for authenticated security-status checks against `v1/getDeviceSecurityStatus`.
- Added app-level wrapper `MiataruAppAPI.getDeviceSecurityStatus(...)` so app callsites can use the centralized request executor and read retry policy.
- Updated `MiataruClientSwift` README with usage documentation and example code for `getDeviceSecurityStatus`.

version 3.1.3
- Added an opt-in unknown-visitor alert feature (`unknownVisitorAlertsEnabled`, default `off`) with a centralized notification permission flow that is reused by Settings and Onboarding.
- Added a new full-onboarding step `iPhone_9_OnboardingUnknownVisitorAlertsView` (shown only when location tracking is enabled) with feature explanation, example notification text, live toggle, denied-state hint, and app-settings shortcut.
- Integrated unknown-visitor evaluation after successful location delivery for both direct `submit(...).sent` and outbox flush paths.
- Added `UnknownVisitorAlertService` as a central alert engine with watermark-based incremental processing, own/known/ignored-device filtering, per-device 24-hour cooldown, and in-flight coalescing.
- Implemented start-at-enable behavior for alert evaluation (no retroactive notifications before activation timestamp).
- Implemented best-effort enrichment for notification text (device slogan + city), including resilient fallback message when enrichment data is unavailable.
- Added local notification foreground presentation handling through `UNUserNotificationCenterDelegate` so unknown-visitor alerts can appear with banner/list/sound while the app is active.
- Added complete localization coverage for all new unknown-visitor onboarding/settings/notification strings across all supported app languages (`da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`).
- Added unit tests for unknown-visitor evaluator logic (selection/filtering/cooldown) and permission-flow behavior, plus a localization completeness test for required keys/locales.

version 3.1.2
- Refined device history caching and refresh behavior: opening history now fetches fresh server data, active history views reuse cache only briefly, and in-view refresh is triggered when new device locations arrive (throttled), while empty server history clears local cache entries.
- Changed Edit Device ACL behavior to immediate server sync on toggle changes (no deferred ACL write on Save), removed the Cancel action, and renamed the primary action to localized "Close" (`close_button_label`).
- Added pulsing animation for the mutual-navigation indicator symbol in both route info overlays (top overlay and iOS 26 bottom accessory), gated by global animation allowance and the existing pulsing marker setting.
- Fixed missing route-info separator in the iOS 26 bottom navigation accessory when mutual navigation is active (`… ETA • [mutual symbol]`), using the localized `device_row_separator` consistently between all segments and before the mutual-navigation icon.
- Improved focused/double-tap navigation robustness by forcing route overlay re-instantiation on each route render update (including periodic refresh), reducing cases where the blue route line appeared truncated until app reactivation.
- Changed device-switch behavior in navigation to fetch route data with route-cache bypass for the initial recenter/update cycle, ensuring the displayed route is recalculated immediately for the newly selected device.
- Centralized Miataru API retry handling in app code (`MiataruRetryPolicy`, `MiataruRetryClassifier`, `MiataruRequestExecutor`, `MiataruAppAPI`) without modifying `MiataruClientSwift`.
- Migrated app-target Miataru callsites from direct `MiataruAPIClient` usage to `MiataruAppAPI` wrappers for uniform read/write retry behavior.
- Added persistent `updateLocation` outbox delivery pipeline (`LocationUpdateOutboxStore`, `LocationUpdateDeliveryCoordinator`) with FIFO queue, cap 500, TTL 24h, and dedupe by `Device+Timestamp+Latitude+Longitude`.
- Wired outbox flush triggers for app activation, network recovery, and periodic timer cadence while pending items exist.
- Replaced legacy custom ACL sync retry loop in `AllowedDeviceListManager` with centralized retry behavior via `MiataruAppAPI`.
- Added new unit tests for retry execution/classification, outbox persistence semantics, and delivery coordinator flush/queue behavior.
- Re-established route polyline rendering in focused double-tap navigation mode on a short cadence (~6s) to prevent occasional map overlay disappearance; this refresh re-renders the existing route and does not trigger additional `MKDirections` requests.
- Ensured focused double-tap navigation consistently suppresses ghost/progress visuals (including residual green progress segments) and renders only the base route plus optional mutual-navigation overlay.
- Changed widget intent `parameterSummary` to key-path form (`Summary { \.$device }`) and removed obsolete `"Show ${device}"` localization content to prevent stale string-catalog entries in `miataruWidgets/Localizable.xcstrings`.
- Removed deprecated `UIViewController.attemptRotationToDeviceOrientation()` usage from rotation-lock handling and relied on scene/controller orientation update APIs (`setNeedsUpdateOfSupportedInterfaceOrientations` + geometry updates) to keep iOS 16+ builds warning-free.
- Prioritized local on-device position updates in focused double-tap navigation by introducing an unfiltered raw location stream for immediate camera/overlay updates instead of waiting on sensitivity-filtered location acceptance.
- Fixed focused-navigation heading arrow update cadence by subscribing the navigation view to raw local location updates, reducing situations where the arrow appeared to follow stale/server-driven movement.
- Reduced heading-arrow jitter in simulator/low-quality heading scenarios by preferring smoothed heading values and only falling back to smoothed course data when compass accuracy is not reliable.
- Incremented iOS app build number (`CURRENT_PROJECT_VERSION`) from 7 to 8.
- Stabilized focused double-tap navigation camera framing so the own device marker remains visible in the lower screen area at low speed/standstill instead of drifting to or below the bottom edge.
- Reduced follow-camera look-ahead aggressiveness and made heading fallback logic more defensive in reversed navigation mode to avoid premature off-screen positioning before movement speed increases.
- Added arrival clock time to the active-navigation route info accessory (`… • <ETA> • <localized prefix>: <time>`), derived from remaining route duration.
- Added full localization for the arrival prefix across all supported app languages (`de`: `Ankunft`, `en`: `ETA`, plus da/es/fi/fr/it/ja/nl/zh-Hans).
- Replaced the textual mutual-navigation suffix in route overlays with a compact SF Symbol indicator (`person.line.dotted.person.fill`) while preserving the localized accessibility label (`mutual_navigation_active`).
- Fixed `scripts/test-screenshots.sh` selector parsing for `set -u` shells by making empty-array loops nounset-safe (`"${array[@]-}"`), preventing crashes like `selected_inputs[@]: unbound variable` when no `--test` selectors are passed.
- Repaired test build/scheme wiring so both `miataruTests` and `miataruUITests` are enabled and consistently runnable from CLI and Xcode.
- Stabilized UI-test integration by hardening launch behavior and test isolation for tab/navigation-driven flows.
- Migrated map/helper test files from `miataru.xcodeproj` root into active test target folders (`miataruTests` / `miataruUITests`) and updated project synchronization.
- Added and refined deterministic UI scenarios in `ExtendedUITests` for launch, add-device flow, QR action flow, and settings onboarding action reachability.
- Updated test documentation artifacts (`documentation/test-katalog.md`, `documentation/test-gap-matrix.md`) to reflect current active tests and coverage.
- Added macOS CLI test helper scripts under `scripts/` to run all tests, unit tests, or UI tests via `xcodebuild` with automatic iOS Simulator destination detection.
- Optimized standard navigation auto-route refresh for moving target devices: route recalculation now requires significant target movement **and** target off-route, reducing frequent MKDirections requests while the target remains on route.
- Extended `NavigationRouteRefreshPolicy` and unit-test coverage to include standard-mode target off-route gating, reverse-mode compatibility, and missing-coordinate guard cases.
- Incremented iOS app build number (`CURRENT_PROJECT_VERSION`) from 5 to 6.
- Added a new app behaviour toggle `Prevent screen rotation` (default `off`) directly below `Deactivate device lock`, including an explanatory text in settings.
- Implemented app-wide orientation locking: when `Prevent screen rotation` is enabled, the app keeps the current orientation and stops rotating UI on device rotation.
- Added full localization coverage for the new rotation-lock setting and explanation across all supported in-app languages and `Settings.bundle` language files.
- Updated `Settings.bundle/Root.plist` with the new `prevent_screen_rotation` preference key and default value.
- Updated project metadata by removing the default UI test template source files and adding a shared `miataru` scheme file.
- Added broad regression test coverage for map helpers, polyline geometry helpers, route ghost calculation, route-cache validation behavior, and route refresh policy edge cases.
- Added a basic UI launch sanity test and increased the iOS app build number (`CURRENT_PROJECT_VERSION`) from 4 to 5.
- Recorded additional workspace file references for new test source files used during test development.
- Restored device speed display in standard navigation mode (route from selected device to user device) by persisting fetched target speed in the navigation cache update path.
- Fixed UITest target-app binding in project settings (`TestTargetID`/`TEST_TARGET_NAME`) so UI tests no longer fail with missing `targetApplicationPath` and premature runner exit.
- Fixed auto route refresh in active navigation to recalculate when the tracked target device moved significantly, even if the local user stays on-route.
- Added `NavigationRouteRefreshPolicy` and dedicated unit tests to cover on-route target movement refresh behavior and guard conditions.
- Fixed `VisitorHistoryViewModelTests` main-thread publishing warnings by running tests on `@MainActor` and stabilizing test isolation/cleanup.
- Fixed timestamp-unit mismatches in visitor/mutual-navigation tests by consistently using millisecond timestamps expected by `MiataruVisitor.TimeStampDate`.
- Updated project build settings for current toolchain compatibility (`IPHONEOS_DEPLOYMENT_TARGET` 18.6 for app/tests and `CURRENT_PROJECT_VERSION` 3).
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
