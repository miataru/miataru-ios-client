# Device Security Status API Client Integration (2026-03-11)

## Goal
Add support for the new Miataru API endpoint `getDeviceSecurityStatus` in the shared Swift client and expose it through the app-level API wrapper.

## Implemented Changes

### MiataruClientSwift
Updated `miataru/Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift`:

- Added typed request body:
  - `GetDeviceSecurityStatusRequestBody`
- Added typed request payload:
  - `GetDeviceSecurityStatusPayload`
- Added typed response models:
  - `MiataruDeviceSecurityStatus`
  - `MiataruGetDeviceSecurityStatusResponse`
- Added new public API method:
  - `MiataruAPIClient.getDeviceSecurityStatus(serverURL:forDeviceID:requestingDeviceID:requestingDeviceKey:)`

Request path and payload naming match `Miataru.yaml`:
- Path: `v1/getDeviceSecurityStatus`
- Request root key: `MiataruGetDeviceSecurityStatus`
- Response root key: `MiataruDeviceSecurityStatus`

### App Networking Wrapper
Updated `miataru/miataru/Networking/MiataruAppAPI.swift`:

- Added `MiataruAppAPI.getDeviceSecurityStatus(...)` passthrough.
- Wrapped with centralized request execution (`MiataruRequestExecutor`) using read retry policy.

## Documentation
Updated package usage docs:
- `miataru/Libraries/MiataruClientSwift/README.md`
  - Added a usage section and sample code for `getDeviceSecurityStatus`.

## Validation
- Verified compilation of the package target:
  - `swift build --target MiataruAPIClient`
- Note: full package build still fails in the existing example app (`Examples/MiataruTestApp/main.swift`) due unrelated pre-existing `String`/`Double` type mismatches.
