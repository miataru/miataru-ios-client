---
name: Allowed Device List Feature
overview: Implement optional per-device access control (current location and history) with one-way activation, server synchronization, and unknown visitor management. The feature requires DeviceKey and cannot be disabled once enabled.
todos:
  - id: phase1-data-model
    content: Extend KnownDevice with ACL fields (hasCurrentLocationAccess, hasHistoryAccess) and update NSCoding for backward compatibility
    status: completed
  - id: phase1-settings
    content: Add allowedDeviceListEnabled flag to SettingsManager with UserDefaults persistence
    status: completed
  - id: phase1-ignored-store
    content: Create IgnoredVisitorDeviceStore singleton for dismissed unknown devices
    status: completed
  - id: phase1-manager
    content: Implement AllowedDeviceListManager with payload building, sync queue, and transactional rollback
    status: completed
  - id: phase2-onboarding
    content: Create iPhone_8_OnboardingAllowedDeviceListView and integrate into onboarding containers
    status: completed
  - id: phase2-settings-ui
    content: Add settings entry for allowed device list feature with status display
    status: completed
  - id: phase3-add-dialog
    content: Add conditional ACL toggles to iPhone_AddDeviceView and wire sync on save
    status: completed
  - id: phase3-edit-dialog
    content: Add conditional ACL toggles to iPhone_EditDeviceView and wire sync on save
    status: completed
  - id: phase3-remove-sync
    content: Wire device removal to sync full list when feature enabled
    status: completed
  - id: phase4-unknown-section
    content: Add unknown visitors section to iPhone_DevicesView with allow/ignore actions
    status: completed
  - id: phase5-localization
    content: Add all feature strings to Localizable.xcstrings and run export workflow
    status: completed
  - id: phase5-testing
    content: Write unit tests for payload mapping, backward compatibility, and sync queue
    status: completed
  - id: phase5-migration
    content: "Verify migration safety: first launch saves ACL defaults, no silent server calls"
    status: completed
isProject: false
---

# Allowed Device List Feature — Implementation Plan

## Current State

The codebase already provides:

- API support: `MiataruAPIClient.setAllowedDeviceList()` in `[Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift](Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift)` with `MiataruAllowedDevice` payload structure
- DeviceKey management: `SettingsManager.deviceKey` in `[miataru/SettingsManagers/App Settings/SettingsManager.swift](miataru/SettingsManagers/App Settings/SettingsManager.swift)`
- Device persistence: `KnownDevice` and `KnownDeviceStore` in `[miataru/SettingsManagers/App Settings/Devices/KnownDevice.swift](miataru/SettingsManagers/App Settings/Devices/KnownDevice.swift)` and `[miataru/SettingsManagers/App Settings/Devices/KnownDeviceStore.swift](miataru/SettingsManagers/App Settings/Devices/KnownDeviceStore.swift)`
- Visitor history: `VisitorHistoryViewModel` in `[miataru/views/iPhone/iPhone_VisitorHistoryView.swift](miataru/views/iPhone/iPhone_VisitorHistoryView.swift)` with `sortedVisitors` property

## Architecture Changes

### Data Model Extensions

**1. Extend `KnownDevice` class** (`[miataru/SettingsManagers/App Settings/Devices/KnownDevice.swift](miataru/SettingsManagers/App Settings/Devices/KnownDevice.swift)`)

- Add `@Published var hasCurrentLocationAccess: Bool = true`
- Add `@Published var hasHistoryAccess: Bool = true`
- Update `init(coder:)` to decode with defaults (`true/true`) for backward compatibility
- Update `encode(with:)` to include new keys

**2. Add feature flag to `SettingsManager**` (`[miataru/SettingsManagers/App Settings/SettingsManager.swift](miataru/SettingsManagers/App Settings/SettingsManager.swift)`)

- Add `@Published var allowedDeviceListEnabled: Bool` with `UserDefaults` persistence
- Add `Keys.allowedDeviceListEnabled` constant
- Initialize from `UserDefaults` with default `false`

**3. Create `IgnoredVisitorDeviceStore**` (new file)

- Singleton store for device IDs explicitly dismissed from unknown visitor list
- Persist to `UserDefaults` or separate plist file
- Methods: `addIgnored(deviceID:)`, `isIgnored(deviceID:)`, `removeIgnored(deviceID:)`

### Domain Service Layer

**4. Create `AllowedDeviceListManager**` (new file: `miataru/SettingsManagers/App Settings/Devices/AllowedDeviceListManager.swift`)

- Singleton service for ACL synchronization
- Responsibilities:
  - Build API payload from `KnownDeviceStore.devices` → `[MiataruAllowedDevice]`
  - Enforce preconditions (DeviceKey exists, server URL valid)
  - Call `MiataruAPIClient.setAllowedDeviceList` with retry logic
  - Serialized sync queue to prevent race conditions
  - Transactional rollback on final sync failure
- Public methods:
  - `activateAllowedDeviceList() async throws`
  - `syncAllowedDeviceListIfEnabled(trigger: SyncTrigger) async throws`
  - `upsertDeviceACL(deviceID:hasCurrentLocationAccess:hasHistoryAccess:) async throws`
  - `removeDeviceAndSync(deviceID:) async throws`
- Error handling: map API errors to user-facing messages, log trigger context

### UI Integration

**5. Onboarding page** (new file: `miataru/views/iPhone/Onboarding/iPhone_8_OnboardingAllowedDeviceListView.swift`)

- Reuse `devicekey` image asset
- Title: "Control which devices can access your location data"
- Body: explains optional feature, DeviceKey requirement, irreversible activation
- CTA logic:
  - If no DeviceKey: primary action opens DeviceKey setup sheet
  - If DeviceKey exists and feature disabled: show enable button
  - If already enabled: show configured state
- Add to onboarding containers: `[miataru/views/iPhone/iPhone_OnboardingContainerView.swift](miataru/views/iPhone/iPhone_OnboardingContainerView.swift)` and iPad/Mac equivalents

**6. Settings entry** (`[miataru/views/iPhone/Settings Views/iPhone_SettingsView.swift](miataru/views/iPhone/Settings Views/iPhone_SettingsView.swift)`)

- Add section for allowed device list feature
- Show feature status (enabled/disabled)
- If enabled: show informational text, no disable action
- If disabled: show enable action (triggers activation flow)

**7. Device dialogs — Add Device** (`[miataru/views/iPhone/Devices Views/iPhone_AddDeviceView.swift](miataru/views/iPhone/Devices Views/iPhone_AddDeviceView.swift)`)

- Conditional UI: only show ACL toggles when `SettingsManager.shared.allowedDeviceListEnabled == true`
- Defaults: `hasCurrentLocationAccess = true`, `hasHistoryAccess = false` for new devices
- On save: add to `KnownDeviceStore`, then call `AllowedDeviceListManager.syncAllowedDeviceListIfEnabled(trigger: .add)`
- Rollback on sync failure: restore pre-add snapshot, show error

**8. Device dialogs — Edit Device** (`[miataru/views/iPhone/Devices Views/iPhone_EditDeviceView.swift](miataru/views/iPhone/Devices Views/iPhone_EditDeviceView.swift)`)

- Conditional UI: only show ACL toggles when feature enabled
- Load existing ACL values from `KnownDevice`
- On save: update `KnownDevice`, then sync full list
- Rollback on sync failure: restore previous ACL values

**9. Device removal** (`[miataru/views/iPhone/iPhone_DevicesView.swift](miataru/views/iPhone/iPhone_DevicesView.swift)`)

- When feature enabled and device deleted: capture snapshot, remove locally, sync full list
- Rollback on sync failure: restore device with previous ACLs

**10. Unknown visitors section** (`[miataru/views/iPhone/iPhone_DevicesView.swift](miataru/views/iPhone/iPhone_DevicesView.swift)`)

- Data source: filter `VisitorHistoryViewModel.sortedVisitors` for unique DeviceIDs not in `KnownDeviceStore` and not in `IgnoredVisitorDeviceStore`
- UI: new section above known devices list, only visible when list is non-empty
- Row display: DeviceID, last seen timestamp, optional location snippet
- Actions:
  - **Allow**: open `iPhone_AddDeviceView` with prefilled DeviceID + ACL controls (defaults: `current=true`, `history=false`)
  - **Ignore**: add to `IgnoredVisitorDeviceStore`, remove from section immediately
- Optional: add "Ignored Devices" management screen in settings to reverse ignore actions

### Synchronization Model

**11. Full-list sync on mutations**
When `allowedDeviceListEnabled == true`, trigger full-list sync on:

- Device add (via `AllowedDeviceListManager.syncAllowedDeviceListIfEnabled(trigger: .add)`)
- Device edit/ACL change (trigger: `.edit`)
- Device remove (trigger: `.remove`)
- Unknown device allow (trigger: `.unknownAllow`)
- Initial activation (trigger: `.activation`)

**12. Transactional rollback pattern**
For all mutations when feature enabled:

1. Capture snapshot: full `KnownDeviceStore.devices` array (including ACL values, ordering)
2. Apply local mutation optimistically
3. Attempt sync with retry policy (exponential backoff)
4. On final failure: restore snapshot, persist immediately, show error banner with retry action
5. Log telemetry: trigger, retry count, error class, rollback performed

### Migration Strategy

**13. Backward compatibility**

- `KnownDevice.init(coder:)`: decode ACL keys with defaults `true/true` if absent
- `SettingsManager.init()`: `allowedDeviceListEnabled` defaults to `false` when key missing
- First launch after update: verify all devices have ACL values in-memory, save archive once (no server call)

**14. Migration safety**

- Existing users remain with feature disabled until explicit activation
- No silent server ACL writes before opt-in
- Older archived `knownDevices.plist` files load gracefully with default ACLs

### Internationalization

**15. Localization strings** (`[miataru/Assets/Localizable.xcstrings](miataru/Assets/Localizable.xcstrings)`)
Add keys for:

- Feature title, body, CTA labels
- ACL toggle labels/descriptions ("Current Location Access", "History Access")
- Unknown visitor section title, allow/ignore buttons
- Sync error messages, retry actions
- Irreversible activation warning text
- Run localization export workflow for all supported languages

### Error Handling

**16. Error scenarios**

- API failures: non-destructive to local edits, explicit retry action
- DeviceKey missing: show prerequisite prompt
- Network offline: queue pending sync, show unsynced indicator
- Race conditions: serialized sync queue in `AllowedDeviceListManager`
- Case sensitivity: normalize DeviceID casing before compare/store/sync

## Testing Requirements

**17. Unit tests**

- Payload mapping: `KnownDevice` → `MiataruAllowedDevice`
- Backward decode compatibility for old archives
- Activation preconditions (with/without DeviceKey)
- Sync queue serialization

**18. Integration tests**

- Activation happy path → flag persisted
- Add/edit/remove triggers full-list sync when enabled
- API failure preserves local changes, exposes retry

**19. Manual QA**

- Onboarding branching (no key / key present / enabled)
- Add/edit toggle defaults and persistence
- Unknown visitor section visibility and actions
- Localization spot checks
- Existing user upgrade path (no forced opt-in)
- Rollback behavior on sync failures

## Definition of Done

Feature complete when:

1. Users can optionally enable allowed-device-list only after DeviceKey setup
2. Initial full ACL list seeded to server with correct defaults (`true/true` for existing devices)
3. Device add/edit/remove fully re-syncs ACL list when enabled
4. Unknown visitor devices actionable in devices screen (allow/ignore)
5. Feature cannot be disabled once enabled
6. Onboarding + settings + localized copy explain privacy/security implications
7. Automated and manual checks pass
8. Backward compatibility verified for existing users

