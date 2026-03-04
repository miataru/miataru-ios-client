# Test Catalog (as of 2026-03-04)

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

- Actively linked app test cases: **85** (Unit: 71, UI: 14)
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
| UT-RGC-001 | Ghost progresses with primary speed and timestamp (non-reversed: user primary) | Ghost progress standard mode | user speed/timestamp as primary source, progress in (0,1] | RouteGhostCalculator | Unit | FakeRoute (MKRoute shim), fixed time | High |
| UT-RGC-002 | Ghost uses expectedTravelTime fallback when speeds are below threshold | Validate fallback path | Low speeds -> expectedTravelTime used | RouteGhostCalculator | Unit | FakeRoute, near-threshold speeds | High |
| UT-RGC-003 | Ghost bases from device when reversed route | Direction-dependent source | isRouteReversed=true -> device is base | RouteGhostCalculator | Unit | FakeRoute, fixed time | High |
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
| UT-MRE-001 | Retries once for transient network error and succeeds | Validate retry path | first timedOut fails, second succeeds, 1 sleep recorded | MiataruRequestExecutor | Unit | injected sleep + deterministic jitter | High |
| UT-MRE-002 | Does not retry for non-retryable auth error | Validate non-retry path | `401` serverError throws without retry | MiataruRequestExecutor | Unit | APIError simulation | High |
| UT-MRE-003 | Classifier marks transient statuses and URL errors as retryable | Validate classification table | 408/429/5xx + transient URLError are retryable; auth/invalid/decoding are not | MiataruRetryClassifier | Unit | APIError + URLError cases | High |
| UT-MRE-004 | Retries are exhausted and final error is thrown | Validate retry ceiling | transient error repeats and throws after max retry | MiataruRequestExecutor | Unit | APIError simulation | High |
| UT-OUT-001 | FIFO order and max-cap enforcement | Validate queue semantics | cap overflow drops oldest, keeps order | LocationUpdateOutboxStore | Unit | temp outbox file + deterministic payloads | High |
| UT-OUT-002 | TTL pruning before enqueue and read | Validate expiry handling | expired entries removed before appending/reading | LocationUpdateOutboxStore | Unit | mutable clock + temp outbox file | High |
| UT-OUT-003 | Dedupe by Device+Timestamp+Latitude+Longitude | Validate dedupe key behavior | identical payload not enqueued twice | LocationUpdateOutboxStore | Unit | temp outbox file + duplicate payload | High |
| UT-LDC-001 | Submit queues update after transient failure | Validate submit fallback | transient send failure leads to outbox enqueue | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + temp outbox | High |
| UT-LDC-002 | Flush stops on transient head error and keeps queue order | Validate head-stop semantics | transient head failure increments attempt and stops cycle | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-003 | Flush drops non-retryable head and continues with next item | Validate non-retryable discard behavior | non-retryable head removed, next item processed | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + prefilled outbox | High |
| UT-LDC-004 | Submit returns failed for non-retryable error without queueing | Validate immediate failure behavior | non-retryable submit error does not enqueue | LocationUpdateDeliveryCoordinator | Unit | mock sender actor + temp outbox | High |
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
| DT-UI-003 | testSettingsShowOnboardingActionIsReachable | Protect settings onboarding action | Settings action reachable/tappable and no unexpected alerts | Settings / Onboarding | UI (XCTest) | Yes |
| DT-UI-004 | testQRCodeTabShowsDeviceKeyAction | Validate QR core action | Open QR tab, device key action available and tappable | QR Screen / Device Key | UI (XCTest) | Yes |

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
- Some tests are still logic-level only without integration (UI target is active and expanded with deterministic core flows).
- Previously extracted map/UI tests are now active; next focus remains integration/E2E for navigation and location pipeline.

## 8) Gap Matrix Reference

Prioritized gap analysis and area scoring is maintained in:

- `documentation/test-gap-matrix.md`

Maintenance note:

- On every test change, **Test Catalog** and **Gap Matrix** must be updated together.
