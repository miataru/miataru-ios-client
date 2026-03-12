# GetLocation DeviceSlogan Integration (2026-03-12)

## Problem
Der Miataru-Server liefert den Device-Slogan jetzt im `GetLocation`-Payload (`DeviceSlogan`) auch bei Listen-Anfragen.

Die App hat Slogans bisher zusätzlich pro Device über `getDeviceSlogan` nachgeladen und gecached. Das führte zu:

- zusätzlichen Requests pro Zeile/Device,
- inkonsistenten Aktualisierungspfaden zwischen Device-Liste, Unknown Visitors und Visitor History.

## Change
Die Slogan-Verarbeitung wurde auf `GetLocation`-basiertes Handling umgestellt.

### Library (MiataruClientSwift)
- `MiataruLocationData` erweitert um `DeviceSlogan` (inkl. Fallback-Dekodierung von `Slogan` für Abwärtskompatibilität).
- `MiataruGetLocationResponse` bleibt tolerant gegenüber `null`-Einträgen.
- README ergänzt um Nutzung von `DeviceSlogan` aus `getLocation`.
- Beispiel-App (`MiataruTestApp`) an die aktuellen `Double`-Typen des Update-Payloads angepasst.
- `packageVersion` auf `1.1.1` erhöht.

### App
- Zentrales Slogan-Caching direkt nach jedem `MiataruAppAPI.getLocation(...)`:
  - `DeviceSloganCacheStore.ingestGetLocationResults(_:requestedDeviceIDs:)`
- `DeviceSloganCacheStore` von aktivem Einzelabruf (`refreshSloganIfStale/fetchSloganIfNeeded`) auf passives Ingest umgebaut.
- Alle per-Row/per-Device `getDeviceSlogan`-Refreshpfade entfernt.
- Slogan-Nachladen in Add/Edit/MyDevice-QR auf `GetLocation`-Aufruf umgestellt.
- Best-effort Slogan-Lookup für Unknown-Visitor-Notifications auf `GetLocation` umgestellt.

### Regelmäßiger Listen-Refresh
- Device-Liste iPhone: periodischer Task ergänzt, der jetzt auch Device-Locations refreshen kann.
- Device-Liste iPad: vorhandener periodischer Task erweitert um Device-Locations-Refresh.
- Refresh-Intervall: `max(5, outsideMapUpdateInterval)` Sekunden.

## Expected Behavior
- Slogans werden beim normalen `GetLocation`-Datenfluss aktualisiert und gecached.
- Unknown-Visitor-Slogans werden bei Unknown-Visitor-Location-Refreshes automatisch mit aktualisiert.
- Weniger Einzelrequests (`getDeviceSlogan`) im Listenkontext.
- Device-Locations werden beim Verweilen in der Device-Liste regelmäßig mitgezogen (parallel zur Visitor-History-Logik).

## Verification
- `cd miataru/Libraries/MiataruClientSwift && swift build` erfolgreich.
- `cd miataru && xcodebuild -project miataru.xcodeproj -scheme miataru -configuration Debug -destination 'generic/platform=iOS Simulator' build` erfolgreich.
