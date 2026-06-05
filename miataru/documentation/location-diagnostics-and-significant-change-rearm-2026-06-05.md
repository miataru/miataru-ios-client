# Location Diagnostics Log and Significant-Change Re-Arm

Date: 2026-06-05

## Summary

This hardening patch adds an opt-in location diagnostics log to Location Tracking Details and performs a one-time significant-change monitor re-arm per app version/build when tracking is eligible.

The diagnostics log is intended for field debugging after app updates or background relaunches where Core Location state can appear active while the significant-change registration is no longer behaving as expected.

## Diagnostics Logging

`LocationDiagnosticsLogStore` owns the user-facing diagnostics buffer:

- The setting key is `location_diagnostics_logging_enabled` and defaults to `false`.
- Entries are persisted as JSON in Application Support so they survive app relaunches and background wakes.
- The buffer is capped at 1000 entries and trims older entries as a ring buffer.
- Disabling logging does not delete old entries; users can clear them explicitly from Location Tracking Details.
- The UI shows only the newest 20 entries. Export includes the full persisted buffer.

Each entry contains:

- `id`
- `timestamp`
- `level`
- `event`
- `summary`
- `result`
- `reason`
- `checks`
- `context`

The log is intentionally filtered. It records only location/tracking decisions such as launch restore, tracking-mode resolution, Core Location start/stop decisions, authorization changes, location callback acceptance/rejection, Smart frequent blockers, upload/outbox decisions, and significant-change re-arm status.

It does not mirror general debug console output, UI debug logs, map logs, device-cache logs, or unrelated app state.

## Privacy and Export

Diagnostic exports are JSON files created through the existing share-sheet flow.

Location values are rounded before they can enter the log:

- Latitude and longitude are rounded to four decimal places.
- Accuracy, speed, distance, and similar numeric values are stored as numeric values only.
- DeviceKey values and exact coordinates are not logged.

The export includes metadata such as generated time, app version, build number, maximum buffer size, entry count, and all retained entries.

## Disabled-State Overhead

Diagnostics are designed to be cheap when disabled:

- `LocationDiagnosticsLogStore.append` exits immediately when `isEnabled == false`.
- `checks`, `context`, and `timestamp` are `@autoclosure` parameters, so location contexts and check arrays passed inline are not built unless logging is enabled.
- Smart frequent activation/blocker diagnostics that require additional check construction are explicitly guarded by `diagnosticsLog.isEnabled`.

The significant-change re-arm status is still computed and persisted even when diagnostics logging is off because it is a visible Location Tracking Details status, not only a diagnostics-log entry.

## Significant-Change Re-Arm Policy

The app invokes `rearmSignificantChangeMonitorAfterFreshLaunchIfNeeded(buildIdentifier:reason:)` during startup after the normal launch restore path.

The pure policy helper allows a re-arm only when all checks pass:

- Location tracking is enabled.
- Authorization is `Always`.
- DeviceKey authentication is not blocked.
- The current version/build has not already attempted a re-arm.

If any check fails, the policy stores a `skipped` status with a reason and does not call Core Location stop/start APIs.

When all checks pass, the app:

1. Sets `allowsBackgroundLocationUpdates = true`.
2. Calls `stopMonitoringSignificantLocationChanges()`.
3. Clears the internal significant-change recovery anchor flag.
4. Calls `startMonitoringSignificantLocationChanges()`.
5. Sets the internal recovery anchor flag.
6. Persists the current build identifier so the re-arm is not repeated for the same build.
7. Persists a visible `attempted` status for Location Tracking Details.

This makes the update-start behavior defensive: it refreshes the significant-change registration once per build without repeatedly disturbing Core Location on every app start.

## UI

Location Tracking Details now contains a diagnostics card with:

- A diagnostics logging toggle.
- Current entry count and ring-buffer limit.
- Latest diagnostics event.
- Last significant-change re-arm status.
- Export action.
- Clear action.
- A compact list of the newest 20 entries.

## Localization

The diagnostics UI strings are localized across the supported app locales:

`da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`.

## Validation

Validated with:

```sh
./miataru/scripts/test-unit.sh
git diff --check
python3 -m json.tool miataru/miataru/Assets/Localizable.xcstrings
plutil -lint "miataru/miataru/SettingsManagers/App Settings/Settings.bundle/Root.plist"
```

The unit suite covers opt-in logging, persistence, ring-buffer trimming, rounded exports without DeviceKey leakage, re-arm eligibility, same-build suppression, skipped status reasons, Smart frequent blockers, and location accept/reject diagnostics.
