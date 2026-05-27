# Documentation Map

This directory contains both living documentation and dated implementation records.

## Canonical Living Documents

- `../README.md` - project overview, current app state, architecture, build/test entry points
- `../miataru/PROJECT_OVERVIEW.md` - architecture and domain overview for development context
- `../miataru/APP_FEATURES.md` - user/developer feature guide
- `../miataru/DEVELOPMENT.md` - local development, testing, debugging, and implementation rules
- `../miataru/APP_STORE_DESCRIPTION.md` - App Store copy source and screenshot guidance
- `../miataru/CHANGELOG.md` - release notes by marketing version
- `../3rd party licenses.md` - dependency license summary
- `../miataru/Libraries/MiataruClientSwift/README.md` - local Miataru API client usage

## Test Documentation

- `test-katalog.md` - active unit/UI/screenshot test inventory
- `test-gap-matrix.md` - risk-based coverage and backlog matrix
- `screenshot-test-workflow.md` - deterministic screenshot capture workflow
- `test-build-repair-report-2026-02-27.md` - historical report for test wiring repair
- `device-id-name-ambiguity-handling-2026-05-27.md` - Device ID duplicate blocking and duplicate-name disambiguation

When tests change, update `test-katalog.md` and `test-gap-matrix.md` together.

## Historical Implementation Notes

Files named with dates, for example `device-history-loading-feedback-2026-04-24.md`, document a specific investigation, implementation, or fix at that time. The same applies to dated files under `../miataru/documentation/`.

These files are retained as historical evidence. They should not be edited merely because newer work superseded them. Update or add a new dated note when a follow-up change needs its own reasoning record.

## Current Project Facts

- Current app version: `3.1.17`
- iOS deployment target: `18.6`
- Platforms: iPhone and iPad app target plus WidgetKit extension
- Locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`
- Primary current domains: DeviceKey, allowed-device list, unknown visitors, widgets, navigation, frequent background tracking, update outbox, cache cleanup, and active test automation

The latest documentation audit is `documentation-audit-2026-05-22.md`.
