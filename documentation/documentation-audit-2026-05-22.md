# Documentation Audit - 2026-05-22

## Scope

This audit reviewed commits on the current branch since `2026-01-01` and compared the living documentation against the current codebase, project settings, test setup, and dependency list.

Reviewed as canonical living documentation:

- `README.md`
- `miataru/PROJECT_OVERVIEW.md`
- `miataru/APP_FEATURES.md`
- `miataru/DEVELOPMENT.md`
- `miataru/APP_STORE_DESCRIPTION.md`
- `miataru/CHANGELOG.md`
- `documentation/test-katalog.md`
- `documentation/test-gap-matrix.md`
- `documentation/screenshot-test-workflow.md`
- `3rd party licenses.md`
- `miataru/Libraries/MiataruClientSwift/README.md`

Dated implementation notes under `documentation/` and `miataru/documentation/` were treated as historical records. Third-party package READMEs under `miataru/Libraries/*` were not rewritten except for the project-owned `MiataruClientSwift` README.

## Commit Review Summary

Since January 2026 the project moved substantially beyond the older README/project-overview state:

- App metadata reached version `3.1.14` and iOS deployment target `18.6`.
- Localization expanded to ten app locales and matching Settings.bundle localizations.
- Widget support matured into text/map widgets with AppIntent device selection, App Group payloads, map snapshots, live fallback fetches, and widget/app cache reconciliation.
- DeviceKey became a full authentication and recovery system rather than a small QR/settings adjunct.
- Allowed Device List, security status, device slogans, visitor history, unknown visitor flows, and unknown visitor alerts were added or significantly expanded.
- Navigation gained route caches, focused double-tap mode, turn-by-turn overlay integration, route-progress ghost calculation, route request limits, stale-response guards, and current ghost stabilization.
- Background tracking gained an explicit frequent mode with distance/duration/delivery/visitor-check controls, low-battery auto-disable, reminders, and expiration handling.
- `updateLocation` delivery gained app-level retry and a persistent FIFO outbox with configurable retention/capacity and server URL retarget/discard behavior.
- Device location/slogan/widget caches were centralized, timestamp-ordered, and cleaned up at startup/removal.
- Test infrastructure was repaired and split into active unit, functional UI, and screenshot schemes/scripts with maintained catalog and gap matrix.

## Documentation Drift Found

- Several primary docs still described only iOS 18.0, not the current 18.6 deployment target.
- Project docs still described only three languages in places, while the app now supports ten locales.
- The app feature guide claimed Mac currently mirrors the iPhone experience, but there is no shipping Mac target.
- Onboarding was still described as a six-step wizard despite the current base-plus-optional page composition.
- Widget data flow, App Group files, and configurable widget selection were not described in the primary docs.
- Frequent background tracking, low-battery auto-disable, delayed delivery, visitor-check cadence, and update outbox behavior were underdocumented.
- DeviceKey, Allowed Device List, unknown visitor alerts, security status, and slogan/cache behavior were scattered across dated notes but not consolidated in the living docs.
- `3rd party licenses.md` was missing `NavigationOverlayKit`.
- The local `MiataruClientSwift` README did not reflect current endpoint coverage or the app-vs-library retry boundary.

## Updates Made

- Rewrote `README.md` as the current top-level project reference.
- Rewrote `miataru/PROJECT_OVERVIEW.md` around current architecture, domains, dependencies, testing, and priorities.
- Rewrote `miataru/APP_FEATURES.md` as a current user/developer feature guide.
- Rewrote `miataru/DEVELOPMENT.md` with current structure, scripts, retry/outbox, widgets, unknown visitors, navigation, and troubleshooting.
- Rewrote `miataru/APP_STORE_DESCRIPTION.md` with current marketing copy, version 3.1.14 "What's New", screenshot guidance, and current differentiators.
- Updated `miataru/Libraries/MiataruClientSwift/README.md` with current API coverage and the app-level retry/outbox boundary.
- Added `NavigationOverlayKit` to `3rd party licenses.md`.
- Added `documentation/README.md` to distinguish canonical living docs from historical dated notes.

## Current Canonical Facts

- Version: `3.1.14`
- Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 18.6`
- Swift project setting: `SWIFT_VERSION = 5.0`
- Target device family: iPhone and iPad
- App Group: `group.com.miataru.ios`
- Active test targets: `miataruTests`, `miataruUITests`, `miataruScreenshotUITests`
- Active shared schemes: `miataru-FunctionalUI`, `miataru-Screenshots`
- Primary app locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`

## Maintenance Guidance

- Keep `README.md`, `PROJECT_OVERVIEW.md`, `APP_FEATURES.md`, and `DEVELOPMENT.md` aligned with app architecture changes.
- Keep `APP_STORE_DESCRIPTION.md` aligned with the latest user-visible release scope before App Store submission.
- Do not rewrite dated implementation notes to "make them current"; add a new dated note for follow-up reasoning.
- Keep test catalog and gap matrix synchronized whenever test files or schemes change.
- Update `3rd party licenses.md` whenever a new package is added to the app target.
