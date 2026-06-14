# Agent Rules

## Commit Workflow

- Before every commit that includes code or project changes, create a `.specstory` history entry for the current chat in `.specstory/history/` using the existing timestamped filename and markdown format.
- Stage and include that `.specstory` file in the same commit.
- Update `CHANGELOG.md` in the same commit following the main app `MARKETING_VERSION` (`miataru.xcodeproj/project.pbxproj`, miataru target).
- Write commit messages in English.

## Test Documentation Memory

- Whenever tests are added, changed, renamed, moved, or removed, update `documentation/test-gap-matrix.md` in the same work item.
- In the same change, also update `documentation/test-katalog.md` so catalog and matrix stay consistent.

## Localization Catalog Memory

- App string catalogs live under `miataru/miataru/Assets/Localization/`.
- When adding or moving user-facing strings, put them in the existing themed `.xcstrings` file that owns that feature area and use the matching explicit table name in Swift. If no existing catalog fits, create a new themed `.xcstrings` file in `Assets/Localization/` instead of expanding `Localizable.xcstrings`.
- Keep `AppShortcuts.xcstrings` phrase-only: shortcut trigger phrases with `${applicationName}` belong there, while App Intent titles, parameters, summaries, dialogs, entities, errors, and shortcut tile titles belong in `AppIntents.xcstrings`.
- Keep Settings.bundle strings in `SettingsManagers/App Settings/Settings.bundle/*.lproj/Root.strings` synchronized with their matching app string-catalog keys where the same setting is shown in-app.

## Simulator / Test Device Memory

- Always use the dedicated Miataru simulator devices for simulation and testing. Do not run tests against an arbitrary open or booted Simulator window.
- For normal unit and UI tests, use `miataru Tests - iPhone 16` through the project scripts or an explicit `xcodebuild -destination` resolved to that simulator's UDID.
- For screenshot tests, use the dedicated screenshot simulators created by `miataru/scripts/restore-test-simulators.sh`: `miataru Screenshots - iPhone 16 Pro Max` and `miataru Screenshots - iPad Pro 13-inch (M5)`.
- Before testing, create or restore the dedicated devices with `cd miataru && ./scripts/restore-test-simulators.sh` if they are missing.
- Avoid `-destination 'platform=iOS Simulator,name=...'` values for generic Apple simulator names, `-destination 'generic/platform=iOS Simulator'`, and any workflow that implicitly selects the currently booted simulator.
