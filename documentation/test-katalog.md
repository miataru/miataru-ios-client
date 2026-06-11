# Test Catalog (as of 2026-06-10)

## 1) Scope and Classification

This catalog is split into four blocks:

1. **Actively linked app tests** (`miataruTests` + `miataruUITests` + `miataruScreenshotUITests`)
2. **Scheme-categorized test execution** (`miataru-FunctionalUI` and `miataru-Screenshots`)
3. **Historically extracted test files** (formerly under `miataru.xcodeproj/*.swift`, now linked)
4. **Third-party test inventory** under `miataru/Libraries/*` (inventory only, not fully cataloged)

Important project observations:

- `miataruTests` is linked as a `PBXFileSystemSynchronizedRootGroup` (`miataruTests` folder is automatically used as source for the unit test target).
- `miataruUITests` is also linked as a synchronized source folder (`miataruUITests`) to the UI test target.
- `miataruScreenshotUITests` is linked as a dedicated UI test target for explicitly triggered screenshot captures.
- Test files directly in `miataru/miataru.xcodeproj/` are no longer the active storage location for app tests.

## 2) Inventory at a Glance

- Actively linked app test cases: **228** (Unit: 211, UI: 17 incl. 11 screenshot captures)
- Existing but not linked app test cases: **0**
- Third-party test functions in `Libraries`: **172**

## 2.1) Category/Scheme Mapping

| Category | Target(s) | Shared Scheme | Test Plan | Trigger |
|---|---|---|---|---|
| `CORE_UNIT` | `miataruTests` | `miataru-FunctionalUI` | `FunctionalSerial.xctestplan` | `scripts/test-functional-ui-serial.sh` |
| `FUNCTIONAL_UI` | `miataruUITests` | `miataru-FunctionalUI` | `FunctionalSerial.xctestplan` | `scripts/test-functional-ui-serial.sh` |
| `SCREENSHOT_CAPTURE` | `miataruScreenshotUITests` | `miataru-Screenshots` | `Screenshots.xctestplan` | `scripts/test-screenshots.sh` |

## 3) Active Test Catalog (`miataruTests`)

| ID | Test-Case Name | Purpose | Content (short) | Component | Type | Data/Mocks | Priority |
|---|---|---|---|---|---|---|---|
| UT-MND-001 | Hysteresis: Enter mutual state at 60s threshold | Validate enter threshold | Visitor age 55s, expected: <= 60s | MutualNavigationDetector / time logic | Unit | Fixed reference time, MiataruVisitor | High |
| UT-MND-002 | Hysteresis: Exit mutual state at 90s threshold | Validate exit threshold | Visitor age 95s, expected: > 90s | MutualNavigationDetector / time logic | Unit | Fixed reference time, MiataruVisitor | High |
| UT-MND-003 | Hysteresis: Stay in mutual state between 60s and 90s | Validate hysteresis middle range | Visitor age 75s, expected: >60 and <=90 | MutualNavigationDetector / time logic | Unit | Fixed reference time, MiataruVisitor | High |
| UT-MND-004 | Visitor timestamp parsing | Validate timestamp parsing | Millisecond string -> Date, deviation < 1ms | MiataruVisitor | Unit | Deterministic timestamp | Medium |
| UT-NRP-001 | No refresh in standard mode when target moved but remains on route | Avoid unnecessary refresh | Standard mode, target moved, not off-route -> false | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | High |
| UT-NRP-002 | Refresh in standard mode when target moved and is off route | Refresh on off-route target | Standard mode + target off-route -> true | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | High |
| UT-NRP-003 | Refresh in reverse mode when target moved significantly | Reverse mode behavior | Reverse mode + significant movement -> true | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | High |
| UT-NRP-004 | No refresh when auto update is disabled | Validate feature flag | Auto update off -> always false | NavigationRouteRefreshPolicy | Unit | Bool flags + coordinates | High |
| UT-NRP-005 | Refresh when no route exists | Initial no-route case | hasRoute=false -> true | NavigationRouteRefreshPolicy | Unit | nil coordinates | High |
| UT-NRP-006 | No refresh when on route and target movement is below threshold | Validate lower threshold bound | Target movement below threshold -> false | NavigationRouteRefreshPolicy | Unit | Small coordinate delta | High |
| UT-NRP-007 | Refresh when user is off route regardless of target movement | Prioritize user off-route | isUserOffRoute=true -> true | NavigationRouteRefreshPolicy | Unit | Identical start/target coordinates | High |
| UT-NRP-008 | No refresh if target did not move beyond threshold | No refresh without relevant movement | Very high threshold, small movement -> false | NavigationRouteRefreshPolicy | Unit | Threshold 1000m | Medium |
| UT-NRP-009 | No refresh when target coordinates are missing and user is on route | Missing-data behavior | currentDeviceCoordinate=nil, user on route -> false | NavigationRouteRefreshPolicy | Unit | nil + lastRouteCoordinate | Medium |
| UT-NRP-010 | hasTargetMovedSignificantly returns false for missing coordinates | Helper robustness | Missing current/last -> false | NavigationRouteRefreshPolicy | Unit | Nil parameters | Medium |
| UT-RGC-001 | Ghost progresses with device speed and timestamp in standard direction | Ghost progress standard mode | `device -> user` uses device speed/timestamp and progresses from the device coordinate | RouteGhostCalculator | Unit | FakeRoute (MKRoute shim), fixed time | High |
| UT-RGC-002 | Ghost uses expectedTravelTime fallback when speeds are below threshold | Validate fallback path | Low speeds -> expectedTravelTime used | RouteGhostCalculator | Unit | FakeRoute, near-threshold speeds | High |
| UT-RGC-003 | Ghost progresses with user speed and timestamp in reverse direction | Direction-dependent source | `user -> device` uses user speed/timestamp and progresses from the user coordinate | RouteGhostCalculator | Unit | FakeRoute, fixed time | High |
| UT-RGC-004 | Ghost progresses monotonically between timer ticks | Timer-driven progress stability | Same server position, speed, and timestamp produce increasing progress across repeated `now` ticks | RouteGhostCalculator | Unit | FakeRoute, fixed time offsets | High |
| UT-RGC-005 | Ghost uses polyline length when reported route distance is larger | Geometry-distance fallback | Reported route distance larger than polyline length still returns a valid destination ghost | RouteGhostCalculator | Unit | FakeRoute, MKPolyline geometry | High |
| UT-RGC-006 | Ghost uses polyline length when reported route distance is smaller | Geometry-distance fallback | Reported route distance smaller than polyline length still returns a valid destination ghost | RouteGhostCalculator | Unit | FakeRoute, MKPolyline geometry | High |
| UT-RGC-007 | Presentation policy uses fresh route start instead of stale sample timestamps | Cached-route visibility | Fresh `routeSummarySeedDate` keeps ghost presentation eligible despite old server sample timestamps | RouteGhostPresentationPolicy | Unit | Fixed route start/time | High |
| UT-RCS-001 | Set and get cached route by key | Cache baseline behavior | set/get by key returns route | RouteCacheStore | Unit | `RouteCacheStore.shared`, FakeRoute | High |
| UT-RCS-002 | isValid returns true when both endpoints moved less than threshold and on-route | Normal validity behavior | Small endpoint movement + on-route -> true | RouteCacheStore | Unit | Threshold + offRouteThreshold | High |
| UT-RCS-003 | isValid returns false when either endpoint moved beyond threshold | Invalidate on large movement | Endpoint moved far -> false | RouteCacheStore | Unit | Movement delta > 100m | High |
| UT-RCS-004 | isValid returns false when user is off route beyond offRouteThreshold | Off-route invalidation | User ~200m off route -> false | RouteCacheStore | Unit | offRouteThreshold=25 | High |
| UT-RCS-005 | Keys are isolated by transportType | Key isolation by transport | Same device ID, different transportType separated | RouteCacheStore | Unit | Two route variants | High |
| UT-RCS-006 | Keys are isolated by isRouteReversed | Key isolation by direction | Forward/reverse separable | RouteCacheStore | Unit | Two direction variants | High |
| UT-RCS-007 | clear(for:) removes only the specified device's entries | Selective clear | clear(Device A) removes A, keeps B | RouteCacheStore | Unit | Two device IDs | High |
| UT-RCS-008 | clear(for:) removes all variants (transport and direction) for a device | Full device clear | All variants for one device are removed | RouteCacheStore | Unit | 4 key variants per device | High |
| UT-RCS-009 | isValid returns false at the boundary when movement equals threshold | Boundary equality case | movement == threshold -> false | RouteCacheStore | Unit | Dynamically computed threshold | High |
| UT-RCS-010 | Default validity ignores off-route when offRouteThreshold is nil | Default with nil threshold | Off-route ignored when offRouteThreshold=nil | RouteCacheStore | Unit | Route + far user point | Medium |
| UT-RCS-011 | Single-point route is never considered off-route in validity check | Robust degenerate route handling | Single-point route not invalidated by off-route logic | RouteCacheStore | Unit | Single-point MKPolyline | Medium |
| UT-RCS-012 | get returns nil for missing key or mismatched parameters | Negative get() path | Unknown device / wrong transportType / direction -> nil | RouteCacheStore | Unit | Varying key params | Medium |
| UT-RCS-013 | Setting the same key twice overwrites the cached route | Overwrite semantics | Second set on same key replaces route | RouteCacheStore | Unit | Two different routes | Medium |
| UT-RCS-014 | isValid returns true with very large threshold despite large movement | Validate threshold influence | Very large threshold -> still true despite large movement | RouteCacheStore | Unit | Threshold=1_000_000 | Low |
| UT-VHV-001 | Known device resolution from visitor history | Validate known-device resolution | Create known device, visitor with same ID resolves name | VisitorHistory / KnownDeviceStore | Unit | Shared store, cleanup via defer | High |
| UT-VHV-002 | Unknown device resolution from visitor history | Validate unknown case | Visitor with unknown ID -> no match | VisitorHistory / KnownDeviceStore | Unit | Shared store | Medium |
| UT-VHV-003 | Device resolution after adding unknown device | unknown->known transition | First nil, after add() name resolves | VisitorHistory / KnownDeviceStore | Unit | Shared store, cleanup via defer | High |
| UT-VHV-004 | Visitor history sorting by timestamp | Validate sorting logic | 3 visitors sorted descending by TimeStampDate | VisitorHistory | Unit | Fixed time offsets | Medium |
| UT-VHV-005 | Shortened device ID format | Validate display format | Long ID becomes `prefix...suffix` | VisitorHistory (UI helper) | Unit | Static string ID | Low |
| UT-DLR-001 | Canonical miataru URI parses device ID | Preserve external URI behavior | `miataru://Device_abc-123` resolves to the case-preserved device ID | DeviceLinkResolver | Unit | URL fixture | High |
| UT-DLR-002 | Path-style miataru URI remains accepted for compatibility | Keep tolerant URI handling | `miataru:/device_abc-123` resolves to the case-preserved device ID | DeviceLinkResolver | Unit | URL fixture | Medium |
| UT-DLR-003 | Wrong URI scheme is ignored | Reject unrelated links | `https://...` returns nil | DeviceLinkResolver | Unit | URL fixture | High |
| UT-DLR-004 | Empty miataru URI is ignored | Avoid blank add/open requests | `miataru://` returns nil | DeviceLinkResolver | Unit | URL fixture | High |
| UT-DLR-005 | Canonical scanner code keeps miataru prefix compatibility | Protect QR scanner and QR generation contract | `miataru://...` scanner input preserves Device ID case and generated URL strings stay canonical | DeviceLinkResolver | Unit | Plain strings | High |
| UT-DLR-006 | Device ID trimming preserves case | Keep display/persistence separate from comparison normalization | Trimmed IDs keep original case; normalized IDs uppercase for comparisons | DeviceLinkResolver | Unit | Plain strings | High |
| UT-DLR-007 | Known device resolution is case-insensitive and returns canonical stored ID | Preserve old QR links while opening stored device | Mixed-case stored ID is found from differently cased input | DeviceLinkResolver / KnownDeviceStore | Unit | Shared store, cleanup via defer | High |
| UT-DLR-008 | Known device store rejects case-insensitive Device ID duplicates | Protect unique Device ID semantics | Existing `MixedCase` ID blocks a differently cased duplicate while preserving stored casing | KnownDeviceStore | Unit | Shared store, cleanup via defer | High |
| UT-DLR-009 | Known device store detects case-insensitive name duplicates without blocking | Warn/disambiguate same-looking names without preventing user choice | `Family iPhone` and `family iphone` are both allowed and detected as name duplicates | KnownDeviceStore | Unit | Shared store, cleanup via defer | Medium |
| UT-DLR-010 | Known device store detects existing case-insensitive Device ID conflicts | Surface legacy/older stored conflicts | Existing same-ID-different-case entries are detected for row disambiguation | KnownDeviceStore | Unit | Shared store snapshot restore | High |
| UT-DLR-011 | Device link routing opens known devices and adds unknown devices | Validate external URI branching | Known URI opens stored canonical device, unknown URI opens add-device sheet preserving input case | AppNavigationCoordinator | Unit | Shared store, cleanup via defer | High |
| UT-DLR-012 | Unknown visitor add requests preserve source and case | Protect Add Device prefill behavior | Unknown visitor action opens Add Device with source `unknownVisitor` and the original Device ID casing | AppNavigationCoordinator | Unit | Shared coordinator cleanup | High |
| UT-DLR-013 | Unknown visitor notification routes by known state | Validate notification-tap branching | Unknown notification shows action dialog preserving input case, known notification opens device | AppNavigationCoordinator | Unit | Shared store, cleanup via defer | High |
| UT-DLR-014 | Navigation miataru URI parses destination options | Protect in-app navigation deep links | `miataru://<DeviceID>?action=navigate&direction=userToDevice&presentation=focused` resolves to a navigation destination with focused launch options | DeviceLinkResolver | Unit | URL fixture | High |
| UT-DLR-015 | Navigation URL generation uses canonical action query | Protect internal link generation | Generated Miataru navigation links include the canonical host DeviceID and action/direction/presentation query items | DeviceLinkResolver | Unit | URLComponents fixture | High |
| UT-DLR-016 | Navigation device link routing opens known navigation and adds unknown devices | Validate navigation URI branching | Known navigation links publish a navigation request; unknown navigation links still enter Add Device flow preserving input case | AppNavigationCoordinator | Unit | Shared store/coordinator cleanup | High |
| UT-AIP-001 | KnownDevice maps to tracked person entity | Protect App Entity mapping | `KnownDevice` display name, DeviceID, and current-location access map to `IntentPersonRecord` and `TrackedPersonEntity` | App Intents / IntentLocationService | Unit | KnownDevice fixture | High |
| UT-AIP-002 | Suggested people only include visible devices with current location access | Enforce Siri/Shortcuts visibility boundary | Blank IDs and devices without current-location access are filtered out | App Intents / TrackedPersonQuery source | Unit | Fake intent provider | High |
| UT-AIP-003 | API location payload maps to intent person location | Protect location DTO mapping | `MiataruLocationData` maps to `IntentLocationPayload` and `IntentPersonLocation` with cached place text | App Intents / IntentLocationService | Unit | MiataruLocationData fixture | High |
| UT-AIP-004 | Latest location throws when no location exists | Validate no-location error | Visible person with no payload throws `.noLocationAvailable` | App Intents / IntentLocationService | Unit | Fake intent provider | High |
| UT-AIP-005 | Person without current location access is not visible and cannot be queried | Validate authorization privacy boundary | Hidden person is not suggested, cannot resolve as entity, and throws `.unauthorized` on stale shortcut execution | App Intents / IntentLocationService | Unit | Fake intent provider | High |
| UT-AIP-006 | Apple Maps URL uses coordinates and does not leak person identifiers | Prevent DeviceID/name leakage in route action | Maps URL contains only destination coordinates and no person ID/name | App Intents / OpenRouteToPersonIntent | Unit | IntentPersonLocation fixture | High |
| UT-AIP-007 | App Intent localization keys exist for all app locales | Enforce App Intent localization completeness | Every `intent_` string-catalog key and known AppIntents-extracted summary key has a non-empty value for all 10 app locales | App Intents / Localizable string-catalog QA | Unit | JSON parse of `Localizable.xcstrings` | High |
| UT-AIP-008 | Miataru navigation URL uses device ID and focused user-to-device mode | Protect in-app navigation handoff | The Miataru navigation intent creates a `miataru://` link with DeviceID, `action=navigate`, `direction=userToDevice`, `presentation=focused`, and no display-name leakage | App Intents / OpenMiataruNavigationToPersonIntent | Unit | IntentPersonLocation fixture | High |
| UT-AIP-009 | Miataru navigation intent opens app and resolves an internal navigation destination | Protect Shortcuts execution path | The Miataru navigation intent requests app foregrounding and resolves the generated Deep Link into a structured internal navigation destination | App Intents / OpenMiataruNavigationToPersonIntent | Unit | IntentPersonLocation fixture | High |
| UT-MRE-001 | Retries once for transient network error and succeeds | Validate retry path | first timedOut fails, second succeeds, 1 sleep recorded | MiataruRequestExecutor | Unit | injected sleep + deterministic jitter | High |
| UT-MRE-002 | Does not retry for non-retryable auth error | Validate non-retry path | `401` serverError throws without retry | MiataruRequestExecutor | Unit | APIError simulation | High |
| UT-MRE-003 | Classifier marks transient statuses and URL errors as retryable | Validate classification table | 408/429/5xx + transient URLError are retryable; auth/invalid/decoding are not | MiataruRetryClassifier | Unit | APIError + URLError cases | High |
| UT-MRE-004 | Retries are exhausted and final error is thrown | Validate retry ceiling | transient error repeats and throws after max retry | MiataruRequestExecutor | Unit | APIError simulation | High |
| UT-OUT-001 | FIFO order and max-cap enforcement | Validate queue semantics | cap overflow drops oldest, keeps order | LocationUpdateOutboxStore | Unit | temp outbox file + deterministic payloads | High |
| UT-OUT-002 | TTL pruning before enqueue and read | Validate expiry handling | expired entries removed before appending/reading | LocationUpdateOutboxStore | Unit | mutable clock + temp outbox file | High |
| UT-OUT-003 | Dedupe by Device+Timestamp+Latitude+Longitude | Validate dedupe key behavior | identical payload not enqueued twice | LocationUpdateOutboxStore | Unit | temp outbox file + duplicate payload | High |
| UT-OUT-004 | Runtime policy can keep aged items and raise max cap | Validate user-configurable queue policy | switching to unlimited TTL and higher cap keeps aged entries in FIFO order | LocationUpdateOutboxStore | Unit | mutable clock + temp outbox file | High |
| UT-LDC-001 | Submit queues update after transient failure | Validate submit fallback | transient send failure leads to outbox enqueue | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + temp outbox | High |
| UT-LDC-002 | Flush stops on transient head error and keeps queue order | Validate head-stop semantics | transient head failure increments attempt and stops cycle | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-003 | Flush drops non-retryable head and continues with next item | Validate non-retryable discard behavior | non-retryable head removed, next item processed | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-004 | Submit returns failed for non-retryable error without queueing | Validate immediate failure behavior | non-retryable submit error does not enqueue | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + temp outbox | High |
| UT-LDC-005 | Submit appends behind pending outbox | Validate end-to-end FIFO delivery | existing outbox item is sent before newly submitted update, preserving metadata | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-006 | Pending outbox can be sent to changed server URL | Validate user-selected retarget behavior | queued item is sent to the corrected server URL after server change confirmation | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-007 | Pending outbox can be discarded after server URL change | Validate user-selected discard behavior | queued item is removed without sending after discard confirmation | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-008 | Submit with pending outbox schedules deferred drain | Validate active tracking drain trigger | appending a new update behind pending items schedules a near-term FIFO flush | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox + short deferred delay | High |
| UT-LDC-009 | Manual full flush drains more than one batch | Validate user-triggered full drain | manual flush continues past the configured batch size until the queue is empty | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + small batch size | High |
| UT-LDC-010 | Server URL retarget keeps in-flight old URL item queued for new URL | Validate retarget race safety | an in-flight old-URL send cannot remove a queued record after the queue was retargeted | LocationUpdateDeliveryCoordinator | Unit | blocking sender actor + retarget during flush | High |
| UT-UVA-001 | Unknown visitor with new timestamp is selected | Validate unknown-device candidate selection | New visitor after watermark produces one candidate | UnknownVisitorAlertEvaluator | Unit | MiataruVisitor fixture + fixed timestamp | High |
| UT-UVA-002 | Cooldown suppresses repeated notifications within 24h | Validate 24h dedupe window | Already-notified device within cooldown produces no candidate | UnknownVisitorAlertEvaluator | Unit | fixed notification/visit times | High |
| UT-UVA-003 | Visitor is re-notified after 24h cooldown | Validate re-notify path after cooldown | Same device after >24h produces candidate again | UnknownVisitorAlertEvaluator | Unit | fixed notification/visit times | High |
| UT-UVA-004 | Known, ignored, and own device IDs are excluded | Validate filtering rules | own/known/ignored are excluded, only unknown remains | UnknownVisitorAlertEvaluator | Unit | mixed visitor fixtures | High |
| UT-UVA-005 | Permission request enables feature when authorization is granted | Validate activation permission flow | `.notDetermined` + grant returns `.enabled` | UnknownVisitorAlertService | Unit | actor-based notifier mock + isolated UserDefaults suite | High |
| UT-UVA-006 | Denied authorization disables feature activation | Validate denied permission behavior | `.denied` returns `.denied` and no prompt is re-requested | UnknownVisitorAlertService | Unit | actor-based notifier mock + isolated UserDefaults suite | High |
| UT-UVA-007 | Unknown visitor alert localization keys exist for all app locales | Localization completeness gate | Required keys present and non-empty for all 10 locales | Localizable string-catalog QA | Unit | JSON parse of `Localizable.xcstrings` | High |
| UT-FBT-001 | Never-expiring frequent background mode schedules a repeating 24h reminder | Protect manual never-expiring reminder | Active tracking + unlimited manual frequent mode schedules one repeating 24h notification | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | High |
| UT-FBT-002 | Existing reminder is kept so the 24h timer is not reset repeatedly | Avoid pushing reminder forward | Existing reminder request prevents rescheduling | FrequentBackgroundTrackingReminderService | Unit | pending notification mock | High |
| UT-FBT-003 | Finite or inactive frequent background mode removes the reminder | Cleanup inactive reminder | Finite/inactive frequent mode cancels pending and delivered reminder notifications | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | High |
| UT-FBT-004 | Undetermined notification permission is requested before scheduling | Validate permission request path | `.notDetermined` requests alert/sound permission before scheduling | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | High |
| UT-FBT-005 | Finite frequent background mode schedules one expiration notification | Protect manual finite expiration notice | Finite manual mode schedules one-shot notification at the stored expiration date | FrequentBackgroundTrackingReminderService | Unit | isolated `UserDefaults`, fixed clock | High |
| UT-FBT-006 | Manual finite mode disable cancels future expiration notification | Cleanup manual disable path | Manual disable removes pending future expiration notification and stored date | FrequentBackgroundTrackingReminderService | Unit | isolated `UserDefaults`, pending notification mock | High |
| UT-FBT-007 | Automatic finite mode expiry does not cancel due expiration notification | Preserve already-due expiration notice | Expired notification date is cleared without removing the due pending notification | FrequentBackgroundTrackingReminderService | Unit | isolated `UserDefaults`, fixed clock | High |
| UT-FBT-008 | Low battery auto-disable cancels timers and sends explanatory notification | Protect battery fallback notification | Low battery cleanup cancels reminder/expiration state and sends typed battery notification | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | High |
| UT-FBT-009 | Smart frequent mode-change notifications are immediate and typed | Protect Smart auto-switch notifications | Smart activation/deactivation notifications are immediate, typed, and non-empty | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | High |
| UT-FBT-010 | Smart frequent mode-change notifications respect denied authorization | Guard denied notification permission | Denied notification authorization prevents Smart mode-change request scheduling | FrequentBackgroundTrackingReminderService | Unit | actor-based notifier mock | Medium |
| UT-FBT-011 | Smart frequent mode-change notification setting requests permission before enabling | Guard settings permission flow | `.notDetermined` requests notification authorization before the Smart mode-change notification setting is enabled; denial is reported and leaves the setting off | FrequentBackgroundTrackingReminderService / Settings UI binding | Unit | actor-based notifier mock | High |
| UT-DSL-001 | Device slogan draft sanitization preserves regular spaces while typing | Protect editable slogan input | Draft sanitization keeps normal spaces so multi-word info text remains typeable | MiataruAppAPI slogan input handling | Unit | Plain strings | High |
| UT-DSL-002 | Device slogan cleansing trims surrounding whitespace on save | Keep saved slogan normalized | Save sanitization removes leading/trailing whitespace but preserves inner spaces | MiataruAppAPI slogan save handling | Unit | Plain strings | High |
| UT-SET-001 | Existing-install settings migration applies once and only to targeted keys | Guard one-time upgrade behavior | Migration enables only the targeted booleans and does not reapply after marker is set | SettingsMigration | Unit | isolated `UserDefaults` suite | High |
| UT-SET-002 | Settings localization keys exist for all app locales | Enforce localization completeness | Required settings labels/explanations are present and non-empty for all 10 locales | Localizable string-catalog QA | Unit | JSON parse of `Localizable.xcstrings` | High |
| UT-SET-003 | Settings.bundle strings contain renamed labels and picker options for all locales | Keep in-app and bundle copy aligned | Every localized `Root.strings` file contains the renamed settings labels and picker values | Settings.bundle localization QA | Unit | plist/strings parsing from bundle resources | High |
| UT-SET-004 | Settings.bundle plist defaults match the runtime settings defaults | Prevent fresh-install default drift | `Root.plist` defaults stay in sync with the centralized runtime registration table | Settings defaults QA | Unit | plist parsing + `SettingsDefaultValues` | High |
| UT-LTP-001 | Background location configuration preserves significant-change default | Protect standard background default | Standard mode uses significant-change monitoring and frequent mode maps normalized distance/accuracy | LocationTrackingPolicy | Unit | Static policy inputs | High |
| UT-LTP-002 | Location tracking mode resolver keeps foreground, navigation, and background policies distinct | Validate tracking resolver | Foreground, navigation, `When In Use`, stopped, significant-change, and frequent modes resolve correctly | LocationTrackingPolicy | Unit | Static authorization/app-state inputs | High |
| UT-LTP-003 | Location service command plan keeps primary recovery anchor separate from frequent updates | Protect reboot-safe manager separation | Frequent background mode keeps the primary manager on significant-change monitoring while standard updates run on the secondary manager | LocationTrackingPolicy | Unit | Static tracking modes + recovery-anchor eligibility | High |
| UT-LTP-004 | Primary significant-change callback reasserts frequent background only for active runtime sessions | Protect background callback policy | Frequent reassertion stays limited to active frequent sessions; stale callbacks and standard reassertion retain expected behavior | LocationTrackingPolicy | Unit | Static app-state/source/mode-switch inputs | High |
| UT-LTP-005 | Background lifecycle context keeps frequent mode active even before UIKit reports background | Protect background transition race | Forced background/foreground contexts override current UIKit state for tracking reconciliation | LocationTrackingPolicy | Unit | Static app-state/context inputs | High |
| UT-LTP-006 | Manual frequent mode overrides smart frequent runtime | Protect Stage 2 override | Manual frequent mode wins over Smart runtime for effective mode, display mode, counters, and delivery intervals | LocationTrackingPolicy | Unit | Static app-state and preference inputs | High |
| UT-LTP-007 | Significant-change recovery anchor is kept only for active Always-authorized tracking | Protect recovery/session eligibility | Recovery anchor, Always service session, frequent activity session, restore, reconcile, and battery-disable policies stay gated | LocationTrackingPolicy | Unit | Static authorization/preference inputs | High |
| UT-LTP-008 | Frequent background accuracy recovery temporarily uses precise configuration for 100m mode | Protect Smart frequent recovery boost | 100 m Smart frequent recovery uses 10 m / nearest-ten-meters while non-trigger filters keep their configured behavior | LocationTrackingPolicy | Unit | Static configuration inputs | High |
| UT-LTP-009 | Frequent background accuracy quality gates uploads and current location updates | Protect coarse-fix rejection | Background frequent callbacks reject invalid/coarse accuracy, accept 28.6 m at the 100 m filter, reject 69.4 m at the 25 m filter, and leave foreground/primary callbacks unchanged | LocationTrackingPolicy | Unit | Static app-state/source/accuracy inputs | High |
| UT-LTP-010 | Smart frequent accuracy recovery starts stops and cools down | Protect recovery trigger lifecycle | 1414 m starts immediately, two >300 m fixes start recovery, manual mode is ineligible, <=100 m stops, 120 s timeout stops, and cooldown blocks restart | LocationTrackingPolicy | Unit | Fixed dates and static policy inputs | High |
| UT-SFB-001 | Smart frequent speed detection supports hybrid and GPS-only modes | Validate Smart speed source policy | Valid GPS speed wins; Hybrid derives speed from usable distance/time samples; GPS-only ignores derived speed | SmartFrequentBackgroundPolicy | Unit | deterministic `CLLocation` fixtures | High |
| UT-SFB-002 | Persisted smart frequent seed is fresh-gated and still rejects implausible activation | Protect first-background-update Smart activation after relaunch | Fresh seeds can satisfy freshness, while stale/future seeds and implausible derived speeds do not activate | SmartFrequentBackgroundPolicy | Unit | deterministic `CLLocation` fixtures + fixed dates | High |
| UT-SFB-003 | Smart frequent activation evidence is quality aware and startup guarded | Protect activation evidence gates | Trusted GPS, region exit, derived movement, startup-batch, same-second, and low-quality evidence behave at boundaries | SmartFrequentBackgroundPolicy | Unit | deterministic `CLLocation` fixtures | High |
| UT-SFB-004 | Smart frequent exit fence eligibility and radius are automatic | Protect hidden exit-fence policy | Eligibility and automatic radius calculation honor tracking/auth/manual/runtime constraints | SmartFrequentBackgroundPolicy | Unit | Static policy inputs | High |
| UT-SFB-005 | Smart frequent activation and inactivity policies are threshold based | Validate Smart runtime policy | Activation, deactivation, inactivity timeout, movement threshold, and confirmation decisions behave at boundaries | SmartFrequentBackgroundPolicy | Unit | fixed dates and static policy inputs | High |
| UT-SFB-006 | Smart frequent inactivity timer action avoids stale callback recursion | Protect backgrounding crash path | Stale callback gaps produce no immediate timer action, fresh callback plus old movement expires, future movement schedules, and missing timestamps do not recurse | SmartFrequentBackgroundPolicy | Unit | fixed dates and static policy inputs | High |
| UT-SFB-007 | Smart frequent runtime watchdog recovers active callback gaps | Protect watchdog recovery/fallback | Watchdog starts, waits, reasserts, and falls back after max recovery attempts | SmartFrequentBackgroundPolicy | Unit | fixed dates and static policy inputs | High |
| UT-SFB-008 | Smart frequent runtime is evaluated only in background | Protect app-state gating | Smart frequent runtime evaluation remains background-only | LocationTrackingPolicy / SmartFrequentBackgroundPolicy | Unit | Static app-state inputs | High |
| UT-SFB-009 | Smart frequent exit fence anchor uses newest usable location | Protect anchor selection | Newest valid anchor is selected from optional candidates | SmartFrequentBackgroundPolicy | Unit | deterministic `CLLocation` fixtures | Medium |
| UT-LSP-001 | Frequent background callbacks bypass sensitivity while frequent runtime is effective | Protect upload path filtering | Manual frequent and Smart probing/confirmed callbacks bypass sensitivity only when effective | LocationSamplePolicy | Unit | Static app-state/runtime inputs | High |
| UT-LSP-002 | Duplicate location callbacks are suppressed before upload | Prevent duplicate server sends from parallel location services | Same timestamp and coordinate callback is skipped; later timestamp is accepted | LocationSamplePolicy | Unit | Deterministic `CLLocation` fixtures | High |
| UT-LSP-003 | Location update batches are processed chronologically and skip invalid coordinates | Ensure usable Core Location batch entries can be considered | Multi-location callbacks are sorted by timestamp and invalid-coordinate entries are filtered before processing | LocationSamplePolicy | Unit | deterministic `CLLocation` batch fixtures | High |
| UT-LSP-004 | Location samples reject stale future and out-of-order timestamps | Protect sample acceptance ordering | Stale, future, duplicate, and out-of-order samples are rejected before changing runtime/upload state | LocationSamplePolicy | Unit | deterministic `CLLocation` fixtures + fixed dates | High |
| UT-LBF-001 | Background forensic gap assessment distinguishes frequent gaps from significant-change idle | Protect diagnostics gap classification | Frequent callback gaps and significant-change idle windows classify separately | LocationBackgroundForensics | Unit | fixed dates and forensic state | Medium |
| UT-LBF-002 | Foreground recovery burst policy only logs inside recovery window with activity | Protect recovery-burst diagnostics | Foreground recovery bursts require activity inside the configured recovery window | LocationBackgroundForensics | Unit | fixed dates and counters | Medium |
| UT-LBF-003 | Significant-change rearm policy attempts only for eligible fresh builds | Protect one-time rearm policy | Re-arm attempts are gated by build identifier, tracking, authorization, DeviceKey block state, and reason | LocationBackgroundForensics | Unit | Static policy inputs + fixed dates | High |
| UT-LBF-004 | Background forensics recorder persists rearm status and build marker | Protect recorder persistence | Significant-change re-arm status, build marker, and forensic state survive recorder reloads with isolated defaults | LocationBackgroundForensicsRecorder | Unit | isolated `UserDefaults` suite + fixed dates | High |
| UT-LBF-005 | Background forensics recorder logs foreground recovery burst after a gap | Protect recorder diagnostics | A foreground open after a background gap prepares recovery tracking and logs callback/accepted/upload burst evidence once activity arrives | LocationBackgroundForensicsRecorder | Unit | isolated diagnostics log + fixed dates | Medium |
| UT-LMS-001 | Location update mode counters increment and reset after 24 hours | Protect mode-specific diagnostics | Foreground/live, significant-change, Smart frequent, and manual frequent counters increment and reset together after 24 hours | LocationUpdateMetricsStore | Unit | deterministic counter and fixed dates | High |
| UT-SET-011 | Smart frequent migration preserves existing manual frequent users | Preserve pre-3.2 manual frequent state | Migration enables the Smart prerequisite when an existing install already had manual frequent mode enabled | SettingsMigration | Unit | isolated `UserDefaults` suite | High |
| UT-SET-012 | Manual frequent normalization keeps Smart prerequisite enabled after migration | Protect external Settings.bundle changes | Startup normalization re-enables Smart prerequisite if manual frequent mode was externally enabled after migration | SettingsMigration | Unit | isolated `UserDefaults` suite | High |
| UT-SET-017 | App string catalog has no stale or new translation units | Keep localized release catalog clean | `Localizable.xcstrings` contains no `extractionState == stale` entries and no `stringUnit.state == new` entries | Localizable string-catalog QA | Unit | JSON parse of `Localizable.xcstrings` | High |
| UT-GEN-001 | example | Placeholder/template | Empty example test without assertions | Base skeleton | Unit | None | Low |

## 4) Previously Unlinked, Now Active Test Cases

These cases were previously located under `miataru.xcodeproj/*.swift` and are now linked into active targets (`miataruTests` / `miataruUITests`).

| ID | Test-Case Name | Purpose | Content (short) | Component | Type | Active in Target |
|---|---|---|---|---|---|---|
| DT-MH-001 | relativeTimeString returns localized 'now' within threshold | relativeTime now threshold | 2s old -> localized now string | MapHelpers | Unit | Yes |
| DT-MH-002 | relativeTimeString returns a non-empty string for past times | Relative time for past values | 120s old -> non-empty / non-placeholder | MapHelpers | Unit | Yes |
| DT-MH-003 | mapSpeedLabelText returns nil for values below default threshold | Speed below threshold | 2 m/s -> nil | MapHelpers | Unit | Yes |
| DT-MH-004 | mapSpeedLabelText returns formatted value above threshold | Speed above threshold | 5 m/s -> label with km/h or mph | MapHelpers | Unit | Yes |
| DT-MH-005 | timezoneOffsetString returns nil for same timezone | Equal timezone offset | Device TZ = current TZ -> nil | MapHelpers | Unit | Yes |
| DT-MH-006 | timezoneOffsetString returns +2 for TZ two hours ahead | Positive timezone offset | +2h vs local -> "+2" | MapHelpers | Unit | Yes |
| DT-MH-007 | spanForZoomLevel produces reasonable deltas and round-trips with currentZoomLevelFromSpan | Zoom roundtrip | spanForZoomLevel <-> currentZoomLevelFromSpan | MapHelpers | Unit | Yes |
| DT-MH-008 | relativeTimeString with future date returns 'now' | Future-date handling | Future date -> now string | MapHelpers | Unit | Yes |
| DT-MH-009 | timezoneOffsetString returns negative offset for behind timezones | Negative timezone offset | -3h vs local -> "-3" | MapHelpers | Unit | Yes |
| DT-MH-010 | mapSpeedLabelText returns non-nil when min threshold is 0 and positive speed | Configurable threshold | minSpeedKmh=0 + positive speed -> label | MapHelpers | Unit | Yes |
| DT-MH-011 | mapLiveSpeedLabelText returns formatted value for fresh locations | Live marker speed freshness | 60s old + 5 m/s -> label with km/h or mph | MapHelpers | Unit | Yes |
| DT-MH-012 | mapLiveSpeedLabelText still shows speed exactly at five minutes | Live marker boundary | 300s old + 5 m/s -> label | MapHelpers | Unit | Yes |
| DT-MH-013 | mapLiveSpeedLabelText hides speed older than five minutes | Live marker stale suppression | 301s old + 5 m/s -> nil | MapHelpers | Unit | Yes |
| DT-MH-014 | mapLiveSpeedLabelText treats future timestamps as fresh | Future timestamp handling | Future timestamp + 5 m/s -> label | MapHelpers | Unit | Yes |
| DT-MH-015 | history speed formatting stays independent from live freshness | History/live display separation | Stale live timestamp hides label while history formatting still shows speed | MapHelpers | Unit | Yes |
| DT-MHA-001 | mapSpeedLabelText returns nil for nil or zero/negative speeds | Guard paths in mapSpeedLabelText | nil/0/<0 -> nil | MapHelpers | Unit | Yes |
| DT-MHA-002 | relativeTimeString respects custom timeConsideredNow threshold | Parameterized now threshold | 2s old with threshold=1 -> not now | MapHelpers | Unit | Yes |
| DT-MKP-001 | split(at:) splits a simple horizontal segment correctly | Basic split case | Half segment, length consistency, progress ~0.5 | MKPolyline Extension | Unit | Yes |
| DT-MKP-002 | split(at:) at distance 0 yields start interpolation and zero done length | Split at distance 0 | done=0, ghost=start | MKPolyline Extension | Unit | Yes |
| DT-MKP-003 | split(at:) at total length yields end interpolation and zero todo length | Split at total distance | todo=0, ghost=end | MKPolyline Extension | Unit | Yes |
| DT-MKP-004 | split(at:) works across multiple segments | Multi-segment split | Split in segment 2, progress check | MKPolyline Extension | Unit | Yes |
| DT-MKP-005 | closestDistance(to:) finds zero for a point on the polyline | Distance on line | Point on line -> distance ~0 | MKPolyline Extension | Unit | Yes |
| DT-MKP-006 | closestDistance(to:) returns perpendicular distance when projection falls within segment | Perpendicular distance | Point next to line -> perpendicular distance | MKPolyline Extension | Unit | Yes |
| DT-MKP-007 | closestDistance(to:) works for single-point polyline | Single-point distance | same->0, far->>0 | MKPolyline Extension | Unit | Yes |
| DT-MKP-008 | remainingDistance(toEndFrom:) decreases as point moves along the polyline | Remaining distance monotonicity | start > mid > end | MKPolyline Extension | Unit | Yes |
| DT-MKP-009 | remainingDistance(toEndFrom:) equals total when point is before start of polyline | Before-start behavior | Point before start -> remaining ~total | MKPolyline Extension | Unit | Yes |
| DT-MKP-010 | remainingDistance(toEndFrom:) works for single-point polyline | Single-point remaining distance | Single point -> direct distance | MKPolyline Extension | Unit | Yes |
| DT-MKP-011 | split(at:) returns nil for degenerate (single-point) polyline | Degenerate split | Single-point split -> nil | MKPolyline Extension | Unit | Yes |
| DT-UI-001 | testLaunchWithCompletedOnboardingShowsRootTabs | Stable launch state | Launch with completed onboarding, tab root visible, no alert | App Bootstrap / Tab Root | UI (XCTest) | Yes |
| DT-UI-002 | testDevicesAddSheetCanOpenAndCancel | Basic device flow validation | Open add-device sheet and close via cancel | Device List / Add Device | UI (XCTest) | Yes |
| DT-UI-003 | testSettingsShowOnboardingActionIsReachable | Protect settings onboarding action | Opens tracking details from settings and verifies the onboarding action remains reachable without alerts | Settings / Tracking Details | UI (XCTest) | Yes |
| DT-UI-004 | testSettingsAdvancedOptionsNavigationMovesAdvancedControlsOffRootScreen | Protect settings reorganization and row hitbox | Verifies Advanced Options is reachable by tapping row whitespace and advanced-only controls no longer appear on the root settings screen | Settings / Advanced Options | UI (XCTest) | Yes |
| DT-UI-005 | testQRCodeTabShowsDeviceKeyAction | Validate QR core action | Open QR tab, device key action available and tappable | QR Screen / Device Key | UI (XCTest) | Yes |

## 5) Screenshot Test Inventory (`miataruScreenshotUITests`)

These tests are intentionally isolated in a dedicated, explicitly triggered scheme:

- Shared scheme: `miataru-Screenshots`
- Test plan: `Screenshots.xctestplan`
- Script: `miataru/scripts/test-screenshots.sh`
- Language/locale enforcement: the script and UI test launch explicitly set Apple language/locale so captures follow the selected `--languages` values independently from simulator default language.

Current scenarios (maximum 10 PNGs per language/device):

| ID | Test-Case Name | Purpose | Content (short) | Type |
|---|---|---|---|---|
| ST-001 | test_01_root_devices | Root devices start | Captures devices start state (iPhone/iPad) | UI Screenshot |
| ST-002 | test_02_root_qr | Root QR start | Captures QR tab in stable start state | UI Screenshot |
| ST-003 | test_03_root_settings | Root settings start | Captures settings tab in stable start state | UI Screenshot |
| ST-004 | test_04_devices_add_sheet | Add-device dialog | Opens add-device sheet and captures screenshot | UI Screenshot |
| ST-005 | test_05_settings_show_onboarding_action | Settings action visible | Navigates/scrolls to onboarding action in settings | UI Screenshot |
| ST-006 | test_06_onboarding_start | Onboarding entry | Starts app in onboarding mode and captures entry state | UI Screenshot |
| ST-007 | test_07_onboarding_pager | Onboarding pager | Captures pager state in onboarding | UI Screenshot |
| ST-008 | test_08_qr_device_key_action | QR action | Captures QR state with device-key action | UI Screenshot |
| ST-009 | test_09_ipad_groups_tab_or_skip | iPad groups | iPad-specific groups tab or clean skip | UI Screenshot |
| ST-010 | test_10_settings_navigation_container | Settings container | Captures settings navigation state or clean skip | UI Screenshot |

## 6) Third-Party Test Inventory (`miataru/Libraries`)

These tests come from embedded libraries and should be evaluated separately for app-level gap analysis:

- `QRCode-main`: 155 test functions
- `SwiftImageReadWrite`: 12 test functions
- `NavigationOverlayKit-master`: 4 test functions
- `swift-qrcode-generator`: 1 test function

## 7) Catalog Metadata for Next Gap Step

For gap analysis, this catalog already includes key comparison dimensions:

- Test type (`Unit` / `UI`)
- Activation status in target (`yes/no`)
- Component mapping (policy, cache, geometry, UI helper)
- Edge-case coverage (boundary, nil, single-point, thresholds)
- Dependencies (`Shared` stores, FakeRoute/MKRoute shim, time simulation)

Practical baseline for the next step:

- Strong coverage for `RouteCacheStore`, `NavigationRouteRefreshPolicy`, `RouteGhostCalculator`.
- Added focused coverage for extracted `LocationTrackingPolicy`, `SmartFrequentBackgroundPolicy`, `LocationSamplePolicy`, `LocationBackgroundForensics`, `LocationBackgroundForensicsRecorder`, and `LocationUpdateMetricsStore` behavior, including reboot-safe tracking decisions, Smart frequent activation/deactivation, Smart frequent accuracy recovery, stale inactivity-timer callback-gap decisions, 25 m accuracy-gate behavior, cold-start and persisted Smart reference gating, implausible Smart activation speed rejection, background lifecycle mode selection, foreground-only `When In Use` authorization, mode-specific update counters, shared frequent-mode delivery/visitor intervals, chronological batch handling, sample rejection, forensics persistence/logging, and duplicate location callback suppression.
- Added focused coverage for unknown-visitor alert evaluation, permission branching, and localization completeness checks.
- Added focused coverage for frequent-background reminder, expiration, low-battery, optional Smart mode-change notifications, and Smart notification permission gating.
- Added string-catalog QA for stale/new translation-unit cleanup in addition to required-key localization completeness.
- Some tests are still logic-level only without integration (UI target is active and expanded with deterministic core flows, including the settings split/navigation regression path).
- Previously extracted map/UI tests are now active; next focus remains integration/E2E for navigation and location pipeline.

## 8) Gap Matrix Reference

Prioritized gap analysis and area scoring is maintained in:

- `documentation/test-gap-matrix.md`

Maintenance note:

- On every test change, **Test Catalog** and **Gap Matrix** must be updated together.
