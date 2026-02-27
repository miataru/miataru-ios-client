# Test Gap Matrix (Stand: 2026-02-27)

## Zweck

Diese Matrix zeigt pro Kernbereich:

- Risiko bei Fehlern
- Aktuelle Testabdeckung (aktiv vs. nur vorhanden)
- Konkrete Luecken
- Priorisierte naechste Testschritte

Bewertungsskala:

- `Abdeckung`: Hoch / Mittel / Niedrig / Keine
- `Gap`: Niedrig / Mittel / Hoch / Kritisch

## Gap Matrix

| Bereich / Komponente | Risiko | Aktive Unit-Tests | Vorhandene aber nicht eingebundene Tests | Aktive Integration | Aktive UI/E2E | Abdeckung | Gap | Naechster Schritt |
|---|---|---|---|---|---|---|---|---|
| Route Cache + Refresh + Ghost (`RouteCacheStore`, `NavigationRouteRefreshPolicy`, `RouteGhostCalculator`) | Hoch | Ja (27) | Nein | Nein | Nein | Mittel-Hoch | Mittel | Integrations-Tests fuer End-to-End Recalc-Entscheidungen (Route vorhanden, stale, off-route, reverse). |
| Mutual Navigation + Visitor-Timestamps (`MutualNavigationDetector`, `MiataruVisitor`) | Hoch | Ja (4) | Nein | Nein | Nein | Niedrig-Mittel | Hoch | Klassenverhalten testen (State-Transition enter/stay/exit), nicht nur Zeit-Differenzen. |
| Visitor History + Known Device Aufloesung (`VisitorHistoryViewModel`, `KnownDeviceStore`) | Mittel | Ja (5) | Nein | Nein | Nein | Mittel | Mittel | Persistenz-/Nebenlaeufigkeits-Tests (duplicate IDs, case-insensitive merge, race-safe updates). |
| Map Helper + Polyline Geometrie (`MapHelpers`, `MKPolyline` Extensions) | Hoch | Ja (23) | Nein | Nein | Nein | Mittel-Hoch | Mittel | Assert-Schaerfung fuer numerische Randfaelle und Regressionen bei Distanzprojektion. |
| Standort-Update Pipeline (`LocationManager`, `DeviceLocationRefresher`) | Sehr hoch | Nein | Nein | Nein | Nein | Keine | Kritisch | Integrations-Tests fuer GPS-Update, Netzwerkfehler, Retry/Backoff, Hintergrundverhalten. |
| Device Access / Sync (`AllowedDeviceListManager`, SyncQueue) | Hoch | Nein | Nein | Nein | Nein | Keine | Hoch | Tests fuer Sync-Triggers, Konfliktfaelle, Fehlerpfade, idempotentes Synchronisieren. |
| Persistenz-Stores (`DeviceLocationCacheStore`, `DeviceHistoryCacheStore`, `DeviceGroupStore`, `DeviceSloganCacheStore`) | Hoch | Teilweise indirekt | Nein | Nein | Nein | Niedrig | Hoch | Serialization roundtrip, migrationssichere Loads, corruption handling, thread-safety. |
| Widget Datenfluss (`WidgetDataSyncCoordinator`, `SharedWidgetData`, `WidgetMapSnapshotGenerator`) | Mittel-Hoch | Nein | Nein | Nein | Nein | Keine | Hoch | Contract-Tests fuer Payload-Formate, Datenfilterung und Snapshot-Fehlerfaelle. |
| Device Key / Auth (`DeviceKeyAuthHandler`) | Hoch | Nein | Nein | Nein | Nein | Keine | Hoch | Unit-Tests fuer Signatur-/Formatvalidierung und harte Negativfaelle. |
| Core UI Flows (Onboarding, Device/Group Listen, Navigation Screens) | Sehr hoch | Nein | Nein | Nein | Ja (4 deterministische Flows) | Mittel | Mittel-Hoch | Naechster Ausbau: Device-Map, Gruppen-Flow und Navigation start/stop inkl. Abbruchpfade. |
| App Bootstrap (`miataruApp`, `AppState`, `AppDelegate`) | Mittel | Nein | Nein | Nein | Nein | Keine | Mittel-Hoch | Smoke Integration fuer App-Startzustand, Initial-Settings, Notification/permission branching. |

## Priorisierte Backlog-Liste

| Prio | Gap | Warum | Konkrete Testarbeit |
|---|---|---|---|
| P0 (erledigt 2026-02-27) | Vorhandene ausgelagerte Tests aktivieren | Erledigt: Unit/UI-Bestand ist jetzt in aktiven Targets verankert | Verschiebung in `miataruTests` und `miataruUITests` + Target-Synchronisierung abgeschlossen. |
| P1 (erledigt 2026-02-27) | UI-Suite aus Smoke in stabile Kernfluesse ueberfuehren | Erledigt: deterministische UI-Grundpfade decken Start, Add-Device, Settings-Onboarding-Aktion und QR-Basisaktion ab | `ExtendedUITests` auf 4 robuste Szenarien erweitert. |
| P1 | Keine Integrations-Tests fuer Standort-/Routing-Pipeline | Kernfunktion der App, viele Abhaengigkeiten | Integrationstest-Setup mit Fake Location + Fake API fuer Route/Update Lifecycle. |
| P1 | Keine Tests fuer AllowedDevice Sync | Datenkonsistenz und Zugriffslogik kritisch | Unit + Integration fuer SyncQueue, Konfliktbehandlung, Wiederholbarkeit. |
| P2 | Persistenz-Stores kaum abgedeckt | Fehler zeigen sich oft erst bei Real-Daten | Roundtrip- und Fehlerfalltests fuer NSCoding/UserDefaults/FileStore. |
| P2 | Widget Pipeline ungetestet | Sichtbare Inkonsistenzen zwischen App/Widget moeglich | Contract-Tests fuer Shared payload und Snapshot-Generierung. |

## Pflege-Regel fuer diese Matrix

Bei jeder Aenderung an Tests (neu, geloescht, umbenannt, erweitert) muss diese Datei aktualisiert werden:

1. Zaehler/Fakten in der Matrix korrigieren.
2. Betroffenen Bereich in `Abdeckung` und `Gap` neu bewerten.
3. Falls noetig Prioritaeten im Backlog anpassen.
