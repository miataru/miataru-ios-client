# App Intents Preparation

Stand: 2026-06-10

## Ziel

Diese Notiz dokumentiert die erste Vorbereitung fuer Siri und Kurzbefehle in Miataru. Implementiert werden die Grundlagen fuer:

- "Person finden": letzte bekannte Position einer eingerichteten Person bzw. eines Devices abrufen.
- "Route in Apple Maps": Apple Maps mit der letzten bekannten Zielkoordinate oeffnen.
- "Navigation in Miataru": Miataru direkt in die interne Navigation vom User-Device zum Ziel-Device oeffnen; externe `miataru://` Deep Links bleiben fuer Safari/`simctl openurl` gueltig.
- "Haeufige Verfolgung starten": manuellen Frequent-Background-Override starten, ohne die normale Standortverfolgung einzuschalten.
- "Haeufige Verfolgung stoppen": manuellen Frequent-Background-Override stoppen, ohne die normale Standortverfolgung zu veraendern.

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
- `DeviceLinkResolver` und `AppNavigationCoordinator`: vorhandenes URL-Scheme `miataru://<deviceID>` fuehrt weiterhin zur Device-Ansicht in Miataru. Der neue Navigationslink `miataru://<deviceID>?action=navigate&direction=userToDevice&presentation=focused` oeffnet direkt die interne Miataru-Navigation.
- `SettingsManager.shared`: Quelle fuer normale Tracking-Aktivierung, DeviceKey-Blockade, manuelle Frequent-Background-Konfiguration, Dauer und Ablaufzeit.
- `LocationManager.shared`: Quelle fuer aktuelle Core-Location-Autorisierung und zentraler Reconcile-Pfad, damit Intent-Aktionen dieselbe Tracking-Umschaltung nutzen wie die App-UI.
- `FrequentBackgroundTrackingReminderService`: wird indirekt ueber bestehende Settings-/LocationManager-Beobachter aktualisiert, wenn der manuelle Frequent-Override startet oder stoppt.

## Neue Dateien

- `miataru/miataru/Services/IntentLocationService.swift`
  - `IntentLocationServicing`
  - `IntentLocationService`
  - `IntentPersonLocation`
  - `IntentLocationError`
  - kleine Provider-/Mapping-Schicht fuer Tests ohne echten Server
- `miataru/miataru/Services/IntentFrequentTrackingService.swift`
  - `IntentFrequentTrackingService`
  - `IntentFrequentTrackingError`
  - testbarer Controller fuer Start/Stop der manuellen Frequent-Background-Verfolgung
- `miataru/miataru/AppIntents/Entities/TrackedPersonEntity.swift`
- `miataru/miataru/AppIntents/Queries/TrackedPersonQuery.swift`
- `miataru/miataru/AppIntents/Intents/FindPersonLocationIntent.swift`
- `miataru/miataru/AppIntents/Intents/OpenRouteToPersonIntent.swift`
- `miataru/miataru/AppIntents/Intents/OpenMiataruNavigationToPersonIntent.swift`
- `miataru/miataru/AppIntents/Intents/StartFrequentTrackingIntent.swift`
- `miataru/miataru/AppIntents/Intents/StopFrequentTrackingIntent.swift`
- `miataru/miataru/AppIntents/Views/PersonLocationSnippetView.swift`
- `miataru/miataru/AppIntents/MiataruAppShortcutsProvider.swift`

## Architekturentscheidungen

- App Intents greifen nicht direkt auf SwiftUI-Views oder ViewModels zu.
- `TrackedPersonQuery` bietet nur Devices mit nicht leerer `DeviceID` und `hasCurrentLocationAccess == true` an.
- Die produktiv registrierten Intent-Parameter verwenden aktuell `TrackedPersonOptionsProvider` als dynamische String-Auswahl. Das vermeidet einen Shortcuts-Runtime-Fehler, bei dem dynamische `AppEntity`-Auswahlen als "not a registered AppEntity identifier" abgewiesen werden koennen.
- Siri-/Dialogtexte enthalten Anzeigename, Alter und grobe Ortsbeschreibung, aber keine DeviceID, DeviceKey oder rohe API-Antwort.
- `FindPersonLocationIntent` oeffnet die App nicht automatisch.
- `OpenRouteToPersonIntent` bleibt als bestehender Typ erhalten und oeffnet unter dem sichtbaren Namen "Route in Apple Maps" weiter Apple Maps ueber `http://maps.apple.com/?daddr=<lat>,<lon>`.
- `OpenMiataruNavigationToPersonIntent` verwendet dieselbe Personen-Auswahl und Berechtigungslogik, erzeugt weiter `miataru://<DeviceID>?action=navigate&direction=userToDevice&presentation=focused`, laesst Shortcuts aber Miataru selbst oeffnen und uebergibt die daraus geparste Navigation direkt an `AppNavigationCoordinator`.
- `DeviceLinkResolver` unterscheidet alte Device-Links und neue Navigation-Links strukturiert; alte Links oeffnen weiter nur die Device-Ansicht.
- `AppNavigationCoordinator` leitet bekannte Navigation-Links in einen Device-Navigation-Request und unbekannte DeviceIDs weiter in den Add-Device-Flow.
- `iPhone_DeviceNavigationView` kann Launch-Optionen annehmen: `direction=userToDevice` startet mit umgedrehter Route, `presentation=focused` schaltet nach verfuegbarer Route in den fokussierten Navigationsmodus.
- `StartFrequentTrackingIntent` und `StopFrequentTrackingIntent` sind bewusst parameterlos und verwenden die in Miataru konfigurierte manuelle Frequent-Background-Dauer.
- "Haeufige Verfolgung starten" schaltet `trackAndReportLocation` nicht ein. Die Aktion bricht mit einem lokalisierten Fehler ab, wenn normale Verfolgung aus ist, DeviceKey-Authentifizierung blockiert oder keine Always-Standortberechtigung vorhanden ist.
- Wiederholtes Starten erneuert die Ablaufzeit des manuellen Frequent-Overrides anhand der aktuellen Dauer-Einstellung.
- "Haeufige Verfolgung stoppen" ist idempotent: wenn der Override bereits aus ist, bleibt der Zustand unveraendert; normale Standardverfolgung wird nicht abgeschaltet.
- Die vorbereitete Snippet View ist noch nicht mit `ShowsSnippetView` verdrahtet, weil die im lokal installierten SDK sichtbare Signatur erst ab iOS 26 verfuegbar ist.
- Intent-Titel, Beschreibungen, Parameter, Dialoge, Fehler, Shortcut-Titel, Snippet-Vorbereitungstexte und von AppIntents extrahierte Parameter-Summary-Strings sind im bestehenden String Catalog fuer alle zehn App-Locale gepflegt.

## iOS 27 App Actions Untersuchung

Apple beschreibt "App Actions" fuer iOS 27 aktuell als Weiterentwicklung rund um App Intents, Intent-/Entity-Schemas, Spotlight Semantic Indexing und View-Annotierungen, nicht als separaten zweiten Framework-Pfad. Relevante Quellen:

- WWDC26 iOS Guide: https://developer.apple.com/wwdc26/guides/ios/
- Apple Intelligence What's New: https://developer.apple.com/apple-intelligence/whats-new/
- Build intelligent Siri experiences with App Schemas: https://developer.apple.com/videos/play/wwdc2026/240/
- Validate App Intents adoption with AppIntentsTesting: https://developer.apple.com/videos/play/wwdc2026/295/

Fuer Miataru bleiben die neuen Tracking-Aktionen vorerst normale App Intents/App Shortcuts. Der manuelle Frequent-Override passt aktuell nicht eindeutig auf eine bekannte Apple-App-Schema-Domaene. Spaeter mit iOS-27-SDK erneut pruefen:

- ob Location-, Navigation- oder Share-Status-Schemas passend fuer Miataru-Aktionen sind;
- ob `TrackedPersonEntity` als `IndexedEntity` bzw. schema-nahe Entity sicher fuer Siri/Spotlight bereitgestellt werden kann;
- ob View-Annotierungen fuer Device-/Map-/Detail-Zeilen Siri-Kontext wie "diese Person" verbessern;
- ob `AppIntentsTesting` fuer Intent-Integrationstests in einer iOS-27/Xcode-27-Testspur genutzt werden kann.

## Offene Annahmen

- Die Reihenfolge aus `KnownDeviceStore.shared.devices` ist auch fuer Siri-/Kurzbefehle-Vorschlaege passend.
- Es gibt aktuell keine Favoritenlogik, die App Intents bevorzugen koennten.
- Es gibt keine separate Einstellung "In Siri/Kurzbefehle anzeigen"; bis dahin gilt `hasCurrentLocationAccess` als Sichtbarkeits- und Berechtigungsgrenze.
- Es gibt keine bestehende App-Logik fuer "Location zu alt", daher wird nur "keine Location" gesondert behandelt.
- Auf gesperrtem Geraet wird aktuell keine feinere Reduktion der Ausgabe implementiert; die Dialoge bleiben generell datensparsam.
- Die Frequent-Tracking-Aktionen bleiben parameterlos; wenn Shortcuts spaeter pro Ausfuehrung eine Dauer setzen sollen, braucht das eine bewusste Erweiterung des Intent-Interfaces.

## Risiken und TODOs

- Optional spaeter: pro Person/Device eine explizite Siri-/Kurzbefehle-Freigabe ergaenzen.
- Optional spaeter: erneut pruefen, ob `TrackedPersonEntity` direkt als Shortcut-Parameter stabil nutzbar ist; die vorbereitete Entity-/Query-Schicht bleibt dafuer im Projekt.
- Optional spaeter: gespeicherte Orte als eigenes Modell einfuehren und darauf `MiataruPlaceEntity`, `MiataruPlaceQuery` und `IsPersonNearPlaceIntent` aufbauen.
- Optional spaeter: weitere Miataru-Navigationsoptionen als Shortcut-Parameter anbieten, z. B. Richtung oder Praesentationsmodus.
- Optional spaeter: Snippet View aktiv verdrahten, sobald das Deployment Target und die AppIntents-APIs dies sauber zulassen.
- Optional spaeter: App-Shortcut-Phrasen pro Sprache ueber Apples AppShortcuts-Lokalisierungsweg pflegen; die aktuelle Implementierung belaesst die Parameter-Phrasen in der stabilen englischen AppIntents-Phrase-Syntax.
- Manuelle Siri-Tests bleiben noetig, weil App Shortcut Phrasen und Siri-Erkennung erst auf Geraet bzw. Simulator realistisch sichtbar werden.
