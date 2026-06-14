# Agent Rules

## Commit Workflow

- Before every commit that includes code or project changes, create a `.specstory` history entry for the current chat in `.specstory/history/` using the existing timestamped filename and markdown format.
- Stage and include that `.specstory` file in the same commit.
- Update `CHANGELOG.md` in the same commit following the main app `MARKETING_VERSION` (`miataru.xcodeproj/project.pbxproj`, miataru target).
- Write commit messages in English.

## Test Documentation Memory

- Whenever tests are added, changed, renamed, moved, or removed, update `documentation/test-gap-matrix.md` in the same work item.
- In the same change, also update `documentation/test-katalog.md` so catalog and matrix stay consistent.
- Keep those updates targeted: locate the relevant test ID, suite, component, or backlog row first, then edit only the affected lines instead of reading or rewriting the full documents.
- For a single focused regression test, a small local catalog row/backlog adjustment is enough unless the change materially alters broader coverage counts or priorities.

## Localization Catalog Memory

- App string catalogs live under `miataru/miataru/Assets/Localization/`.
- When adding or moving user-facing strings, put them in the existing themed `.xcstrings` file that owns that feature area and use the matching explicit table name in Swift. If no existing catalog fits, create a new themed `.xcstrings` file in `Assets/Localization/` instead of expanding `Localizable.xcstrings`.
- Keep `AppShortcuts.xcstrings` phrase-only: shortcut trigger phrases with `${applicationName}` belong there, while App Intent titles, parameters, summaries, dialogs, entities, errors, and shortcut tile titles belong in `AppIntents.xcstrings`.
- Keep Settings.bundle strings in `SettingsManagers/App Settings/Settings.bundle/*.lproj/Root.strings` synchronized with their matching app string-catalog keys where the same setting is shown in-app.

## Token Discipline

- Prefer narrow inspection commands: `rg --files`, targeted `rg`, `sed -n`, `git diff --name-only`, and path-scoped `git status --short -- <paths>`.
- Before broad `rg`, `git diff --stat`, or full-document reads, run a compact discovery step such as `rg --files`, `git diff --name-only`, `sed -n '<start>,<end>p'`, or `miataru/scripts/context-summary.sh`.
- Avoid full-file reads for large documents, test inventories, string catalogs, generated files, and JSON payloads unless the full content is genuinely needed; start with narrow line ranges or key-specific reads.
- For `.xcstrings` and other large JSON files, inspect counts, key lists, duplicate checks, or targeted keys with `jq`/small scripts instead of dumping whole files.
- Run test/build output through project scripts or filtered pipelines by default. Normal unit/UI test scripts use `TEST_OUTPUT=summary`, store the full `xcodebuild` log under `miataru/artifacts/test-logs/`, and print only focused diagnostics and summaries.
- Use `TEST_OUTPUT=full` only when the focused summary and saved log path are insufficient.
- Use `xcodebuild ... -quiet` for expected-success builds. When investigating failures or warnings, filter output first with focused patterns such as `error:`, `warning:`, `TEST FAILED`, `TEST SUCCEEDED`, or the specific diagnostic text.
- If a test fails, inspect the focused failure output first and expand to full logs only when the failure summary is insufficient.
- For running tests, poll exit status, summary lines, or focused log filters; do not repeatedly print full live logs.
- Split large work into separate turns or commits when it crosses more than one major concern, such as implementation, localization/catalog migration, test infrastructure, documentation cleanup, and warning cleanup.
- Actively split tasks that combine implementation, refactor, tests, documentation, warning cleanup, and commit work into smaller phases when the context starts to sprawl.
- For catalog moves, generated-file changes, and broad refactors, verify with compact summary scripts instead of repeatedly printing long file contents or large diffs.
- Keep final reports compact: summarize changed areas, verification commands/results, commit hashes, and important caveats. Do not paste long command output unless explicitly requested.

## Simulator / Test Device Memory

- Always use the dedicated Miataru simulator devices for simulation and testing. Do not run tests against an arbitrary open or booted Simulator window.
- For normal unit and UI tests, use `miataru Tests - iPhone 16` through the project scripts or an explicit `xcodebuild -destination` resolved to that simulator's UDID.
- For screenshot tests, use the dedicated screenshot simulators created by `miataru/scripts/restore-test-simulators.sh`: `miataru Screenshots - iPhone 16 Pro Max` and `miataru Screenshots - iPad Pro 13-inch (M5)`.
- Before testing, create or restore the dedicated devices with `cd miataru && ./scripts/restore-test-simulators.sh` if they are missing.
- Avoid `-destination 'platform=iOS Simulator,name=...'` values for generic Apple simulator names, `-destination 'generic/platform=iOS Simulator'`, and any workflow that implicitly selects the currently booted simulator.
