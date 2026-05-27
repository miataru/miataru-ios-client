# Unknown Device Case Preservation

## Context

Unknown devices can enter the add-device flow from several paths: device-list unknown visitors, the unknown-device action sheet, notifications, scanner input, and external `miataru://<DeviceID>` links. The routing layer intentionally used uppercase normalization for case-insensitive known-device matching, unknown-visitor filtering, and cache keys.

That normalization leaked into the visible add-device request. When an unknown device ID contained lowercase characters, tapping the unknown visitor converted the prefilled Device ID to uppercase. This was wrong because Device IDs may be case-sensitive from the user's perspective and must be preserved exactly when adding a new device.

## Change

- `DeviceLinkResolver` now exposes `trimmedDeviceID(_:)` for display/persistence flows that should only remove surrounding whitespace.
- `deviceID(from:)` and `deviceID(fromCanonicalCode:)` return the trimmed Device ID with original letter casing.
- `normalizedDeviceID(_:)` still uppercases, but is reserved for case-insensitive matching and cache-like comparison paths.
- `AppNavigationCoordinator` now uses the trimmed Device ID for add-device and unknown-device action requests.
- Known-device routing continues to use normalized comparison and returns the stored canonical Device ID when a match exists.

## Result

- Unknown visitors with lowercase or mixed-case Device IDs keep their original spelling when opened from the device list or unknown-device action sheet.
- External links and QR scanner input preserve case for unknown devices while still resolving known devices case-insensitively.
- Existing uppercase/case-insensitive cache and filter behavior remains available where a comparison key is needed.

## Verification

Focused regression coverage lives in `DeviceLinkResolverTests`:

- URI and scanner parsing preserve mixed-case IDs.
- `trimmedDeviceID(_:)` preserves case while `normalizedDeviceID(_:)` uppercases for comparison.
- Known-device routing remains case-insensitive and returns the stored canonical ID.
- Unknown-device add requests and unknown-visitor notification action requests preserve source and case.

Validation command:

```sh
./scripts/test-unit.sh -only-testing:miataruTests/DeviceLinkResolverTests
```
