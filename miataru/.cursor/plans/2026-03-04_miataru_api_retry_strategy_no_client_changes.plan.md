---
name: Miataru API Retry Strategy (No Client Library Changes)
overview: Centralize Miataru API retry and resilience in app code only, including a persistent updateLocation outbox, while leaving MiataruClientSwift untouched.
todos:
  - id: add-app-side-retry-core
    content: Add MiataruRetryPolicy/Classifier, MiataruRequestExecutor and MiataruAppAPI facade in app target
    status: completed
  - id: migrate-app-callsites
    content: Migrate app callsites from direct MiataruAPIClient calls to MiataruAppAPI wrappers
    status: completed
  - id: add-updatelocation-outbox
    content: Implement persistent FIFO outbox for updateLocation with cap, TTL, dedupe and batch flush
    status: completed
  - id: wire-flush-triggers
    content: Trigger outbox flush on app-active, network recovery and periodic timer
    status: completed
  - id: add-tests-and-docs
    content: Add retry/outbox tests and update development/test documentation and changelog
    status: completed
isProject: false
---

# Miataru API Retry/Resilience Plan (ohne Änderungen an MiataruClientSwift)

## Scope

- Retry/Resilience gilt ausschließlich für Miataru-API-Aufrufe im App-Target (`miataru/miataru/**`).
- Widget (`miataruWidgets`) bleibt bewusst ohne Retries.
- Es gibt **keine** Änderungen an `miataru/Libraries/MiataruClientSwift/**`.

## Use-Case-Matrix

| Use Case | Endpoint | Retry-Verhalten |
|---|---|---|
| Eigene Location senden | `updateLocation` | 1 Retry + Outbox |
| Device Map (iPhone/iPad) | `getLocation` | 1 Retry |
| Group Map (iPhone/iPad) | `getLocation` | 1 Retry |
| DeviceList Refresher | `getLocation`, `getVisitorHistory` | 1 Retry |
| Visitor History | `getVisitorHistoryWithConfig` | 1 Retry |
| Device History Map | `getLocationHistory` | 1 Retry |
| Unknown Visitor Zusatzdaten | `getLocation`, `getDeviceSlogan` | 1 Retry |
| Device Slogan Fetch | `getDeviceSlogan` | 1 Retry |
| Device Slogan Write | `setDeviceSlogan` | 1 Retry |
| DeviceKey setzen/restore | `setDeviceKey` | 1 Retry |
| Allowed Device List Sync | `setAllowedDeviceList` | 1 Retry |
| Widget Timeline Loader | `getLocation` | kein Retry |

## Retry-Profile

- Retrybar:
  - `URLError`: `timedOut`, `networkConnectionLost`, `notConnectedToInternet`, `cannotConnectToHost`, `cannotFindHost`, `dnsLookupFailed`
  - HTTP: `408`, `429`, `5xx`
- Nicht retrybar:
  - `invalidURL`, `encodingError`, `decodingError`
  - Auth/ACL (`401`, `403`) und sonstige fachliche `4xx`
- Read-Profil:
  - `maxRetries=1`, Backoff `0.8s`, Jitter `±25%`
- Write-Profil:
  - `maxRetries=1`, Backoff `1.0s`, Jitter `±25%`
- `updateLocation`-Profil:
  - `maxRetries=1`, Backoff `1.2s`, Jitter `±25%`

## Outbox-Spezifikation (`updateLocation`)

- Speicherort: App Support `locationUpdateOutbox.json`
- Queue: FIFO
- Cap: `500`
- TTL: `24h`
- Dedupe-Key: `Device + Timestamp + Latitude + Longitude`
- Flush-Trigger:
  - App wird aktiv
  - Netzwerk wird wieder verfügbar
  - Periodischer Timer (`60s`) solange Einträge vorhanden sind
- Flush-Batch: `25`
- Fehlerverhalten:
  - Transient am Head: Flush stoppt, nächster Trigger übernimmt
  - Non-retryable: nur betroffenes Item wird verworfen

## Implementierte App-interne Komponenten

1. `miataru/Networking/MiataruRetryPolicy.swift`
   - Retry-Profile
   - `MiataruRetryClassifier` für retrybar/nicht-retrybar
2. `miataru/Networking/MiataruRequestExecutor.swift`
   - Zentraler Retry-Executor (Actor)
3. `miataru/Networking/MiataruAppAPI.swift`
   - Fassade für Miataru-Aufrufe mit Retry-Profilen
4. `miataru/Networking/LocationUpdateOutboxStore.swift`
   - Persistente Outbox (FIFO/TTL/Cap/Dedupe)
5. `miataru/Networking/LocationUpdateDeliveryCoordinator.swift`
   - Direct-Send + Retry + Queueing + Flush-Koordination

## Betroffene Migrationsdateien

- `LocationManagers/LocationManager.swift` (Outbox/Coordinator Integration)
- `LocationManagers/DeviceLocationRefresher.swift`
- `SettingsManagers/App Settings/Devices/AllowedDeviceListManager.swift`
- `SettingsManagers/App Settings/Devices/DeviceSloganCacheStore.swift`
- `views/iPhone/iPhone_DevicesView.swift`
- `views/iPad/iPad_DevicesView.swift`
- `views/iPhone/Devices Views/iPhone_DeviceMapView.swift`
- `views/iPad/Devices Views/iPad_DeviceMapView.swift`
- `views/iPhone/Groups Views/iPhone_GroupMapView.swift`
- `views/iPad/Groups Views/iPad_GroupMapView.swift`
- `views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift`
- `views/iPhone/Devices Views/DeviceHistoryMap/iPhone_DeviceHistoryMapView.swift`
- `views/iPhone/iPhone_VisitorHistoryView.swift`
- `views/iPhone/iPhone_MyDeviceQRCodeView.swift`
- `views/iPhone/Devices Views/iPhone_EditDeviceView.swift`
- `views/iPhone/iPhone_DeviceKeySheetView.swift`
- `views/Common/MutualNavigationDetector.swift`

## Tests

- `miataruTests/MiataruRequestExecutorTests.swift`
  - Klassifikation retrybar/nicht-retrybar
  - Retry-Versuchszahlen und Backoff-Aufruf
- `miataruTests/LocationUpdateOutboxStoreTests.swift`
  - FIFO, Cap, TTL, Dedupe
- `miataruTests/LocationUpdateDeliveryCoordinatorTests.swift`
  - Queueing bei transienten Fehlern
  - Flush-Stop bei transientem Head
  - Verwerfen non-retryable und Weiterverarbeitung

## Rollout-Reihenfolge

1. Zentraler Executor + Retry-Klassifikation + Fassade
2. Read-Migration
3. Write-Migration (ohne `updateLocation`)
4. `updateLocation` Outbox + Flush-Trigger
5. Tests + Dokumentationsupdates

## Harte Randbedingung (eingehalten)

- Keine Änderung in `miataru/Libraries/MiataruClientSwift/**`.
- Retry, Klassifikation und Outbox leben vollständig unter `miataru/miataru/**`.
