# Test Gap Matrix (as of 2026-03-14)

## Purpose

This matrix shows, per core area:

- Risk impact
- Current test coverage (active vs. only existing)
- Concrete gaps
- Prioritized next testing steps

Scale:

- `Coverage`: High / Medium / Low / None
- `Gap`: Low / Medium / High / Critical

## Gap Matrix

| Area / Component | Risk | Active Unit Tests | Existing but Not Linked Tests | Active Integration | Active UI/E2E | Coverage | Gap | Next Step |
|---|---|---|---|---|---|---|---|---|
| Route Cache + Refresh + Ghost (`RouteCacheStore`, `NavigationRouteRefreshPolicy`, `RouteGhostCalculator`) | High | Yes (27) | No | No | No | Medium-High | Medium | Add integration tests for end-to-end recalculation decisions (route exists, stale, off-route, reverse). |
| Mutual Navigation + Visitor Timestamps (`MutualNavigationDetector`, `MiataruVisitor`) | High | Yes (4) | No | No | No | Low-Medium | High | Test full class behavior (state transitions enter/stay/exit), not only time deltas. |
| Visitor History + Known Device Resolution (`VisitorHistoryViewModel`, `KnownDeviceStore`) | Medium | Yes (5) | No | No | No | Medium | Medium | Add persistence/concurrency tests (duplicate IDs, case-insensitive merge, race-safe updates). |
| Unknown Visitor Alerts (`UnknownVisitorAlertEvaluator`, `UnknownVisitorAlertService`) | High | Yes (7) | No | No | No | Medium | Medium-High | Add integration tests for upload-triggered history polling, watermark progression, and end-to-end local notification scheduling. |
| Device Info / Slogan Editing (`MiataruAppAPI`, QR/Edit-Device slogan flows) | Medium | Yes (2) | No | No | No | Low-Medium | Medium | Add save/display roundtrip coverage for the editable slogan flows, including cache refresh and server-error handling. |
| Map Helper + Polyline Geometry (`MapHelpers`, `MKPolyline` Extensions) | High | Yes (23) | No | No | No | Medium-High | Medium | Tighten assertions for numeric edge cases and distance projection regressions. |
| Location Update Pipeline (`LocationManager`, `DeviceLocationRefresher`, retry/outbox path) | Very High | Yes (11) | No | No | No | Low-Medium | High | Add integration tests for GPS updates, network failures, retry/backoff, outbox flush triggers, and background behavior. |
| Settings Defaults + Localization (`SettingsManager`, `Settings.bundle`, `Localizable.xcstrings`) | Medium-High | Yes (4) | No | No | Yes (1 targeted settings-navigation smoke) | Medium | Medium | Add integration coverage for fresh-install defaults, one-time upgrade migration wiring in app bootstrap, and locale synchronization edge cases. |
| Device Access / Sync (`AllowedDeviceListManager`, SyncQueue) | High | No | No | No | No | None | High | Add tests for sync triggers, conflict cases, error paths, and idempotent sync behavior. |
| Persistence Stores (`DeviceLocationCacheStore`, `DeviceHistoryCacheStore`, `DeviceGroupStore`, `DeviceSloganCacheStore`, `LocationUpdateOutboxStore`) | High | Partly direct | No | No | No | Low-Medium | High | Expand serialization roundtrip, migration-safe loading, corruption handling, and thread-safety tests for remaining stores. |
| Widget Data Flow (`WidgetDataSyncCoordinator`, `SharedWidgetData`, `WidgetMapSnapshotGenerator`) | Medium-High | No | No | No | No | None | High | Add contract tests for payload formats, data filtering, and snapshot failure cases. |
| Device Key / Auth (`DeviceKeyAuthHandler`) | High | No | No | No | No | None | High | Add unit tests for signature/format validation and strict negative cases. |
| Core UI Flows (Onboarding, Device/Group Lists, Navigation Screens) | Very High | No | No | No | Yes (15 deterministic flows incl. screenshot suite) | Medium-High | Medium | Next expansion: device map, group flow, and navigation start/stop including abort paths. |
| App Bootstrap (`miataruApp`, `AppState`, `AppDelegate`) | Medium | No | No | No | No | None | Medium-High | Add smoke integration tests for startup state, initial settings, and notification/permission branching. |

## Prioritized Backlog

| Priority | Gap | Why | Concrete Test Work |
|---|---|---|---|
| P0 (done 2026-02-27) | Activate existing extracted tests | Done: Unit/UI inventory is now linked in active targets | Move files to `miataruTests` and `miataruUITests` + target synchronization completed. |
| P1 (done 2026-02-27) | Move UI suite from smoke to stable core flows | Done: deterministic UI baseline covers launch, add-device, settings onboarding action, and QR baseline action | `ExtendedUITests` expanded to 5 robust scenarios. |
| P1 (done 2026-03-01) | Split screenshot/functional runs into dedicated schemes | Done: serial execution and explicitly triggerable screenshot suite for 10 languages + 2 device classes | New schemes `miataru-FunctionalUI`/`miataru-Screenshots`, test plans, `miataruScreenshotUITests`, scripts, and artifact export established. |
| P1 (done 2026-03-04) | Add unit coverage for retry/outbox resilience layer | Done: retry classifier/executor, persistent outbox semantics, and delivery coordinator behavior are unit-tested | Added `MiataruRequestExecutorTests`, `LocationUpdateOutboxStoreTests`, `LocationUpdateDeliveryCoordinatorTests`. |
| P1 (done 2026-03-09) | Add unit coverage for unknown-visitor alert logic | Done: evaluator selection/filter/cooldown rules, permission-flow branches, and localization key-completeness checks are now covered | Added `UnknownVisitorAlertEvaluatorTests` and `UnknownVisitorAlertLocalizationTests`. |
| P1 (done 2026-03-14) | Add settings regression coverage for defaults, localization, and navigation | Done: one-time migration behavior, runtime-vs-bundle default parity, localization key completeness, and advanced-options navigation are covered | Added `SettingsConfigurationTests` and one new `ExtendedUITests` scenario. |
| P2 (done 2026-03-14) | Protect multi-word device slogan input during editing | Done: live input keeps regular spaces while final save normalization still trims edges | Added `DeviceSloganSanitizationTests` and split slogan draft sanitization from save cleansing. |
| P1 | No integration tests for location/routing pipeline | Core app function with many dependencies | Integration test setup with fake location + fake API for route/update lifecycle. |
| P1 | No integration tests for unknown-visitor alert trigger wiring | New feature relies on two asynchronous trigger paths (`submit` + outbox flush) and server history deltas | Add integration tests for both trigger hooks and “from activation time” watermark behavior. |
| P1 | No tests for AllowedDevice sync | Data consistency and access logic are critical | Unit + integration tests for SyncQueue, conflict handling, repeatability. |
| P2 | Persistence stores barely covered | Failures often appear only with real data | Roundtrip and error-path tests for NSCoding/UserDefaults/FileStore. |
| P2 | Widget pipeline untested | User-visible inconsistencies between app/widget possible | Contract tests for shared payload and snapshot generation. |

## Maintenance Rule

Whenever tests are changed (added, removed, renamed, expanded), this file must be updated:

1. Update counters/facts in the matrix.
2. Re-assess `Coverage` and `Gap` for impacted areas.
3. Adjust backlog priorities if needed.
