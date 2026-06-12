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
- `location-tracking-smart-frequent-background.md` - tracking resolver, foreground/background modes, manual frequent updates, Smart frequent runtime, diagnostics, retry/outbox behavior, notification sounds, and LocationManager modularization.
- `navigation-routing-and-mutual-navigation.md` - route camera behavior, heading refresh, mutual navigation UI, live ETA, compact arrival state, route ghost stabilization, and focused navigation.
- `device-history-cache-map-and-analysis.md` - history loading, cache refresh, user camera priority, and compact speed/altitude analysis.
- `device-security-devicekey-and-allowed-list.md` - DeviceKey recovery, emergency reset, security status, Allowed Device List read/sync behavior, onboarding DeviceKey flow, and location-permission touchpoints.
- `unknown-visitors-alerts-and-history.md` - unknown visitor alerts, filtering, enrichment, allowed-list handoff, add-device locking, case preservation, visitor-history refresh, and slogan display.
- `device-list-cache-slogans-and-settings.md` - device-list refresh behavior, central location/slogan cache ingest, DeviceID/name ambiguity, slogan cleansing, and settings refactor.
- `persistent-data-cleanup-and-widgets.md` - app-owned cache cleanup, widget device selection, widget/app cache synchronization, and related validation.

## Test Documentation

- `test-katalog.md` - active unit/UI/screenshot test inventory.
- `test-gap-matrix.md` - risk-based coverage and backlog matrix.
- `screenshot-test-workflow.md` - deterministic screenshot capture workflow.
- `test-build-repair-report-2026-02-27.md` - historical report for test wiring repair.

When tests change, update `test-katalog.md` and `test-gap-matrix.md` together.

## Standalone Historical Notes And Audits

These records are still useful but are not broad enough to merge into a topic reference yet:

- `documentation-audit-2026-05-22.md` - audit of previous documentation placement and maintenance risks.
- `rotation-lock-deprecation-fix-2026-03-03.md` - rotation lock deprecation fix note.
- `settings-advanced-options-hitbox-2026-06-11.md` - Advanced Options hitbox bug fix note.
- `audits/ipad-iphone-audit-2026-03-04.md` - iPad/iPhone parity audit.

## Maintenance Rules

- Keep `documentation/` as the single documentation root.
- Keep `Intent-Sprint/` separate from the current App Intents implementation reference.
- Prefer updating a consolidated topic reference when a change extends an existing topic.
- Add a new dated note only for one-off investigations or fixes that do not clearly belong to an existing topic.
- When a dated note becomes part of a broader topic, merge its information into the relevant topic document, retain the source filename in "Source Notes Consolidated", then remove the superseded note.

## Current Project Facts

- Current app version: `3.2.2`
- iOS deployment target: `18.6`
- Platforms: iPhone and iPad app target plus WidgetKit extension
- Locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`
- Primary current domains: DeviceKey, allowed-device list, unknown visitors, widgets, App Intents/Siri/Shortcuts, navigation, device history analytics, Smart/manual frequent background tracking, string-catalog QA, update outbox, cache cleanup, and active test automation
