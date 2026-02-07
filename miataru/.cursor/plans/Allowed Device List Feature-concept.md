# Allowed Device List Feature — Implementation Plan

## 1) Current state (what already exists)

Based on the current codebase:

- The API layer already supports `setAllowedDeviceList` with per-device access flags (`hasCurrentLocationAccess`, `hasHistoryAccess`) and requires both `DeviceID` and `DeviceKey`. This is exposed in `MiataruAPIClient.setAllowedDeviceList(...)`.
- The app already supports optional DeviceKey management (`SettingsManager.deviceKey`, onboarding page, settings sheet, auth mismatch handling).
- Known devices are persisted via `KnownDeviceStore` and represented by `KnownDevice` (currently name, id, color, ordering/group info).
- Visitor history is already loaded and displayed (`VisitorHistoryViewModel` / visitor history views), including an “add unknown visitor as device” flow.

This makes the new feature mostly an app-domain/state-management and UX integration project, not a protocol design project.

---

## 2) Key product decisions and rationale

### Decision A: How to track whether the allowed-device-list feature is enabled

**Choose:** explicit immutable activation flag + persisted per-device ACL fields.

- Add a dedicated setting flag, e.g. `allowedDeviceListEnabled: Bool` in `SettingsManager`.
- Add ACL fields to each `KnownDevice`:
  - `hasCurrentLocationAccess: Bool`
  - `hasHistoryAccess: Bool`

**Why this over “infer from list existence” only?**

- Inference from list/data shape is brittle during migration or partial failures.
- An explicit flag cleanly models the “one-way activation” requirement (“cannot be disabled”).
- Per-device ACL fields remain the source of truth for payload generation once enabled.

**Implications:**

- Migration needs defaults for older archived devices.
- Guardrails are easy: UI and sync logic can branch on `allowedDeviceListEnabled`.
- If enabled but server sync fails, state handling must remain deterministic (see rollout/sync section).

### Decision B: One-way activation behavior

**Choose:** activation is local + server-seeded atomically as one user action, then immutable in UI.

- Activation button triggers:
  1. Preconditions check (DeviceKey exists).
  2. Build payload from all known devices (defaults `true/true` for existing devices).
  3. Call `setAllowedDeviceList`.
  4. On success, persist `allowedDeviceListEnabled = true` and ACL values.

**Why:** avoids a local “enabled but never seeded” state on first setup.

### Decision C: Canonical synchronization model

**Choose:** when enabled, local known-device list is canonical and server ACL is overwritten with full list on each relevant mutation.

- Mutations: add/remove device, edit ACL toggles, onboarding activation, unknown-device allow/disallow action.
- Use one central orchestrator service to avoid duplicate ad-hoc sync code.

---

## 3) Architecture changes

## 3.1 Data model and persistence

1. Extend `KnownDevice` to include ACL fields:
   - `hasCurrentLocationAccess: Bool = true`
   - `hasHistoryAccess: Bool = true`
2. Update `NSCoding` encode/decode keys with backward-compatible defaults.
3. Add `allowedDeviceListEnabled` to `SettingsManager.Keys` and initialize from `UserDefaults`.
4. Add a local ignored-unknown-devices store (e.g. `IgnoredVisitorDeviceStore`) containing device IDs explicitly dismissed from the Devices screen unknown list.

### 3.2 Domain service layer (new)

Create `AllowedDeviceListManager` (singleton or injected service) responsible for:

- Building API payload from `KnownDeviceStore.devices`.
- Enforcing preconditions (`deviceKey != nil && !empty`, valid server URL).
- Calling `MiataruAPIClient.setAllowedDeviceList`.
- Exposing high-level methods:
  - `activateAllowedDeviceList()`
  - `syncAllowedDeviceListIfEnabled(trigger:)`
  - `upsertDeviceACL(deviceID:..., hasCurrentLocationAccess:..., hasHistoryAccess:...)`
  - `removeDeviceAndSync(deviceID:...)`
- Centralized error mapping/user messages/logging.

This keeps view code thin and avoids scattered API calls.

### 3.3 UI flow integration

1. **Onboarding**
   - Add a dedicated onboarding page for allowed-device-list.
   - Reuse the same image asset as DeviceKey onboarding.
   - CTA logic:
     - If no DeviceKey: primary action opens DeviceKey setup first.
     - If DeviceKey exists and feature disabled: show enable/setup action.
     - If already enabled: show configured/success state.
2. **Settings**
   - Add entry to review/manage feature state and explanatory text.
   - Do not provide “disable” action once enabled.
3. **Add/Edit device dialogs**
   - If feature is enabled, show two translated toggles.
   - If feature is **not** enabled yet, keep add/edit/delete dialogs in their current form and do **not** show ACL toggles.
   - Edit defaults: existing stored values.
   - Add defaults (requirement): `current = true`, `history = false` for new devices.
4. **Devices list unknown section**
   - Add top section only when unknown devices exist in visitor history and are not ignored.
   - Actions per row:
     - **Allow/Add** → open add flow with prefilled DeviceID and ACL defaults, then sync full list.
     - **Ignore/Disallow** → add ID to ignored store (hidden from this list), no deletion from full visitor history.

---

## 4) End-to-end behavior design

### 4.1 Activation sequence

1. User starts allowed-device-list setup (onboarding/settings).
2. App checks DeviceKey.
3. If missing, prompt DeviceKey creation first.
4. On DeviceKey success, build full ACL payload from known devices with initial defaults (`true/true`).
5. Call `setAllowedDeviceList`.
6. On ACK, persist `allowedDeviceListEnabled = true`.
7. From now on, all device list mutations trigger full-list sync.


### 4.1a UI gating before feature activation

- Until `allowedDeviceListEnabled == true`, existing add/change/delete device dialogs remain unchanged.
- No access-rights toggle controls are rendered in these dialogs before activation.
- Device list CRUD behavior remains exactly as today (no ACL payload sync calls).

### 4.2 Add device sequence (when enabled)

1. User opens Add Device.
2. UI shows ACL toggles with defaults `current=true`, `history=false`.
3. On save, add to `KnownDeviceStore`, then sync full list.
4. If final sync failure occurs, rollback to pre-add snapshot and show a localized error explaining restoration.

### 4.3 Edit device sequence (when enabled)

1. User edits toggles.
2. Save mutates `KnownDevice`.
3. Full-list sync is triggered.
4. If final sync failure occurs, rollback edited values to previous snapshot and notify user.

### 4.4 Remove device sequence (when enabled)

1. User deletes device.
2. Remove locally.
3. Re-send full list without removed device.
4. If final sync failure occurs, restore removed device + previous ACLs/order and notify user.

---

## 5) Unknown visitors section design (Devices screen)

- Data source:
  - `VisitorHistoryViewModel.sortedVisitors`
  - filter unique DeviceIDs not in known devices and not in ignored store.
- UI:
  - New section above known devices.
  - Each row shows DeviceID, last seen timestamp, optional location snippet similar to visitor history row style.
- Actions:
  - **Allow**: open add-device sheet with prefilled ID + ACL controls.
  - **Ignore**: persist to ignored list and remove from this section immediately.
- Visibility:
  - Section hidden if resulting list is empty.

---

## 6) Copy/texts and privacy communication

The feature text should explicitly explain:

- It is optional.
- It requires DeviceKey to protect ACL updates.
- Once enabled, the app will actively manage and sync who may access current location and history.
- It cannot be disabled later, but per-device rights remain editable.

Suggested short onboarding title/body:

- **Title**: “Control which devices can access your location data”
- **Body**: “Optionally enable access control for linked devices. You can define per device whether current location and location history are shared. This requires a DeviceKey and cannot be turned off later.”

All strings must be added to `Localizable.xcstrings` and exported to all currently supported languages.

---

## 7) Internationalization plan

1. Add base keys in `miataru/miataru/Assets/Localizable.xcstrings`:
   - feature title, body, CTA labels, helper text, irreversible-warning text,
   - toggle labels/descriptions,
   - unknown-device section title/buttons,
   - sync error/retry messages.
2. Run localization export/update workflow used in the project.
3. Verify no fallback-to-English regressions by spot checking all supported locales.

---

## 8) Error handling and resilience

- Treat API call failures as non-destructive to local edits; provide explicit retry action.
- Add exponential backoff for background retries when appropriate.
- Log trigger context (`activation`, `add`, `edit`, `remove`, `unknown_allow`) for debugging.
- Respect existing DeviceKey auth-block handling patterns.

### 8.1 Transactional rollback on final sync failure

For any operation that mutates device list and/or ACL values while feature is enabled (add/edit/remove/allow unknown), apply a transactional pattern:

1. Capture a snapshot before mutation:
   - full `KnownDeviceStore.devices` state (including ACL values, ordering, groups linkages if affected),
   - related settings state if changed in same flow.
2. Apply local mutation optimistically.
3. Attempt full-list sync using `setAllowedDeviceList` with retry policy.
4. If sync reaches **final failure** (all retries exhausted / non-recoverable error), restore the pre-mutation snapshot fully.
5. Surface a clear user-facing error explaining:
   - the server update failed,
   - the app restored previous device/access configuration,
   - user can retry later.

This prevents client/server divergence and ensures users do not remain in a silently inconsistent access-control state.

### 8.2 Rollback UX/telemetry requirements

- Show an explicit error banner/dialog after rollback with localized text and a retry action.
- Record structured telemetry/log fields: trigger, retry count, error class, rollback performed (true/false).
- Ensure rollback itself is persisted immediately (save store/settings) so app restarts cannot retain half-applied state.

---

## 9) Migration strategy for existing users

1. App update introduces new fields with decode defaults.
2. Existing users remain with feature disabled.
3. Show onboarding page and optionally a settings hint/badge to introduce feature.
4. Activation only on explicit user action.
5. No silent server ACL writes before opt-in.

### 9.1 Backward-compatible `KnownDevice` archive migration

Because `KnownDeviceStore` persists with `NSKeyedArchiver`, this migration must be additive and tolerant:

- Add only new optional/decode-with-default keys in `KnownDevice` coder methods.
- In `init(coder:)`, if ACL keys are absent (old archive), default to:
  - `hasCurrentLocationAccess = true`
  - `hasHistoryAccess = true`
- Keep all existing archive keys unchanged (`DeviceName`, `DeviceID`, `DeviceIsInGroup`, `KnownDevicesTablePosition`, `DeviceColor`) to avoid breaking older persisted files.
- Add a lightweight migration version marker in app settings (e.g. `knownDevicesSchemaVersion`) only for diagnostics/telemetry; do not gate decoding on it.

This ensures users with older `knownDevices.plist` files can load data without data loss.

### 9.2 Backward-compatible settings load/save behavior

`SettingsManager` already uses key-based `UserDefaults` reads with defaults, which is naturally forward/backward tolerant. Preserve this behavior:

- Introduce `allowedDeviceListEnabled` as a new independent key with default `false` when missing.
- Never reinterpret absence of this key as enabled.
- Do not change semantics of existing DeviceKey keys (`device_key`, `device_key_last_changed`, auth-block keys).
- Keep save logic idempotent: only write new key when explicitly toggled/enabled by user action.

### 9.3 Migration safety checks at first launch after update

On first app start after introducing ACL fields:

1. Load `KnownDeviceStore` from existing archive.
2. Verify all devices have non-nil ACL values in-memory (after decode defaults).
3. Save archive once via normal save path to persist the new keys.
4. Do **not** call `setAllowedDeviceList` automatically during this migration step.

This gives graceful persistence migration without silently changing server-side access control.

### 9.4 Evaluation matrix for existing-user scenarios

Add explicit QA evaluation for upgrade paths:

- **Case A:** User without DeviceKey, feature disabled, existing devices present.
  - Expected: all data loads; feature remains disabled; onboarding explains prerequisite.
- **Case B:** User with DeviceKey, feature disabled.
  - Expected: no behavior change until explicit activation.
- **Case C:** User with many devices/groups and reordered list.
  - Expected: ordering/group membership unchanged after migration save.
- **Case D:** Corrupted or partially old `knownDevices.plist`.
  - Expected: graceful fallback to recoverable state (existing error handling path), no crash.

### 9.5 Rollback/compatibility note

If users downgrade app versions, older builds may ignore unknown archived keys but should still read existing known fields if key names/types remain unchanged. Therefore:

- Avoid renaming existing keys.
- Avoid changing types of existing keys.
- Keep ACL keys additive only.

---

## 10) Risks, edge cases, and corrections to requested flow

### Validating the requested logic

- ✅ Correct: requiring DeviceKey as prerequisite is necessary and consistent with API contract.
- ✅ Correct: full-list resend on every ACL/device-list mutation is the safest server-consistency model.
- ✅ Correct: one-way enablement simplifies security semantics and user expectations.

### Important edge cases to account for

1. **Own device entry**: ensure “my device” in known list is always included in payload and has intended defaults.
2. **Race conditions**: rapid edits/add/removes can overlap network calls; use a serialized sync queue in `AllowedDeviceListManager`.
3. **Case sensitivity**: normalize DeviceID casing before compare/store/sync.
4. **Offline mode**: queue pending sync and surface unsynced status indicator.
5. **Visitor-history availability**: unknown-device section should degrade gracefully if visitor history fails.

### Recommended refinement

- Keep “Ignore unknown device” reversible in a dedicated “ignored devices” management screen (settings) to prevent accidental permanent hiding.

---

## 11) Implementation phases and milestones

### Phase 1 — Foundations (model + manager)

- Extend `KnownDevice` ACL fields with persistence migration.
- Add `allowedDeviceListEnabled` setting.
- Implement `AllowedDeviceListManager` with serialized sync and tests for payload generation.

### Phase 2 — Activation UX

- New onboarding page + settings entry.
- Prerequisite flow to DeviceKey setup.
- First activation call and immutable enabled state.

### Phase 3 — Device dialogs + sync wiring

- Add/edit dialogs show ACL toggles when enabled.
- Wire add/edit/remove triggers into manager sync.
- Add user-facing retry/error messaging.

### Phase 4 — Unknown visitor section

- Top section in devices list with allow/ignore actions.
- Ignored visitor store + optional management screen.

### Phase 5 — Localization, docs, QA hardening

- Add/translate all strings.
- Update app feature docs and onboarding docs.
- Regression suite and manual QA checklist.

---

## 12) Testing and validation checklist

### Unit tests

- Payload mapping from known devices to `MiataruAllowedDevice`.
- Backward decode compatibility for old archived `KnownDevice` data.
- Activation precondition behavior (with/without DeviceKey).
- Sync queue serialization and coalescing.

### Integration tests (where feasible)

- Activation happy path → enabled flag persisted.
- Add/edit/remove device when enabled triggers full-list call.
- API failure preserves local changes and exposes retry path.

### UI/manual QA

- Onboarding branching (no key / key present / enabled).
- Add/edit toggle defaults and persistence.
- Unknown-device section visibility and actions.
- Localization spot checks across supported locales.
- Existing user upgrade path with no forced opt-in.

---

## 13) Definition of done

Feature is complete when:

1. Users can optionally enable allowed-device-list only after DeviceKey setup.
2. Initial full ACL list is seeded to server with correct defaults.
3. Device add/edit/remove fully re-syncs ACL list when enabled.
4. Unknown visitor devices are actionable in devices screen (allow/ignore).
5. Feature cannot be disabled once enabled.
6. Onboarding + settings + localized copy clearly explain privacy/security implications.
7. Automated and manual checks pass.
