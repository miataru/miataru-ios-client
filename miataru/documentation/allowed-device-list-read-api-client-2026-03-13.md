# Allowed Device List Read API Client Integration (2026-03-13)

## Goal
Add support for the new Miataru API endpoint `getAllowedDeviceList` in the shared Swift client so the stored ACL of an owner device can be fetched in a typed way.

## Implemented Changes

### MiataruClientSwift
Updated `miataru/Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift`:

- Added typed request body:
  - `GetAllowedDeviceListRequestBody`
- Added typed request payload:
  - `GetAllowedDeviceListPayload`
- Added typed response models:
  - `MiataruAllowedDeviceList`
  - `MiataruGetAllowedDeviceListResponse`
- Added new public API method:
  - `MiataruAPIClient.getAllowedDeviceList(serverURL:deviceID:deviceKey:)`
- Removed an existing non-functional Swift warning in `SkipDecodable` by changing `var keyed` to `let keyed`

Request path and payload naming match `Miataru.yaml`:
- Path: `v1/getAllowedDeviceList`
- Request root key: `MiataruGetAllowedDeviceList`
- Response root key: `MiataruAllowedDeviceList`

### Response Shape
The new response model exposes:
- `DeviceID`
- `IsAllowedDeviceListEnabled`
- `allowedDevices`

Each allowlist entry is decoded as existing `MiataruAllowedDevice` values.

## Documentation
Updated package usage docs:
- `miataru/Libraries/MiataruClientSwift/README.md`
  - Added a usage section and sample code for `getAllowedDeviceList`

Updated release notes:
- `miataru/CHANGELOG.md`
  - Added entries for the new client support and README update

## Validation
- Verified compilation of the full Swift package:
  - `swift build`
- Result: build completed successfully
