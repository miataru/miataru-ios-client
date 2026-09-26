# Documentation Map

This directory is the canonical project documentation root. Do not add new project documentation under `miataru/documentation/`.

The current structure favors living topic references over many small dated notes. Older notes that covered the same topic have been coalesced into the topic documents below, with their source filenames retained inside each consolidated document for traceability.

## Canonical Living Documents

- `../README.md` - project overview, current app state, architecture, build/test entry points
- `../miataru/PROJECT_OVERVIEW.md` - architecture and domain overview for development context
- `../miataru/APP_FEATURES.md` - user/developer feature guide
- `../miataru/DEVELOPMENT.md` - local development, testing, debugging, and implementation rules
- `../miataru/APP_STORE_DESCRIPTION.md` - App Store copy source and screenshot guidance
- `../miataru/CHANGELOG.md` - release notes by marketing version
- `../3rd party licenses.md` - dependency license summary
- `../miataru/Libraries/MiataruClientSwift/README.md` - local Miataru API client usage

## Consolidated Topic References

- `app-intents-current-shortcuts-and-manual-validation.md` - current Siri/Shortcuts implementation, service boundaries, privacy rules, App Intents test coverage, and manual validation.
- `Intent-Sprint/` - separate iOS 26 schema-readiness roadmap for App Intents, Entity/Intent Schemas, IndexedEntity/Spotlight, IntentValueQuery, View Annotations, and AppIntentsTesting.
- `Places-Sprint/` - future Places UI/UX concept, requirements, privacy rules, and watch-planning notes.
- `location-tracking-smart-frequent-background.md` - tracking resolver, foreground/background modes, manual frequent updates, Smart frequent runtime, diagnostics, retry/outbox behavior, notification sounds, and LocationManager modularization.
- `navigation-routing-and-mutual-navigation.md` - route camera behavior, heading refresh, mutual navigation UI, live ETA, compact arrival state, route ghost stabilization, and focused navigation.
- `device-history-cache-map-and-analysis.md` - history loading, cache refresh, user camera priority, and compact speed/altitude analysis.
- `device-security-devicekey-and-allowed-list.md` - DeviceKey recovery, emergency reset, security status, Allowed Device List read/sync behavior, onboarding DeviceKey flow, and location-permission touchpoints.
- `unknown-visitors-alerts-and-history.md` - unknown visitor alerts, filtering, enrichment, allowed-list handoff, add-device locking, case preservation, visitor-history refresh, and slogan display.
- `known-device-access-history-storage-limits.md` - per-device known VisitorHistory access logging limits, 60-minute summary windows, storage bounds, and cleanup triggers.
- `device-list-cache-slogans-and-settings.md` - device-list refresh behavior, central location/slogan cache ingest, DeviceID/name ambiguity, slogan cleansing, and settings refactor.
- `persistent-data-cleanup-and-widgets.md` - app-owned cache cleanup, widget device selection, widget/app cache synchronization, and related validation.

## Process and Graph

- [Repository agent rules](../AGENTS.md) and [Miataru rules](../miataru/AGENTS.md) define scoped work, opt-in team routing, build increments, and release evidence.
- [Verification map](../miataru/scripts/verification-map.json), [verification runner](../miataru/scripts/verify.py), and [metadata preflight](../miataru/scripts/verify-metadata.py) define the executable gates.
- [Release workflow](release-workflow.md) defines the checked-commit, optional physical-iPhone, archive, signing/dSYM, upload, and Apple-processing evidence boundaries.
- [SwiftProjectGraph](../tools/SwiftProjectGraph/README.md) is the local source/document navigation index; [installation and refresh](../tools/SwiftProjectGraph/INSTALL.md) explain its lifecycle.

## Test Documentation

- `test-katalog.md` - active unit/UI/screenshot test inventory.
- `test-gap-matrix.md` - risk-based coverage and backlog matrix.
- `screenshot-test-workflow.md` - deterministic screenshot capture workflow.
- `test-build-repair-report-2026-02-27.md` - historical report for test wiring repair.

When tests change, update `test-katalog.md` and `test-gap-matrix.md` together.

## Standalone Historical Notes And Audits

These records are still useful but are not broad enough to merge into a topic reference yet:

- `audits/documentation-audit-2026-05-22.md` - audit of previous documentation placement and maintenance risks.
- `rotation-lock-deprecation-fix-2026-03-03.md` - rotation lock deprecation fix note.
- `settings-advanced-options-hitbox-2026-06-11.md` - Advanced Options hitbox bug fix note.
- `audits/ipad-iphone-audit-2026-03-04.md` - iPad/iPhone parity audit.

## Complete Inventory and Historical Plans

[Documentation inventory](DOCUMENTATION_INVENTORY.md) explains the status and review boundaries. The [file-by-file TSV](DOCUMENTATION_INVENTORY.tsv) records every versioned or newly added document, including third-party documents and historical `.specstory` records. Historical records are retained as evidence; active requirements and flows do not require creating chat histories.

The following 30 Cursor plans are historical proposals. Their headings describe the original plan, while Current behavior is determined by app code and the living topic references above.

| Plan | Status |
|---|---|
| [Test-Neustrukturierung mit dedizierten Schemes und Screenshot-Suite (seriell, 1 Simulator)](<../miataru/.cursor/plans/2026-03-01 Test Screenshot Automation Plan.md>) | historisch |
| [Miataru API Retry/Resilience Plan (ohne Änderungen an MiataruClientSwift)](<../miataru/.cursor/plans/2026-03-04_miataru_api_retry_strategy_no_client_changes.plan.md>) | historisch |
| [Allowed Device List Feature — Implementation Plan](<../miataru/.cursor/plans/Allowed Device List Feature-concept.md>) | historisch |
| [allowed device list feature 032669d5.plan](<../miataru/.cursor/plans/allowed_device_list_feature_032669d5.plan.md>) | historisch |
| [Animated polyline on navigation route (full route)](<../miataru/.cursor/plans/animated_route_in_navigate_mode_71f7d07a.plan.md>) | historisch |
| [Deduplicate Device Location Refresh Pipeline](<../miataru/.cursor/plans/deduplicate_device_location_refresh_c34cc28a.plan.md>) | historisch |
| [DeviceKey Authentication Plan](<../miataru/.cursor/plans/devicekey_auth_flow_aec977ce.plan.md>) | historisch |
| [devicekey usage audit 5be4fa9c.plan](<../miataru/.cursor/plans/devicekey_usage_audit_5be4fa9c.plan.md>) | historisch |
| [Device Tap Nearby Sheet Analysis](<../miataru/.cursor/plans/devicetapnearbysheetdiagnosis_a66a9859.plan.md>) | historisch |
| [Fix DeviceHistoryMapView Zoom and Data Retrieval](<../miataru/.cursor/plans/fix_devicehistorymapview_zoom_and_data_retrieval_a5ed1d34.plan.md>) | historisch |
| [Incorporate](<../miataru/.cursor/plans/ghostspeedincorporation_5201c16a.plan.md>) | historisch |
| [history map refactor 9ad9659b.plan](<../miataru/.cursor/plans/history-map-refactor_9ad9659b.plan.md>) | historisch |
| [implement getvisitorhistory api 6b929d34.plan](<../miataru/.cursor/plans/implement_getvisitorhistory_api_6b929d34.plan.md>) | historisch |
| [improve map tapability d170647b.plan](<../miataru/.cursor/plans/improve_map_tapability_d170647b.plan.md>) | historisch |
| [Low Power Mode Gating Plan](<../miataru/.cursor/plans/low-power-gate-effects_980105a3.plan.md>) | historisch |
| [macos native support 2a05c700.plan](<../miataru/.cursor/plans/macos_native_support_2a05c700.plan.md>) | historisch |
| [Merge Groups Into Devices](<../miataru/.cursor/plans/merge_groups_into_devices_5173d21e.plan.md>) | historisch |
| [miataru ios widgets be2ab38b.plan](<../miataru/.cursor/plans/miataru_ios_widgets_be2ab38b.plan.md>) | historisch |
| [mutual navigation and visitor history 0bbbadc5.plan](<../miataru/.cursor/plans/mutual_navigation_and_visitor_history_0bbbadc5.plan.md>) | historisch |
| [Mutual Navigation Sound Cues](<../miataru/.cursor/plans/mutual_navigation_sounds_7835d78c.plan.md>) | historisch |
| [navigation overlay mode a06f0fbb.plan](<../miataru/.cursor/plans/navigation_overlay_mode_a06f0fbb.plan.md>) | historisch |
| [Implementation Plan: Periodic Location Updates](<../miataru/.cursor/plans/periodic_location_updates_fa95e72d.plan.md>) | historisch |
| [Playback respects manual zoom (history map)](<../miataru/.cursor/plans/playback_respects_manual_zoom_7fac64f4.plan.md>) | historisch |
| [Post-Update Onboarding Replay](<../miataru/.cursor/plans/post_update_onboarding_15483174.plan.md>) | historisch |
| [reverse navigation double tap mode 241b4efc.plan](<../miataru/.cursor/plans/reverse_navigation_double-tap_mode_241b4efc.plan.md>) | historisch |
| [route request optimization 8e204d1a.plan](<../miataru/.cursor/plans/route_request_optimization_8e204d1a.plan.md>) | historisch |
| [Improve Timeline Scrub Performance](<../miataru/.cursor/plans/timeline_scrub_performance_2824e1c0.plan.md>) | historisch |
| [Turn Feedback Cues Plan](<../miataru/.cursor/plans/turn_feedback_cues_5fce8e08.plan.md>) | historisch |
| [visitor log inline b90777eb.plan](<../miataru/.cursor/plans/visitor-log-inline_b90777eb.plan.md>) | historisch |
| [Visitor History Auto-Refresh Plan](<../miataru/.cursor/plans/visitorhistoryautorefresh_9a355328.plan.md>) | historisch |

## Maintenance Rules

- Keep `documentation/` as the single documentation root for project topic references; root and `miataru/` retain their living overview and development entry points.
- Keep `Intent-Sprint/` separate from the current App Intents implementation reference.
- Prefer updating a consolidated topic reference when a change extends an existing topic.
- Add a new dated note only for one-off investigations or fixes that do not clearly belong to an existing topic.
- When a dated note becomes part of a broader topic, merge its information into the relevant topic document, retain the source filename in "Source Notes Consolidated", then remove the superseded note.

## Current Project Facts

- Current development checkout: `3.5` build `3` (app and widget). App Store Connect accepted the build 3 upload on 2026-09-26; Apple processing completion, App Review, and store availability remain unverified.
- iOS deployment target: `18.6`
- Platforms: iPhone and iPad app target plus WidgetKit extension
- Locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`
- Primary current domains: DeviceKey, allowed-device list, unknown visitors, widgets, App Intents/Siri/Shortcuts, navigation, device history analytics, Smart/manual frequent background tracking, string-catalog QA, update outbox, cache cleanup, and active test automation
