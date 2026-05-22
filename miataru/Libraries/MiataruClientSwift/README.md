# MiataruAPIClient

This directory contains the local Swift package for the Miataru API as well as a small sample application.

## Structure

- `Sources/MiataruAPIClient/` - Swift Package library
- `Definitions/Miataru.yaml` - API definition
- `Examples/MiataruTestApp/` - Sample application and Dockerfile

## Using as a Swift Package in Xcode

1. Open your Xcode project.
2. Choose **File > Add Packages...**.
3. Enter the local path to this folder or the Git repository.
4. Add the **MiataruAPIClient** product as a dependency.
5. Import the package:

```swift
import MiataruAPIClient
```

## Running the sample application locally

```bash
cd Examples/MiataruTestApp
swift run
```

## Running the sample application with Docker

```bash
docker build -f Examples/MiataruTestApp/Dockerfile -t miataru-testapp .
docker run -it --rm miataru-testapp
```

## Library behavior

- POST requests use a `URLSessionConfiguration.ephemeral` and `reloadIgnoringLocalCacheData` so JSON responses are not stored in a disk cache.
- The library itself does not perform app-specific retry, outbox, or cache ingest steps.
- The miataru app uses `MiataruAppAPI`, `MiataruRequestExecutor`, `MiataruRetryPolicy`, and `LocationUpdateDeliveryCoordinator` in the app target for that.
- Existing `APIError` values are passed through unchanged so request/server errors do not accidentally appear as encoding errors.

## Supported APIs

- `getLocation`
- `getLocationHistory`
- `getVisitorHistory`
- `getVisitorHistoryWithConfig`
- `updateLocation`
- `deleteLocation`
- `setDeviceKey`
- `setAllowedDeviceList`
- `getAllowedDeviceList`
- `setDeviceSlogan`
- `getDeviceSlogan`
- `getDeviceSecurityStatus`

## GetLocation with the requesting device's DeviceKey

`getLocation` optionally supports `RequestMiataruDeviceID` and `RequestMiataruDeviceKey`.

```swift
let locations = try await MiataruAPIClient.getLocation(
    serverURL: serverURL,
    forDeviceIDs: [targetDeviceID],
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey
)

if let first = locations.first {
    print(first.Device)
    print(first.DeviceSlogan ?? "(no slogan)")
}
```

## GetLocationHistory with the requesting device's DeviceKey

`getLocationHistory` also supports the optional DeviceKey of the requesting device.

```swift
let history = try await MiataruAPIClient.getLocationHistory(
    serverURL: serverURL,
    forDeviceID: targetDeviceID,
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey,
    amount: 1000
)
```

## Visitor History

`getVisitorHistory` returns the visitor list directly. `getVisitorHistoryWithConfig` can first read server configuration data and then load the available history amount.

```swift
let visitors = try await MiataruAPIClient.getVisitorHistory(
    serverURL: serverURL,
    forDeviceID: ownDeviceID,
    deviceKey: ownDeviceKey,
    amount: 100
)

let response = try await MiataruAPIClient.getVisitorHistoryWithConfig(
    serverURL: serverURL,
    forDeviceID: ownDeviceID,
    deviceKey: ownDeviceKey,
    amount: nil
)
```

## UpdateLocation and DeleteLocation

```swift
let payload = UpdateLocationPayload(
    Device: ownDeviceID,
    DeviceKey: ownDeviceKey,
    Timestamp: "\(Int(Date().timeIntervalSince1970 * 1000))",
    Longitude: 13.4050,
    Latitude: 52.5200,
    HorizontalAccuracy: 10,
    Speed: nil,
    BatteryLevel: nil,
    Altitude: nil
)

let acknowledged = try await MiataruAPIClient.updateLocation(
    serverURL: serverURL,
    locationData: payload,
    enableHistory: true,
    retentionTime: 1440
)

let deleted = try await MiataruAPIClient.deleteLocation(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    deviceKey: ownDeviceKey
)
```

## DeviceKey API

```swift
let response = try await MiataruAPIClient.setDeviceKey(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    currentDeviceKey: oldDeviceKey,
    newDeviceKey: newDeviceKey
)
```

## Allowed Device List API

```swift
let updateResponse = try await MiataruAPIClient.setAllowedDeviceList(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    deviceKey: ownDeviceKey,
    allowedDevices: [
        MiataruAllowedDevice(
            DeviceID: friendDeviceID,
            hasCurrentLocationAccess: true,
            hasHistoryAccess: true
        )
    ]
)

let allowedDeviceList = try await MiataruAPIClient.getAllowedDeviceList(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    deviceKey: ownDeviceKey
)

print(allowedDeviceList.DeviceID)
print(allowedDeviceList.IsAllowedDeviceListEnabled)
print(allowedDeviceList.allowedDevices.count)
```

## Device Slogan API

```swift
let setResponse = try await MiataruAPIClient.setDeviceSlogan(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    deviceKey: ownDeviceKey,
    slogan: "Find me if you can"
)

let slogan = try await MiataruAPIClient.getDeviceSlogan(
    serverURL: serverURL,
    forDeviceID: targetDeviceID,
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey
)

print(setResponse.MiataruResponse)
print(slogan.DeviceID)
print(slogan.Slogan ?? "(no slogan)")
```

## Device Security Status API

```swift
let securityStatus = try await MiataruAPIClient.getDeviceSecurityStatus(
    serverURL: serverURL,
    forDeviceID: targetDeviceID,
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey
)

print(securityStatus.DeviceID)
print(securityStatus.HasDeviceKey)
print(securityStatus.IsAllowedDeviceListEnabled)
```

## Notes for the miataru app

- App code should prefer `MiataruAppAPI` over calling `MiataruAPIClient` directly so retry, counters, device key error handling, and cache ingest stay consistent.
- Widget code uses the library more directly because the widget extension should not access app actors and the app outbox store.
