# Device ID and Name Ambiguity Handling

## Context

Preserving Device ID letter casing fixed the immediate unknown-device bug, but it exposed two related ambiguity cases:

- Device IDs that differ only by uppercase/lowercase are technically dangerous because routing, cache keys, unknown-visitor filtering, and known-device matching intentionally use case-insensitive comparison keys.
- Device names that differ only by uppercase/lowercase are confusing for users, but they are human labels and should remain editable.

## Rules

- Device IDs are unique case-insensitively.
- The original Device ID casing is still stored and displayed.
- Add Device rejects a new Device ID when its trimmed uppercase comparison key already exists.
- Device names are allowed to duplicate case-insensitively, but Add/Edit Device shows a localized warning.
- Device list rows show a shortened Device ID under the name when a row would be ambiguous because of a duplicate display name or an existing same-ID-different-case conflict.

## Implementation

- `KnownDeviceStore` owns the duplicate logic:
  - `device(matchingDeviceIDCaseInsensitive:excluding:)`
  - `hasCaseInsensitiveDeviceIDDuplicate(for:)`
  - `hasCaseInsensitiveNameDuplicate(...)`
- `iPhone_AddDeviceView` trims name/ID before saving, blocks Device ID conflicts, and shows the duplicate-name warning.
- `iPhone_EditDeviceView` shows the same duplicate-name warning without blocking the save.
- `DeviceRowView` observes the store and renders the short Device ID line only for ambiguous rows.
- The visible new strings are present in `Localizable.xcstrings` for all supported locales.

## Verification

Focused regression coverage lives in `DeviceLinkResolverTests`:

- Case-insensitive Device ID duplicates are rejected by `KnownDeviceStore`.
- Case-insensitive Device name duplicates are detected but allowed.
- Existing legacy same-ID-different-case rows are detected for row disambiguation.
- The earlier case-preserving unknown-device routing tests remain covered.

Validation command:

```sh
./scripts/test-unit.sh -only-testing:miataruTests/DeviceLinkResolverTests
```
