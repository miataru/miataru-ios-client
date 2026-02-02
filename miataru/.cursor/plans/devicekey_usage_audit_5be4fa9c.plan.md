---
name: devicekey_usage_audit
overview: Add DeviceKey support to Miataru client location endpoints and wire it through all location/history call sites so navigation and history use the device key when configured.
todos:
  - id: client-devicekey-payloads
    content: Add deviceKey to getLocation/getLocationHistory payloads + APIs
    status: pending
  - id: wire-call-sites
    content: Pass deviceKey in all getLocation/getLocationHistory calls
    status: pending
  - id: verify-coverage
    content: Search for remaining call sites and update
    status: pending
isProject: false
---

## Scope

- Update Miataru client payloads and APIs to accept optional `DeviceKey` for location and history requests.
- Propagate `settings.deviceKey` into all call sites for `getLocation` and `getLocationHistory` across iPhone/iPad device and group views.
- Keep encoding behavior consistent with existing optional DeviceKey handling patterns.

## Key findings

- `getLocation` and `getLocationHistory` currently have no `deviceKey` parameter and their payloads omit `DeviceKey`.

```688:699:/Users/bietiekay/code/miataru-ios-app/miataru/Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift
    public static func getLocation(serverURL: URL,
                           forDeviceIDs deviceIDs: [String],
                           requestingDeviceID: String) async throws -> [MiataruLocationData] {
        let url = serverURL.appendingPathComponent("v1/GetLocation")
        let devicesPayload = deviceIDs.map { ["Device": $0] }
        let jsonPayload: [String: Any] = [
            "MiataruGetLocation": devicesPayload,
            "MiataruConfig": ["RequestMiataruDeviceID": requestingDeviceID]
        ]
```

- Navigation fetches location without any device key today.

```783:797:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
    private func fetchTargetDeviceLocation(resetAndRecenter: Bool, ignoreRouteCache: Bool = false) async {
        guard let url = URL(string: settings.miataruServerURL) else { return }
        do {
            isLoading = true
            defer { isLoading = false }
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [device.DeviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
```

## Implementation plan

1. Extend Miataru client payloads to include optional `DeviceKey` for `GetLocationPayload` and `GetLocationHistoryPayload` with encode logic matching existing optional fields (e.g. `DeleteLocationPayload`, `GetVisitorHistoryPayload`). Update `getLocation`/`getLocationHistory` signatures to accept `deviceKey: String? = nil` and include it in the request bodies when non-empty. Files:
  - [/Users/bietiekay/code/miataru-ios-app/miataru/Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift](/Users/bietiekay/code/miataru-ios-app/miataru/Libraries/MiataruClientSwift/Sources/MiataruAPIClient/MiataruAPIClient.swift)
2. Update all call sites to pass `settings.deviceKey` (or `SettingsManager.shared.deviceKey` where applicable) into the new parameters for `getLocation` and `getLocationHistory`. This includes navigation, device map/history, and group/map views across iPhone/iPad. Seed references:
  - [/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)
  - [/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceMapView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceMapView.swift)
  - [/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift)
3. Verify we did not miss Miataru client usage by searching for remaining `getLocation`/`getLocationHistory` call sites and updating them consistently (including iPad views and group maps). Add minimal compile-time fixes if any signatures changed.

## Test plan

- Manual: set a device key and confirm navigation fetches and history views load data for protected devices.
- Optional: run existing unit tests if desired.

