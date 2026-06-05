version 3.2
- Added an opt-in Location Diagnostics log in Location Tracking Details with a persistent 1000-entry ring buffer, JSON export, rounded location values, and localized UI across all supported app languages.
- Added a one-time-per-build significant-change monitor re-arm on eligible fresh app/update starts, with visible skipped/attempted status and diagnostic checks for tracking, Always authorization, DeviceKey block state, and build repetition.
- Kept diagnostics logging cheap while disabled by short-circuiting append calls before diagnostic checks, contexts, and timestamps are built; the visible re-arm status remains available independently of diagnostics logging.
- Added the new two-stage Smart Frequent Background Updates policy. Stage 1 (`Smart frequent updates`) keeps standard significant-change background tracking active by default and temporarily starts frequent background updates only after movement above the configured speed threshold is detected.
- Kept Stage 2 (`Frequent background updates`) as the manual always-on/temporary frequent mode. Manual frequent mode is unlocked by Smart frequent updates and overrides Smart runtime decisions completely.
- Locked the Smart frequent toggle while manual frequent background mode is active, with localized explanatory text, so users cannot disable the prerequisite while the manual override is still running.
- Smart frequent mode-change notifications now request and respect notification permission before the setting is enabled, including a denied-state message with an app-settings shortcut.
- Shared frequent parameters now apply consistently to Smart frequent runtime and manual frequent mode, including movement distance, delayed server delivery, and visitor-history check intervals.
- Extended the frequent background movement threshold presets to include 10 m and 5 m while keeping the separate frequent/Smart movement threshold setting and the existing 100 m default.
- Persisted the last valid raw location as a fresh Smart frequent seed so Smart frequent runtime can activate from the first background update after relaunch when the derived movement is plausible.
- Hardened Core Location batch handling so `didUpdateLocations` processes all usable locations chronologically, updates Smart state and diagnostics per location, and submits accepted uploads sequentially through the delivery coordinator.
- Clarified 5 m and 10 m battery implications in localized Advanced Options copy and marked the compact `5m`/`10m` labels as non-translatable string-catalog literals.
- Renamed significant-change user-facing copy toward the battery-saving standard background mode and refreshed Location Tracking Details so Location Access Control sits directly below Device Access Control.
- Restyled the Background Status section to match the upper statistic rows and gave each background status row a distinct icon for scanability.
- Removed stale and newly extracted string-catalog entries from `Localizable.xcstrings` and added a regression check that keeps the app string catalog free of stale/new translation units.
- Preserved existing users with manual frequent background updates enabled by migrating them to the new two-stage model with both the Smart prerequisite and manual frequent mode enabled.
- Added Smart frequent configuration for speed threshold (2, 5, 10, 15, 20, 30 km/h), speed detection mode (Hybrid or GPS-only), and a shared inactivity window (5, 10, 15, 30 minutes).
- Smart frequent runtime now starts from significant-change callbacks, uses valid GPS speed first and derived distance/time speed in Hybrid mode, and stops frequent runtime after the shared inactivity window when no update or no relevant movement over the frequent distance filter occurs.
- Smart frequent activation is now guarded against confusing startup/update relaunches: the first background location in a fresh process seeds the movement reference instead of activating frequent runtime immediately, and implausible activation speeds above 200 km/h are ignored.
- Added optional Smart frequent mode-change notifications, defaulting off, for automatic Smart frequent activation and inactivity-based deactivation. Tapping those notifications opens Advanced Options like the other frequent-background notifications.
- Expanded Location Tracking Details with distinct background modes (`Significant-change`, `Smart waiting`, `Smart frequent active`, `Manual frequent active`), Smart diagnostics, and persisted location-update counters split by foreground/live, significant-change, Smart frequent, and manual frequent modes with a shared 24-hour reset.
- Added localized labels, explanatory text, notification text, Settings.bundle strings, and option values for all supported locales.
- Added regression coverage for Smart defaults, migration, Settings.bundle parity, localization completeness, speed detection, activation/deactivation policy, manual override behavior, 24-hour mode counters, and Smart mode-change notification scheduling.
- Added regression coverage for persisted Smart frequent seeding, 5 m/10 m movement threshold normalization, Settings.bundle parity, and chronological multi-location callback processing.
- Updated the living project documentation, App Store copy source, test catalog/gap matrix, and added dated Smart frequent background updates implementation notes.
- Updated project metadata for version 3.2 build 4.

version 3.1.19
- Added 2-hour and 3-hour auto-disable options for frequent background updates in Advanced Options and the iOS Settings.bundle, keeping 4 hours as the default.
- Localized the new 3-hour picker label and the 2-hour/3-hour duration explanations across all supported app locales.
- Added regression coverage for the new frequent-background duration normalization, expiration dates, and localization/settings-bundle parity.
- implemented Logger based debug logging for local app debugging
- Updated project metadata for version 3.1.19 build 1.

version 3.1.18
- Restored reboot-safe background location tracking after real-device testing showed that frequent background mode could prevent Miataru from receiving any post-reboot location wakeups.
- Made the primary `CLLocationManager` the durable significant-change/reboot anchor for every active `Always`-authorized tracking mode, including foreground, standard background, and frequent background operation.
- Moved frequent background `startUpdatingLocation()` work onto a separate Core Location manager so high-frequency background updates can run without displacing the primary significant-change relaunch registration.
- Added a `CLBackgroundActivitySession`/`CLServiceSession` runtime anchor while frequent background mode is active, reducing burst-only delivery when iOS would otherwise suspend standard background location updates between significant-change wakeups.
- Cleaned up stale secondary frequent-manager callbacks if they arrive after frequent background mode has already been disabled, while still allowing the first valid stale callback location to pass through the normal deduped upload path and suppressing repeated stale callbacks after cleanup.
- Reasserted standard significant-change monitoring after background primary callbacks, so the post-reboot significant-change path does not rely only on the launch-time reconstruction.
- Kept an Always `CLServiceSession` for every active Always-authorized tracking mode, including standard significant-change tracking, so post-reboot background tracking has an explicit Core Location service context beyond the first relaunch.
- Preserved the stable post-reboot behavior for frequent mode: after a reboot, Miataru resumes reporting via significant-change updates without a manual launch; the saved frequent mode resumes when the app is started normally again.
- Kept standard significant-change tracking functional across foreground/background transitions and iPhone reboots, while maintaining duplicate-upload suppression for callbacks from parallel location services.
- Added regression coverage for the primary-recovery-anchor/secondary-frequent-update command plan.
- Updated project metadata for version 3.1.18 build 3.

version 3.1.17
- Added SwiftUI zoom navigation transitions for iPhone device and group pushes from the list rows into the matching map detail views.
- Kept the onboarding wizard on the native page transition and removed the broader helper-driven state animations from forms, visitor history, QR, settings, and navigation chrome so motion stays focused on navigation context.
- Updated project metadata for version 3.1.17 build 2.
- Kept unknown-device action dialog localization keys visible to String Catalog extraction by replacing dynamic lookup with explicit localized string references.
- Blocked case-insensitive duplicate Device IDs while keeping the original stored casing visible.
- Added a localized duplicate-name warning in Add/Edit Device and showed a shortened Device ID in device-list rows when names or legacy Device ID conflicts would otherwise be ambiguous.
- Added localized duplicate/conflict strings across all supported app languages.
- Preserved lowercase and mixed-case Device IDs when adding unknown devices from unknown visitors, unknown-device actions, QR scanner input, or external `miataru://` links.
- Split Device ID handling so visible/add-device flows only trim whitespace while internal matching can still use uppercase normalization for case-insensitive known-device resolution and cache keys.
- Added regression coverage for case-preserving URI/scanner parsing, case-preserving unknown-device add requests, and continued case-insensitive known-device routing.
- Hardened reboot-safe background tracking after real-device testing showed that frequent background mode could still lose all updates after an iPhone restart.
- Moved Core Location location-launch recovery into `application(_:willFinishLaunchingWithOptions:)` with a dedupe guard for `didFinishLaunchingWithOptions`, so Miataru reconstructs tracking as early as possible when iOS relaunches it for location.
- Added a short background-task wrapper around background location uploads so a location callback received after reboot or background relaunch has protected time to reach the Miataru server before suspension.
- Tightened the tracking resolver so background tracking requires `Always` location authorization; `When In Use` remains foreground-only instead of presenting a misleading background/reboot-capable tracking state.
- Kept the significant-change recovery anchor on its dedicated Core Location manager while frequent background updates use standard background location updates on the primary manager.
- Added regression coverage for the `When In Use` foreground/background split and documented the remaining iOS boundaries around force-quit, missing `Always` permission, and real-device reboot validation.
- Updated project metadata for version 3.1.17.

version 3.1.16
- Opened the unknown-device action sheet at its large detent by default so the Add/Ignore buttons are visible immediately when adding from unknown visitors or notification flows.
- Made background location tracking reboot-resilient by keeping significant-change monitoring active as a sparse recovery anchor whenever user-enabled tracking has `Always` authorization and DeviceKey authentication is not blocking updates.
- Frequent background updates now run alongside the significant-change recovery anchor instead of replacing it, so iOS can relaunch Miataru after system termination or reboot on the next significant location change.
- Added launch recovery for Core Location starts and normal app starts, reconstructing tracking mode from settings, authorization, frequent-mode expiration, battery auto-disable, and DeviceKey auth state.
- Frequent-mode expiration and low-battery auto-disable now only disable the frequent/high-accuracy portion and fall back to standard significant-change tracking.
- Background lifecycle transitions now force the background tracking policy immediately, and the significant-change recovery anchor now uses a dedicated `CLLocationManager` so frequent background updates can run through standard location updates without being displaced by the recovery anchor.
- Added upload deduplication for parallel location callbacks so frequent and significant-change services do not submit the same location twice.
- Added regression coverage for recovery-anchor eligibility, launch recovery gating, location-launch detection, background lifecycle mode selection, and duplicate callback suppression.
- Updated project metadata for version 3.1.16.

version 3.1.15
- Reworked the unknown-device workflow so tapping an unknown visitor row, tapping its options button, or opening an unknown-visitor notification presents the same explanatory action sheet.
- The unknown-device sheet now shows the known device details from the visitor row, including device ID, cached info/slogan, cached location, and visit time when available.
- Clarified the localized unknown-device copy across all app languages, including that the current position has not yet been shared, that adding allows access selection, and that ignored devices receive no position data.
- Locked the Device ID field when adding an unknown visitor from the Devices tab, QR-tab visitor history, standalone visitor history, or unknown-visitor notification flow, while keeping normal Add Device and unknown deep-link prefills editable.
- Hid QR scanning from the locked unknown-visitor Add Device flow and left the prefilled Device ID visible as read-only context.
- Centralized `miataru://<DeviceID>` parsing and routing so existing QR codes, in-app scanner input, and external Camera-app links keep working while known devices open directly and unknown devices open the add-device flow.
- Added regression coverage for URI compatibility, case-insensitive known-device resolution, known-vs-unknown routing, unknown-visitor notification branching, and Add Device request source preservation.
- Documented the locked unknown-visitor Add Device flow and its separation from normal Add Device/deep-link behavior.
- Updated project metadata for version 3.1.15.

version 3.1.14
- Updated the living project documentation, documentation index/audit, App Store copy source, local API-client README, and third-party license summary to match the current 3.1.14 project state.
- Stabilized navigation route-progress ghost rendering by storing explicit ghost snapshots, forcing map progress redraws through a render revision, and giving user/device/ghost annotations stable internal identities.
- Serialized navigation auto-update work so overlapping target-location fetches and stale `MKDirections` responses can no longer overwrite newer route or ghost state after screen, device, or direction changes.
- Clarified route-ghost direction handling so standard `device -> user` progress uses device speed/timestamp, reverse `user -> device` progress uses user speed/timestamp, and cached routes use fresh route seed time for ghost visibility.
- Hardened route-ghost distance handling by using polyline geometry length when splitting completed/remaining route progress, avoiding failures from small `MKRoute.distance` versus polyline discrepancies.
- Added route-ghost regression coverage for monotonic tick progress, direction-specific speed/timestamp use, cached-route visibility, and route-distance/polyline-length mismatches.
- Documented the route-ghost update logic, reasoning, concurrency implications, and focused validation workflow.
- Hid live map-marker speed labels once the marker location is older than five minutes, while keeping device history speed details time-independent.
- Added regression coverage for live marker speed freshness, the five-minute boundary, future timestamps, and unchanged history speed formatting.
- Fixed configurable widgets so selecting a different device now drives the rendered text and map content through the selected device ID instead of falling back to a previously cached widget device.
- Split widget device selections from cached widget location entries, keeping all known devices selectable in store order even when some devices do not yet have cached widget location data.
- Normalized known-device ordering after load, add, move, and removal operations, and routed iPhone device reordering through the store so widget sync receives the persisted order.
- Added regression coverage and technical documentation for the widget device-selection flow.
- Restricted unknown-visitor alert enrichment to true unknown visitor candidates so known, allowed, ignored, and own devices no longer trigger supplemental `GetLocation` requests during visitor-history processing.
- Batched alert supplemental lookups per visitor-history processing run and reused cached city/slogan data when available, avoiding per-device enrichment requests when possible.
- Shared the same normalized unknown-visitor filtering logic between iPhone and iPad device lists so already known or ignored visitor IDs are consistently excluded.
- Added regression coverage for known/allowed visitor filtering, supplemental lookup scoping, ID normalization, and shared unknown-visitor list filtering.
- Documented the visitor-history-only enrichment flow and its separation from normal location-update delivery.
- Added startup and post-device-removal cleanup for app-owned persistent data, pruning orphaned widget snapshots, stale unknown location cache entries, and stale unknown slogan cache entries.
- Moved widget map snapshots into the App Group `Library/Caches/WidgetSnapshots` directory and removed legacy root-level snapshot files and atomic-write leftovers during cleanup.
- Switched the Miataru API client to a non-disk-caching ephemeral `URLSession` for POST JSON requests.
- Added regression coverage and technical documentation for persistent app-data cleanup behavior.
- Updated project metadata for version 3.1.14.

version 3.1.13
- Fixed visitor-history freshness on the current-device tab so recent visitors are refreshed immediately when the tab opens instead of waiting for the next automatic or manual reload.
- Improved the location-permission escalation flow so choosing `When In Use` can still trigger the follow-up `Always` request during tracking setup.
- Added a localized `Request Location Permission Again` action in Location Tracking Details to restart the full location authorization flow after limited or changed iOS permission choices.
- Removed the persistent one-time lockout around `Always` authorization requests and replaced it with current-session gating plus modern authorization-change handling.
- Made onboarding DeviceKey setup sheets close automatically shortly after a successful DeviceKey create/restore/reset result, while leaving normal settings DeviceKey sheets unchanged.
- Updated project metadata for version 3.1.13.

version 3.1.12
- Centralized successful `GetLocation` response ingestion so device-location cache, slogan cache, widget payloads, and device-list rows reuse already fetched server data consistently.
- Hardened device-location cache writes with timestamp ordering so older app, history, widget, or background responses can no longer overwrite newer location data.
- Reused latest `GetLocationHistory` entries to improve cached battery, altitude, speed, timestamp, and placemark freshness without adding new server requests.
- Reused visitor-history responses from refreshers, visitor-history views, mutual-navigation checks, and unknown-visitor alerts to update the recent-visitor indicator more quickly.
- Preserved newer widget App Group locations when the app syncs widget data and imported newer widget-written locations into the app cache on startup and foreground activation.
- Removed redundant per-view cache update loops from iPhone/iPad device maps, group maps, navigation, and device-list fallback paths in favor of the central ingest path.
- Added regression coverage for timestamp ordering, opt-in missing-device removal, history promotion, and recent-visitor normalization.
- Added the missing localized `frequent_background_location_updates_central_explanation` string across all supported app locales and wired the central Settings toggle to use it.
- Updated project metadata for version 3.1.12.

version 3.1.11
- Centralized location tracking mode selection in `LocationManager`, making foreground high-accuracy, standard significant-change background tracking, and opt-in frequent background updates resolve through one path.
- Focused Turn-by-turn navigation now registers an explicit location session and cleans it up when navigation is disabled, auto-stopped, direction-switched, or the navigation view disappears.
- App backgrounding now always applies the configured background policy, even while a navigation session is active; returning to the foreground reapplies high-accuracy tracking.
- Fixed the legacy foreground lifecycle hook so it no longer stops location tracking when the app enters the foreground.
- Added regression coverage for foreground/background/navigation tracking-mode resolution.
- Documented the location tracking mode resolver behavior.
- Updated project metadata for version 3.1.11.

version 3.1.10
- Removed the duplicate collapsed-sidebar restore button on iPad by relying on the native `NavigationSplitView` restore control instead of drawing an additional custom overlay.
- Updated project metadata for version 3.1.10.

version 3.1.9
- Fixed the iPad Devices and Groups sidebars so their custom header no longer leaves the large system navigation gap above the first list section.
- Restored the iPad sidebar hide/show workflow with a sidebar button in the list header while relying on the native collapsed-sidebar restore control.
- Restored the full-bleed iPad map layout so the map again extends behind the status/title area instead of showing a white strip at the top.
- Kept the frequent-background-updates notice conditional on the mode being active; on iPad it now appears inside the existing Devices section so inactive mode keeps the same spacing.
- Localized the new sidebar accessibility labels and hints across the supported in-app languages.
- Updated project metadata for version 3.1.9.

version 3.1.8
- Moved the central frequent-background-updates toggle below the Tracking & Security settings section and now shows it whenever location tracking is enabled, so users can enable the mode directly from standard tracking.
- Added a configurable low-battery auto-disable threshold for frequent background updates in Advanced Options, defaulting to 30% and available as 10%, 20%, 30%, 40%, or 50%.
- When the selected battery threshold is reached, Miataru now automatically disables frequent background updates, cancels the related reminder/expiration timers, returns to standard significant-change background tracking, and sends a localized explanatory notification.
- Localized the new setting, Settings.bundle entry, explanatory text, and low-battery notification across all supported app languages.
- Formatted user-facing percentages in code with NumberFormatter-backed localized strings so the string catalog no longer contains hard-coded percentage values.
- Added regression coverage for setting defaults and normalization, low-battery auto-disable decisions, notification cleanup, and localized key coverage.
- Updated project metadata for version 3.1.8.

version 3.1.7
- Fixed device-map marker selection on iPhone and iPad so the nearby-device picker now considers the marker distance on screen at the current zoom level, not only a fixed physical distance in meters. This makes the picker appear reliably when devices look close together or overlap on the map.
- Added a separated, tappable device-list notice while frequent background updates are active; it opens Advanced Options directly and shows the expiration time when the mode is configured to end automatically.
- Added an opt-in frequent background location-update mode in Advanced Options, keeping significant-change monitoring as the unchanged default when the user does not enable it.
- Added configurable frequent-background distance presets (100 m default, 50 m, 25 m) and auto-disable durations (1 hour, 4 hours default, 12 hours, 24 hours, never), with automatic fallback to significant-change monitoring after expiry.
- Added frequent-background delivery options so updates can keep sending immediately by default or be queued locally and flushed together after 30 seconds, 1 minute, 5 minutes, or 10 minutes.
- Added configurable visitor-history check intervals for frequent background mode, defaulting to 10 minutes so visitor checks no longer have to run after every background location upload.
- Added a repeating local reminder notification for the never-expiring frequent background mode; tapping it opens the Advanced Options page where the mode can be turned off.
- Added a local notification for finite frequent-background durations so users are informed when Miataru automatically returns to the standard background update mode.
- Added localized per-option explanations for frequent background movement threshold, auto-disable duration, server-delivery mode, and visitor-check interval choices.
- Added localized red battery-usage warning text while frequent background updates are enabled, plus background-mode/expiry visibility in the location-status view.
- Added a prominent central Settings toggle while frequent background updates are active, making the battery impact visible and allowing the mode to be turned off without opening Advanced Options.
- Preserved frequent-background update settings during DeviceKey recovery/reset flows and added regression coverage for defaults, localization parity, value normalization, expiry behavior, and default significant-change configuration.
- Incremented iOS app build number (`CURRENT_PROJECT_VERSION`) from 1 to 2.
- Fixed offline `UpdateLocation` delivery so new updates are queued behind already pending outbox items and retried in FIFO order without replacing the original event payload metadata.
- Added a location-status statistic for queued location updates that still need to be sent.
- Added Advanced Options controls for the unsent location-update queue retention and capacity, keeping the default at 24 hours / 500 updates while allowing longer retention, unlimited retention, and higher caps.
- Added a confirmation step when changing the Miataru server URL while location updates are queued, allowing the user to send queued updates to the new server or discard them.
- Improved queued-update draining so active tracking schedules near-term FIFO flushes, full batches continue automatically, and the location-status view can manually flush all currently deliverable queued updates.
- Hardened queued-update server URL retargeting so already queued items are consistently rewritten to the chosen new server and in-flight old-URL sends cannot remove retargeted queue records.
- Added regression coverage for queued-update ordering, configurable outbox policy changes, server URL retargeting, full queue flushes, and settings/localization parity.
- Added visible loading feedback when opening a device's location history on iPhone and iPad, including the selected device name/ID while history data is being preloaded.
- Prevented the history map from briefly showing the "no location history" fallback before cached or freshly loaded history entries have been applied.
- Improved history-load error handling so invalid configuration, server/response failures, encoding/decoding failures, network failures, and unknown failures produce readable user-facing messages.
- Added full localization coverage for the new history loading text across all supported app languages.
- Made common error overlays wrap long messages more reliably and kept history preload errors visible longer.
- Kept manual pan/zoom interaction on the device history map authoritative during live history refreshes, so newly recorded positions no longer force the map to refit after the user has adjusted the camera.
- Stopped history-map item taps from automatically recentering the map; tapping a point now only selects it and preserves the current camera.
- Added an expanded detail bubble for selected history points, including the initially selected item when the history map opens, showing available timestamp, coordinates, accuracy, speed, altitude, and battery information directly at the item.

version 3.1.5
- Refactored the iOS settings flow: centralized runtime defaults and one-time existing-install migrations, shortened the root settings screen, added a dedicated `Advanced Options` page, and moved ACL/status content to the intended destinations.
- Synchronized settings defaults, labels, picker options, and explanatory copy across `Localizable.xcstrings` and all supported `Settings.bundle` locales.
- Added regression coverage for settings defaults, settings localization completeness, `Settings.bundle` parity, and the advanced-options navigation path, with updated test documentation.
- Fixed device-slogan editing so normal spaces remain typeable while final save cleansing still trims outer whitespace and removes control characters.
- Changed the device-slogan fetch strategy: `Add Device` and `Edit Device` use `getDeviceSlogan`, unknown devices in the iPhone/iPad device lists only fetch missing slogans individually after the normal `getLocation` refresh, and all other slogan reads continue to rely on `getLocation`.

version 3.1.4
- Extended `MiataruClientSwift` with typed support for `getAllowedDeviceList` (`MiataruGetAllowedDeviceList` request and `MiataruAllowedDeviceList` response model).
- Added `MiataruAPIClient.getAllowedDeviceList(...)` for authenticated owner reads against `v1/getAllowedDeviceList`.
- Updated `MiataruClientSwift` README with usage documentation and example code for `getAllowedDeviceList`.
- Fixed intermittent Devices-list refresh flicker where rows briefly dropped all supplemental information and showed only the device name during active polling.
- Coalesced overlapping device-list refresh requests into a single in-flight fetch and now apply refreshed device-location cache data as one consolidated snapshot instead of publishing per-device partial states.
- Kept the last successful device-location cache visible on transient refresh failures, avoiding the short-lived blank/half-empty list state during network hiccups.
- Fixed standard navigation summary countdown on iPhone and iPad so ETA/distance no longer jump from the initially correct route values to `0 km / 0 min` right after route calculation.
- Standard `device -> user` navigation now seeds live summary updates from the moment the active route is applied (including cached routes), instead of reusing potentially stale device sample timestamps.
- Added centralized device-slogan cleansing before every `setDeviceSlogan` request (remove control characters, trim outer whitespace, enforce max length 40) so invalid special/control characters are not sent to the server.
- Replaced raw server error text in slogan-save UI with a user-friendly localized fallback message ("Beim Setzen des Device Slogans ist etwas schief gelaufen. Probier es später noch einmal.") across all supported app languages.
- Added optional slogan rendering in the Devices tab list rows (iPhone + iPad): when a device slogan exists, it is shown directly below the device name.
- Matched device-list slogan styling to Visitor History by using secondary text color for a consistent, slightly darker subtitle appearance.
- Extended reversed-route live summary updates to normal (non-double-tap) navigation mode, so ETA/distance/arrival stay continuously in sync outside focused mode as well.
- Simplified navigation duration formatting to hour+minute granularity only (removed seconds) for more compact route info on smaller devices.
- Simplified the iOS 26 bottom accessory arrival segment to show only the arrival clock time, removing the localized `ETA:`/`Ankunft:` prefix.
- Extended `MiataruClientSwift` with typed support for `getDeviceSecurityStatus` (`MiataruGetDeviceSecurityStatus` request and `MiataruDeviceSecurityStatus` response model).
- Added `MiataruAPIClient.getDeviceSecurityStatus(...)` for authenticated security-status checks against `v1/getDeviceSecurityStatus`.
- Added app-level wrapper `MiataruAppAPI.getDeviceSecurityStatus(...)` so app callsites can use the centralized request executor and read retry policy.
- Updated `MiataruClientSwift` README with usage documentation and example code for `getDeviceSecurityStatus`.
- Added a new first security-status row in Edit Device `Access Permissions` that loads on open via `getDeviceSecurityStatus` and shows DeviceKey + ACL status text with symbols.
- Added status color coding in that row: active (`green`), inactive (`red`), unknown/loading (`secondary`) with unknown fallback on missing credentials or API/auth/network errors.
- Added full localization coverage for the new Edit Device security-status texts across all supported app languages (`da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`).

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
