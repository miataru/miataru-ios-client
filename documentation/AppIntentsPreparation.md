# App Intents Preparation

Stand: 2026-06-09

## Ziel

Diese Notiz dokumentiert die erste Vorbereitung fuer Siri und Kurzbefehle in Miataru. Implementiert werden die Grundlagen fuer:

- "Person finden": letzte bekannte Position einer eingerichteten Person bzw. eines Devices abrufen.
- "Route zu Person": Apple Maps mit der letzten bekannten Zielkoordinate oeffnen.

Die Naehepruefung gegen gespeicherte Orte ist bewusst verschoben, weil in der App aktuell keine passende persistente Orte-Datenquelle existiert.

## Gefundene relevante Modelle

- `KnownDevice` (`miataru/miataru/SettingsManagers/App Settings/Devices/KnownDevice.swift`): enthaelt `DeviceName`, `DeviceID`, Zugriffsflags wie `hasCurrentLocationAccess` und `hasHistoryAccess` sowie Sortier-/Darstellungsmetadaten.
- `KnownDeviceStore.shared.devices`: zentrale lokale Datenquelle fuer eingerichtete Devices/Personen.
- `MiataruLocationData` aus `MiataruAPIClient`: API-Modell fuer Server-Locations mit DeviceID, Koordinate, Genauigkeit und Zeitstempel.
- `DeviceLocationCacheStore`: bestehender Cache fuer letzte Device-Locations und bereits bekannte Reverse-Geocoding-Ergebnisse.

Nach aussen verwenden App Intents den Begriff "Person", intern bleiben die vorhandenen Device-Modelle die Quelle.

## Gefundene relevante Services

- `MiataruAppAPI.getLocation(...)`: bestehender Adapter fuer `getLocation`, inklusive Server-Konfiguration, API-Zaehler und Cache-Integration.
- `DeviceLocationCacheStore.shared.getPlacemark(for:)`: liefert vorhandene grobe Ortsdaten wie Ort/Land, ohne ein neues Reverse-Geocoding im Intent zu erzwingen.
- `DeviceLinkResolver` und `AppNavigationCoordinator`: vorhandenes URL-Scheme `miataru://<deviceID>` fuehrt zur Device-Ansicht in Miataru. Fuer "Route zu Person" wird dieses Scheme nicht verwendet, weil es keine Routen-Navigation oeffnet.

## Neue Dateien

- `miataru/miataru/Services/IntentLocationService.swift`
  - `IntentLocationServicing`
  - `IntentLocationService`
  - `IntentPersonLocation`
  - `IntentLocationError`
  - kleine Provider-/Mapping-Schicht fuer Tests ohne echten Server
- `miataru/miataru/AppIntents/Entities/TrackedPersonEntity.swift`
- `miataru/miataru/AppIntents/Queries/TrackedPersonQuery.swift`
- `miataru/miataru/AppIntents/Intents/FindPersonLocationIntent.swift`
- `miataru/miataru/AppIntents/Intents/OpenRouteToPersonIntent.swift`
- `miataru/miataru/AppIntents/Views/PersonLocationSnippetView.swift`
- `miataru/miataru/AppIntents/MiataruAppShortcutsProvider.swift`

## Architekturentscheidungen

- App Intents greifen nicht direkt auf SwiftUI-Views oder ViewModels zu.
- `TrackedPersonQuery` bietet nur Devices mit nicht leerer `DeviceID` und `hasCurrentLocationAccess == true` an.
- Die produktiv registrierten Intent-Parameter verwenden aktuell `TrackedPersonOptionsProvider` als dynamische String-Auswahl. Das vermeidet einen Shortcuts-Runtime-Fehler, bei dem dynamische `AppEntity`-Auswahlen als "not a registered AppEntity identifier" abgewiesen werden koennen.
- Siri-/Dialogtexte enthalten Anzeigename, Alter und grobe Ortsbeschreibung, aber keine DeviceID, DeviceKey oder rohe API-Antwort.
- `FindPersonLocationIntent` oeffnet die App nicht automatisch.
- `OpenRouteToPersonIntent` oeffnet Apple Maps ueber `http://maps.apple.com/?daddr=<lat>,<lon>`.
- Die vorbereitete Snippet View ist noch nicht mit `ShowsSnippetView` verdrahtet, weil die im lokal installierten SDK sichtbare Signatur erst ab iOS 26 verfuegbar ist.
- Intent-Titel, Beschreibungen, Parameter, Dialoge, Fehler, Shortcut-Titel und Snippet-Vorbereitungstexte sind im bestehenden String Catalog fuer alle zehn App-Locale gepflegt.

## Offene Annahmen

- Die Reihenfolge aus `KnownDeviceStore.shared.devices` ist auch fuer Siri-/Kurzbefehle-Vorschlaege passend.
- Es gibt aktuell keine Favoritenlogik, die App Intents bevorzugen koennten.
- Es gibt keine separate Einstellung "In Siri/Kurzbefehle anzeigen"; bis dahin gilt `hasCurrentLocationAccess` als Sichtbarkeits- und Berechtigungsgrenze.
- Es gibt keine bestehende App-Logik fuer "Location zu alt", daher wird nur "keine Location" gesondert behandelt.
- Auf gesperrtem Geraet wird aktuell keine feinere Reduktion der Ausgabe implementiert; die Dialoge bleiben generell datensparsam.

## Risiken und TODOs

- Optional spaeter: pro Person/Device eine explizite Siri-/Kurzbefehle-Freigabe ergaenzen.
- Optional spaeter: erneut pruefen, ob `TrackedPersonEntity` direkt als Shortcut-Parameter stabil nutzbar ist; die vorbereitete Entity-/Query-Schicht bleibt dafuer im Projekt.
- Optional spaeter: gespeicherte Orte als eigenes Modell einfuehren und darauf `MiataruPlaceEntity`, `MiataruPlaceQuery` und `IsPersonNearPlaceIntent` aufbauen.
- Optional spaeter: route-spezifischen Miataru-Deep-Link einfuehren, falls die App selbst eine Navigationsansicht oeffnen soll.
- Optional spaeter: Snippet View aktiv verdrahten, sobald das Deployment Target und die AppIntents-APIs dies sauber zulassen.
- Optional spaeter: App-Shortcut-Phrasen pro Sprache ueber Apples AppShortcuts-Lokalisierungsweg pflegen; die aktuelle Implementierung belaesst die Parameter-Phrasen in der stabilen englischen AppIntents-Phrase-Syntax.
- Manuelle Siri-Tests bleiben noetig, weil App Shortcut Phrasen und Siri-Erkennung erst auf Geraet bzw. Simulator realistisch sichtbar werden.
