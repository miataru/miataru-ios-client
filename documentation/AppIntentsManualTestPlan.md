# App Intents Manual Test Plan

Stand: 2026-06-09

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

## Fehlerfaelle

1. Ohne eingerichtete Personen ausfuehren: erwartete Meldung "Keine Personen eingerichtet".
2. Person aus Miataru entfernen und bestehenden Kurzbefehl erneut ausfuehren: erwartete Meldung "Person nicht mehr verfuegbar".
3. `hasCurrentLocationAccess` fuer eine Person deaktivieren: Person darf nicht vorgeschlagen werden; ein alter Kurzbefehl muss mit Berechtigungsfehler abbrechen.
4. Server nicht erreichbar machen: erwartete Meldung fuer Netzwerk-/Serverfehler.
5. Person ohne Location testen: erwartete Meldung "Noch kein Standort verfuegbar".

## Spaeter

Die Aktion "Ist Person in der Naehe von Ort?" ist in dieser Runde bewusst nicht enthalten. Sobald eine persistente Orte-Datenquelle existiert, manuell testen:

1. Gespeicherten Ort wie Zuhause oder Arbeit anlegen.
2. Naehe-Aktion in Kurzbefehle suchen.
3. Person, Ort und Radius auswaehlen.
4. Rueckgabewert `true`/`false` in einer Automation verwenden.
5. Distanzberechnung mit bekannten Testkoordinaten plausibilisieren.
