# App Intents Manual Test Plan

Stand: 2026-06-10

## Vorbereitung

1. App auf einem iPhone oder Simulator installieren.
2. Mindestens eine Person bzw. ein Device in Miataru einrichten.
3. Sicherstellen, dass fuer diese Person `hasCurrentLocationAccess` aktiv ist und eine aktuelle Server-Location existiert.
4. Kurzbefehle-App oeffnen.
5. Nach Miataru-Aktionen suchen.
6. Optional die Geraetesprache auf eine unterstuetzte App-Sprache stellen und pruefen, dass Titel, Parameter, Dialoge und Fehler lokalisiert erscheinen.

## Person finden

1. Aktion "Person finden" auswaehlen.
2. Eine vorgeschlagene Person auswaehlen.
3. Kurzbefehl ausfuehren.
4. Pruefen, ob der Dialog Anzeigename, Alter der Position und eine grobe Ortsbeschreibung bzw. den Fallback enthaelt.
5. Pruefen, dass keine DeviceID, kein DeviceKey und keine rohe API-Antwort angezeigt wird.
6. Siri testen, zum Beispiel: "Where is [Name] in Miataru?"
7. Pruefen, dass die App nicht automatisch geoeffnet wird.
8. Pruefen, dass beim Ausfuehren kein Shortcuts-Fehler zu `TrackedPersonEntity` oder `EntityIdentifier` erscheint.

## Route zu Person

1. Aktion "Route zu Person" auswaehlen.
2. Eine vorgeschlagene Person auswaehlen.
3. Kurzbefehl ausfuehren.
4. Pruefen, dass Apple Maps mit einer Route zur letzten bekannten Koordinate geoeffnet wird.
5. Siri testen, zum Beispiel: "Route to [Name] in Miataru."
6. Pruefen, dass die Maps-URL keine DeviceID enthaelt.

## Haeufige Verfolgung starten

1. Aktion "Haeufige Verfolgung starten" bzw. "Start Frequent Tracking" auswaehlen.
2. Mit ausgeschalteter normaler Standortverfolgung ausfuehren: erwartete Meldung, dass Standortverfolgung zuerst in Miataru aktiviert werden muss.
3. Normale Standortverfolgung aktivieren und sicherstellen, dass iOS "Immer" Standortzugriff erlaubt.
4. Aktion erneut ausfuehren.
5. Pruefen, dass der manuelle Frequent-Background-Override aktiv ist und die vorhandene Dauer-Einstellung verwendet.
6. Aktion ein zweites Mal ausfuehren und pruefen, dass die Ablaufzeit erneuert wird.
7. Siri testen, zum Beispiel: "Start frequent tracking in Miataru."
8. Pruefen, dass die App nicht automatisch geoeffnet wird und keine DeviceID, kein DeviceKey und keine Serverdaten gesprochen werden.

## Haeufige Verfolgung stoppen

1. Manuellen Frequent-Background-Override aktivieren.
2. Aktion "Haeufige Verfolgung stoppen" bzw. "Stop Frequent Tracking" auswaehlen.
3. Kurzbefehl ausfuehren.
4. Pruefen, dass der manuelle Frequent-Override ausgeschaltet ist und normale Standardverfolgung unveraendert bleibt.
5. Aktion erneut ausfuehren: erwartete Meldung, dass haeufige Verfolgung bereits ausgeschaltet war.
6. Siri testen, zum Beispiel: "Stop frequent tracking in Miataru."
7. Pruefen, dass die App nicht automatisch geoeffnet wird.

## Fehlerfaelle

1. Ohne eingerichtete Personen ausfuehren: erwartete Meldung "Keine Personen eingerichtet".
2. Person aus Miataru entfernen und bestehenden Kurzbefehl erneut ausfuehren: erwartete Meldung "Person nicht mehr verfuegbar".
3. `hasCurrentLocationAccess` fuer eine Person deaktivieren: Person darf nicht vorgeschlagen werden; ein alter Kurzbefehl muss mit Berechtigungsfehler abbrechen.
4. Server nicht erreichbar machen: erwartete Meldung fuer Netzwerk-/Serverfehler.
5. Person ohne Location testen: erwartete Meldung "Noch kein Standort verfuegbar".
6. "Haeufige Verfolgung starten" mit DeviceKey-Auth-Blockade ausfuehren: erwartete Meldung, dass Miataru geoeffnet und der DeviceKey aktualisiert werden muss.
7. "Haeufige Verfolgung starten" ohne Always-Standortberechtigung ausfuehren: erwartete Meldung, dass Always-Zugriff benoetigt wird.

## Spaeter

Die Aktion "Ist Person in der Naehe von Ort?" ist in dieser Runde bewusst nicht enthalten. Sobald eine persistente Orte-Datenquelle existiert, manuell testen:

1. Gespeicherten Ort wie Zuhause oder Arbeit anlegen.
2. Naehe-Aktion in Kurzbefehle suchen.
3. Person, Ort und Radius auswaehlen.
4. Rueckgabewert `true`/`false` in einer Automation verwenden.
5. Distanzberechnung mit bekannten Testkoordinaten plausibilisieren.

iOS 27 / App Actions spaeter erneut pruefen:

1. Mit iOS-27-SDK nach passenden Apple App Schemas fuer Location-, Navigation- oder Share-Status-Aktionen suchen.
2. `TrackedPersonEntity` mit `IndexedEntity` und Siri/Spotlight testen, falls die frueheren dynamischen `AppEntity`-Probleme behoben sind.
3. `AppIntentsTesting` fuer automatisierte Intent-Ausfuehrung in einer iOS-27-Testspur evaluieren.
