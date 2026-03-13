# MiataruAPIClient

Dieses Repository enthält ein Swift Package zur Nutzung der Miataru API sowie eine Beispielapplikation.

## Struktur

- `Sources/MiataruAPIClient/` – Das eigentliche Swift Package (Library)
- `Examples/MiataruTestApp/` – Beispielapplikation und Dockerfile

## Nutzung als Swift Package in Xcode

1. Öffne dein Xcode-Projekt.
2. Wähle im Menü: **File > Add Packages...**
3. Gib den lokalen Pfad zu diesem Ordner oder das Git-Repository an.
4. Füge das Produkt **MiataruAPIClient** als Abhängigkeit hinzu.
5. Importiere das Package in deinem Code:
   ```swift
   import MiataruAPIClient
   ```

## Beispielapplikation lokal ausführen

```bash
cd Examples/MiataruTestApp
swift run
```

## Beispielapplikation mit Docker ausführen (aus Projekt-Root)

```bash
docker build -f Examples/MiataruTestApp/Dockerfile -t miataru-testapp .
docker run -it --rm miataru-testapp
```

## Hinweise
- Die Beispielapplikation sendet und liest Testdaten von https://service.miataru.com.
- Passe ggf. die Device-IDs in `main.swift` an.
- Die Library kann in eigenen Swift-Projekten verwendet werden.

## GetLocation mit DeviceKey des anfragenden Geräts

Die `getLocation`-Methode unterstützt optional den DeviceKey des anfragenden Geräts.
Dadurch kann der Server eine Kombination aus `RequestMiataruDeviceID` und `RequestMiataruDeviceKey` validieren.

```swift
let locations = try await MiataruAPIClient.getLocation(
    serverURL: serverURL,
    forDeviceIDs: [targetDeviceID],
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey
)

if let first = locations.first {
    print(first.Device)                  // targetDeviceID
    print(first.DeviceSlogan ?? "(kein Slogan)")
}
```

## GetLocationHistory mit DeviceKey des anfragenden Geräts

Die `getLocationHistory`-Methode unterstützt ebenfalls optional den DeviceKey des anfragenden Geräts.
Dadurch kann der Server auch bei History-Abfragen die Kombination aus `RequestMiataruDeviceID` und `RequestMiataruDeviceKey` validieren.

```swift
let history = try await MiataruAPIClient.getLocationHistory(
    serverURL: serverURL,
    forDeviceID: targetDeviceID,
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey,
    amount: 1000
)
```

## Device Slogan API

Die Library unterstützt jetzt auch die neuen Endpunkte `setDeviceSlogan` und `getDeviceSlogan`.

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

print(setResponse.MiataruResponse)         // "ACK"
print(slogan.DeviceID)                     // targetDeviceID
print(slogan.Slogan ?? "(kein Slogan)")
```

## Device Security Status API

Die Library unterstützt zusätzlich den Endpunkt `getDeviceSecurityStatus`.
Der Call erfordert die Authentifizierung über `RequestDeviceID` und `RequestDeviceKey`.

```swift
let securityStatus = try await MiataruAPIClient.getDeviceSecurityStatus(
    serverURL: serverURL,
    forDeviceID: targetDeviceID,
    requestingDeviceID: ownDeviceID,
    requestingDeviceKey: ownDeviceKey
)

print(securityStatus.DeviceID)                  // targetDeviceID
print(securityStatus.HasDeviceKey)              // true/false
print(securityStatus.IsAllowedDeviceListEnabled) // true/false
```

## Allowed Device List Read API

Die Library unterstützt außerdem den Endpunkt `getAllowedDeviceList` zum Auslesen der gespeicherten ACL eines Geräts.
Der Call verwendet Owner-Authentifizierung über `DeviceID` und `DeviceKey`.

```swift
let allowedDeviceList = try await MiataruAPIClient.getAllowedDeviceList(
    serverURL: serverURL,
    deviceID: ownDeviceID,
    deviceKey: ownDeviceKey
)

print(allowedDeviceList.DeviceID)                    // ownDeviceID
print(allowedDeviceList.IsAllowedDeviceListEnabled)  // true/false
print(allowedDeviceList.allowedDevices.count)        // Anzahl ACL-Einträge
```
