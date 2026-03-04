# Miataru Retry/Outbox Implementierung (Stand 2026-03-04)

## Ziel

Die Miataru-API-Resilienz wurde im App-Code zentralisiert, ohne Änderungen an `miataru/Libraries/MiataruClientSwift/**`.

## Architektur

### 1. Retry-Schicht (App-intern)

- `miataru/miataru/Networking/MiataruRetryPolicy.swift`
  - Retry-Profile:
    - Reads: `maxRetries=1`, Backoff `0.8s`, Jitter `±25%`
    - Writes: `maxRetries=1`, Backoff `1.0s`, Jitter `±25%`
    - `updateLocation`: `maxRetries=1`, Backoff `1.2s`, Jitter `±25%`
- `miataru/miataru/Networking/MiataruRetryPolicy.swift` (enthält auch `MiataruRetryClassifier`)
  - Retrybar: transiente `URLError` + HTTP `408/429/5xx`
  - Nicht retrybar: `invalidURL`, `encodingError`, `decodingError`, Auth/ACL `401/403`, sonstige fachliche `4xx`
- `miataru/miataru/Networking/MiataruRequestExecutor.swift`
  - Zentraler Executor für Retry inklusive Jitter/Backoff.
- `miataru/miataru/Networking/MiataruAppAPI.swift`
  - Fassade für alle Miataru-App-Calls mit zentralem Retry.

### 2. `updateLocation` Outbox

- `miataru/miataru/Networking/LocationUpdateOutboxStore.swift`
  - Persistente FIFO-Queue in App Support: `locationUpdateOutbox.json`
  - Cap: `500`
  - TTL: `24h`
  - Dedupe-Key: `Device + Timestamp + Latitude + Longitude`
- `miataru/miataru/Networking/LocationUpdateDeliveryCoordinator.swift`
  - Direct-send für `updateLocation`
  - Bei transientem Fehler: enqueue in Outbox
  - Flush-Trigger:
    - App aktiv
    - Netzwerk wieder verfügbar
    - periodischer Timer (`60s`) solange Outbox nicht leer
  - Flush-Batchgröße: `25`
  - Fehlerregeln:
    - transient am Head: Flush stoppt, nächster Trigger übernimmt
    - non-retryable: Item wird verworfen, nächste Items laufen weiter

## Integrierte Flows

- `LocationManager` verwendet jetzt den DeliveryCoordinator für `updateLocation`.
- Read-/Write-Callsites im App-Target wurden auf `MiataruAppAPI` migriert.
- Widget bleibt bewusst ohne Retry (direkter Client-Call).
- `AllowedDeviceListManager` nutzt jetzt zentrales Retry statt lokalem custom Retry-Loop.

## User-/UX-Verhalten

- Automatische Flows bleiben still.
- Bei `updateLocation` transienten Fehlern werden Updates in Outbox gepuffert statt hart zu fehlschlagen.
- Non-retryable Auth/ACL-Fehler verhalten sich weiterhin als sichtbarer Fehlerpfad.

## Geräte-Test-Checkliste

1. Tracking aktivieren, `updateLocation` senden lassen.
2. Netz kurz deaktivieren (Flugmodus/WLAN+Mobil aus), dann wieder aktivieren.
3. Prüfen:
   - Während Offline-Phase keine Abstürze/Blockaden.
   - Nach Netz-Recovery werden queued Updates schrittweise ausgeliefert.
4. Read-Flows testen (Devices/Groups/History):
   - Kurzzeitige Netzstörung sollte durch 1 Retry abgefedert werden.
5. Auth/ACL-Fehler testen:
   - DeviceKey-Mismatch bleibt non-retryable und sichtbar.

## Hinweis

Die Miataru Client Library wurde nicht angepasst; alle Änderungen liegen ausschließlich im App-Code.
