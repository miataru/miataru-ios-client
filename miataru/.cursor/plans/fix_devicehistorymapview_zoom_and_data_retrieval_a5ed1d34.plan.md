---
name: Fix DeviceHistoryMapView zoom and data retrieval
overview: "Fix two issues in DeviceHistoryMapView: 1) Map zoom not working correctly due to missing animation and timing issues, 2) Data retrieval potentially failing due to improper error handling and response validation."
todos: []
---

# Fix DeviceHistoryMapView Zoom and Data Retrieval

Issues

## Analysis

After analyzing the `DeviceHistoryMapView` implementation, I've identified two main issues:

### Issue 1: Map Zoom Not Working Correctly

The `updateRegion()` function at lines 124-145 has several problems:

- **Missing animation**: Unlike other map views in the codebase (iPhone_DeviceMapView, iPad_DeviceMapView, GroupMapView), it doesn't wrap the camera position update in `withAnimation`, which can cause the update to be ignored or appear abrupt
- **Timing issue**: The function is called immediately after setting `history` in `MainActor.run`, but the map view might not be fully rendered yet
- **Span calculation edge cases**: When all points are identical or very close together, the span calculation might not provide a reasonable zoom level

### Issue 2: Data Retrieval Issues

The `loadHistory()` function at lines 84-122 has several critical problems:

- **Encoding Error (APIError error 2)**: The request encoding is failing with `APIError.encodingError`. This is the primary issue causing data retrieval to fail. The error occurs when trying to encode `GetLocationHistoryRequestBody`, which contains an optional `MiataruConfig` and `GetLocationHistoryPayload`. The encoding might be failing due to:
- Optional `MiataruConfig` not being handled correctly by automatic Codable synthesis
- Device ID format issues (UUID format: `BF0160F5-4138-402C-A5F0-DEB1AA1F4216`)
- Missing custom `encode(to:)` implementation in `GetLocationHistoryRequestBody`
- **Poor error handling**: The current error handling only shows `error.localizedDescription`, which for `APIError.encodingError` doesn't provide useful debugging information. The underlying encoding error details are lost.
- **No error handling for empty responses**: If the server returns an empty array, there's no distinction between "no data" and "error"
- **Missing validation**: No check if the API response contains valid location data before processing
- **Cache handling**: When using cached data, `updateRegion()` is called but might execute before the view is ready

## Solution

### Fix 1: Improve Map Zoom Implementation

1. **Add animation wrapper** to `updateRegion()`:

- Wrap camera position update in `withAnimation(.easeInOut(duration: 0.5))` to match other map views
- Ensure the update happens on the main thread (already handled, but verify)

2. **Improve span calculation**:

- Handle edge case when all points are identical (use a reasonable default span)
- Add padding factor (currently 1.4) but ensure minimum span is reasonable
- Consider using a minimum span that provides good visibility

3. **Add delay/async handling**:

- Use `Task { @MainActor in ... }` or ensure update happens after view is ready
- Consider using `.onChange(of: history)` modifier to trigger region update when data changes

### Fix 2: Improve Data Retrieval

1. **Fix encoding error handling** (CRITICAL):

- Add specific handling for `APIError.encodingError` to extract and display the underlying encoding error details
- Add debug logging to show the exact encoding failure reason
- Check if `requestingDeviceID` is valid before making the request
- Add validation for device ID format if needed

2. **Fix API client encoding issue** (if within scope):

- The `GetLocationHistoryRequestBody` struct in `MiataruAPIClient.swift` may need a custom `encode(to:)` method to properly handle the optional `MiataruConfig`
- Ensure the encoder configuration matches server expectations
- Consider making `MiataruConfig` non-optional in the request if the server requires it

3. **Add response validation**:

- Check if the API response is empty and handle it appropriately
- Validate that returned locations have valid coordinates before processing
- Add better error messages for different failure scenarios

4. **Improve error handling**:

- Distinguish between network errors, encoding errors, decoding errors, empty responses, and invalid data
- Provide more specific, user-friendly error messages
- Add detailed debug logging for troubleshooting

5. **Fix timing of region update**:

- Ensure `updateRegion()` is called after the view has rendered
- Consider using `.onChange(of: history)` modifier instead of calling it directly

## Implementation Details

### Files to Modify

- [`miataru/views/Common/DeviceHistoryMapView.swift`](miataru/views/Common/DeviceHistoryMapView.swift)
- [`Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift`](Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift) - May need custom encoding implementation for `GetLocationHistoryRequestBody`

### Key Changes

1. **Update `updateRegion()` function**:

- Add `withAnimation` wrapper
- Improve span calculation for edge cases
- Add validation for empty history

2. **Update `loadHistory()` function**:

- Add specific handling for `APIError.encodingError` with detailed error extraction
- Add validation for `requestingDeviceID` before making request
- Add validation for empty API responses
- Improve error handling with specific error types and user-friendly messages
- Add detailed debug logging for encoding failures
- Ensure proper timing of region updates

3. **Fix API client encoding** (if needed):

- Add custom `encode(to:)` method to `GetLocationHistoryRequestBody` to properly handle optional `MiataruConfig`
- Ensure the JSON structure matches server expectations
- Add error handling and logging for encoding failures

4. **Add `.onChange(of: history)` modifier**:

- Automatically update region when history changes
- This ensures the update happens at the right time in the view lifecycle

## Testing Considerations

- **Critical**: Test with device ID `BF0160F5-4138-402C-A5F0-DEB1AA1F4216` to reproduce and verify encoding error fix
- Test with different device ID formats (UUID, hash, etc.)
- Test with nil `requestingDeviceID` to ensure optional handling works
- Test with empty history data
- Test with single location point
- Test with multiple identical locations
- Test with locations spread across large distances
- Test with network errors
- Test with encoding errors (verify error messages are helpful)
- Test with invalid API responses
- Verify animation works smoothly
- Verify zoom level is appropriate for the data