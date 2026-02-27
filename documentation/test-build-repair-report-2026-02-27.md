# Test Build Repair Report (2026-02-27)

## Ziel

Defekte Test-Build-Konfiguration und Test-Einbindung im Projekt vollständig prüfen, reparieren und verifizieren.

## Durchgeführte Arbeiten

1. Scheme/Test-Konfiguration repariert:
   - `miataruTests` und `miataruUITests` in der shared scheme aktiv gesetzt.
   - Parallele Ausführung für beide Testables deaktiviert, um instabile/flaky Läufe zu vermeiden.
2. Projektverdrahtung überprüft:
   - UI-Test-Ordner als synchronisierte Gruppe im Xcode-Projekt eingebunden.
   - Historisch falsch platzierte Testdateien unter `miataru.xcodeproj/` in aktive Testordner überführt.
3. UI-Test-Integration stabilisiert:
   - `ExtendedUITests` auf robuste, deterministische Flows umgestellt.
   - Tab-Navigation in UI-Tests explizit und stabil ausgewählt.
   - App-seitige UI-Test-Guards ergänzt (u. a. störende Banner/Auto-Navigation im UI-Test-Modus reduziert).
4. Test-Dokumentation aktualisiert:
   - `documentation/test-katalog.md`
   - `documentation/test-gap-matrix.md`
   - Testnamen und Scope an den finalen UI-Testbestand angepasst.

## Verifikation

- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:miataruTests test`  
  Ergebnis: **60/60 bestanden**
- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:miataruUITests test`  
  Ergebnis: **4/4 bestanden**
- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17' test`  
  Ergebnis: **TEST SUCCEEDED**

## Status

Test-Build-Konfiguration und Test-Einbindung sind wieder funktionsfähig und vollständig grün verifiziert.
