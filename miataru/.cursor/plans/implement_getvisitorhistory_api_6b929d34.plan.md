---
name: Implement GetVisitorHistory API
overview: Add GetVisitorHistory API support to the Miataru client library by implementing data structures and a public method following the same pattern as getLocationHistory.
todos:
  - id: "1"
    content: Add MiataruVisitor struct with DeviceID, TimeStamp properties and TimeStampDate computed property
    status: completed
  - id: "2"
    content: Add GetVisitorHistoryPayload struct with Device and Amount properties
    status: completed
  - id: "3"
    content: Add GetVisitorHistoryRequestBody struct for request encoding
    status: completed
  - id: "4"
    content: Add MiataruVisitorHistoryServerConfig struct for server configuration data
    status: completed
  - id: "5"
    content: Add MiataruGetVisitorHistoryResponse struct with custom decoding for malformed entries
    status: completed
  - id: "6"
    content: Implement getVisitorHistory() public method following getLocationHistory() pattern
    status: completed
---

# Implement GetVisitorHistory API in Miataru Client Library

## Overview

The Miataru server provides a `/v1/GetVisitorHistory` endpoint that returns a list of devices that have requested the location of a specific device. This endpoint is defined in the YAML specification but not yet implemented in the client library.

## Implementation Details

### 1. Data Structures (in `MiataruAPIClient.swift`)

Add the following Swift structs following the existing pattern:

- **`MiataruVisitor`** (public struct, Codable)
  - Properties: `DeviceID: String`, `TimeStamp: String`
  - Computed property: `TimeStampDate: Date` (similar to `MiataruLocationData.TimestampDate`)
  - Custom decoding to handle string/number timestamp formats

- **`GetVisitorHistoryPayload`** (public struct, Codable)
  - Properties: `Device: String`, `Amount: String`
  - Similar to `GetLocationHistoryPayload`

- **`GetVisitorHistoryRequestBody`** (private struct, Encodable)
  - Property: `MiataruGetVisitorHistory: GetVisitorHistoryPayload`
  - Note: Unlike `GetLocationHistoryRequestBody`, this does NOT include optional `MiataruConfig` per the API spec

- **`MiataruVisitorHistoryServerConfig`** (public struct, Codable)
  - Properties: `MaximumNumberOfVisitorHistory: String`, `AvailableVisitorHistory: String`

- **`MiataruGetVisitorHistoryResponse`** (public struct, Codable)
  - Properties: `MiataruServerConfig: MiataruVisitorHistoryServerConfig`, `MiataruVisitors: [MiataruVisitor]`
  - Custom decoding to handle malformed entries gracefully (similar to `MiataruGetLocationHistoryResponse`)

### 2. Public API Method

Add `getVisitorHistory()` method to `MiataruAPIClient`:

```swift
public static func getVisitorHistory(serverURL: URL,
                              forDeviceID deviceID: String,
                              amount: Int) async throws -> [MiataruVisitor]
```

- Parameters: `serverURL`, `forDeviceID`, `amount`
- Returns: Array of `MiataruVisitor` objects
- Throws: `APIError` on failure
- Implementation pattern matches `getLocationHistory()`:
  - Construct URL: `serverURL.appendingPathComponent("v1/GetVisitorHistory")`
  - Create request body with `GetVisitorHistoryRequestBody`
  - Use `performPostRequest(url:encodablePayload:logMessage:)`
  - Decode response with error handling and logging
  - Return array of visitors

### 3. File to Modify

- `Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift`
  - Add data structures after existing response structs (around line 294)
  - Add public method after `getLocationHistory()` (around line 434)

### 4. Testing Considerations

The implementation should:

- Handle empty visitor arrays
- Handle malformed visitor entries (skip with logging)
- Support timestamp decoding (string or number format)
- Include debug logging consistent with existing methods
- Follow the same error handling pattern as `getLocationHistory()`

## API Specification Reference

Based on the Swagger spec:

- **Request**: `POST /v1/GetVisitorHistory`
  - Body: `{ "MiataruGetVisitorHistory": { "Device": "...", "Amount": "..." } }`
- **Response**: `{ "MiataruServerConfig": { "MaximumNumberOfVisitorHistory": "...", "AvailableVisitorHistory": "..." }, "MiataruVisitors": [{ "DeviceID": "...", "TimeStamp": "..." }] }`

## Notes

- Unlike `GetLocationHistory`, the `GetVisitorHistory` request does NOT include an optional `MiataruConfig` field per the API specification
- The `TimeStamp` field uses JavaScript timestamp format (seconds since epoch as string)
- The `DeviceID` can be an empty string if the visiting device ID was not reported