# Test-Neustrukturierung mit dedizierten Schemes und Screenshot-Suite (seriell, 1 Simulator)

## Kurzfassung
Das ist möglich und passt zu Xcode-Schemes + Test Plans.  
Stand heute (1. März 2026) ist `iPad Pro 13-inch (M5)` als Simulator vorhanden; `iPhone 16 Pro Max` ist als Device-Type vorhanden und wird bei Bedarf automatisch als Simulator-Instanz erzeugt.

## Implementierungsplan

### 1) Kategorisierung und Zielbild fest verdrahten
1. Kategorisierung auf Target-/Suite-Ebene einführen:
- `CORE_UNIT` = `miataruTests`
- `FUNCTIONAL_UI` = `miataruUITests`
- `SCREENSHOT_CAPTURE` = neues Target `miataruScreenshotUITests`
2. Mapping auf Schemes:
- `miataru-FunctionalUI` führt `CORE_UNIT + FUNCTIONAL_UI` aus (deine Auswahl: inkl. Unit).
- `miataru-Screenshots` führt nur `SCREENSHOT_CAPTURE` aus und wird nie im Standardlauf genutzt.
3. Testkatalog entsprechend erweitern in [documentation/test-katalog.md](/Users/bietiekay/code/miataru-ios-app/documentation/test-katalog.md).

### 2) Neue Test-Pläne mit serieller Ausführung
1. Neuen Plan `FunctionalSerial.xctestplan` anlegen unter [miataru](/Users/bietiekay/code/miataru-ios-app/miataru):
- Enthält `miataruTests` und `miataruUITests`.
- Parallelisierung aus.
- Deterministische Reihenfolge (lexikalisch).
2. Neuen Plan `Screenshots.xctestplan` anlegen:
- Enthält nur `miataruScreenshotUITests`.
- Parallelisierung aus.
- Deterministische Reihenfolge (lexikalisch).
3. Beide Pläne in [miataru.xcodeproj/project.pbxproj](/Users/bietiekay/code/miataru-ios-app/miataru/miataru.xcodeproj/project.pbxproj) und Schemes referenzieren.

### 3) Schemes anlegen und entkoppeln
1. Neues Shared Scheme `miataru-FunctionalUI` in [xcshareddata/xcschemes](/Users/bietiekay/code/miataru-ios-app/miataru/miataru.xcodeproj/xcshareddata/xcschemes) mit `FunctionalSerial.xctestplan`.
2. Neues Shared Scheme `miataru-Screenshots` mit `Screenshots.xctestplan`.
3. Bestehendes Scheme `miataru` bleibt Build/Run-fokussiert; Screenshot-Tests werden dort nicht aktiviert.

### 4) Neues Screenshot-UI-Testtarget und Testklasse
1. Neues UI-Testtarget `miataruScreenshotUITests` anlegen in [miataru.xcodeproj/project.pbxproj](/Users/bietiekay/code/miataru-ios-app/miataru/miataru.xcodeproj/project.pbxproj).
2. Neuer Ordner [miataruScreenshotUITests](/Users/bietiekay/code/miataru-ios-app/miataru/miataruScreenshotUITests) mit:
- `ScreenshotBaseUITestCase.swift`
- `FeatureScreenshotScenariosUITests.swift`
3. Bis zu 10 Szenarien als deterministische Testmethoden (lexikalisch nummeriert `test_01...test_10`).
4. Jeder Shot als `XCTAttachment` (`.keepAlways`) mit klarer Namenskonvention:
- `<scenarioIndex>_<scenarioSlug>__<lang>__<device>.png` (Dateiname wird beim Export finalisiert).

### 5) App-Hooks für reproduzierbare Screenshot-Zustände
1. Bestehende UI-Test-Launch-Args in [miataruApp.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/miataruApp.swift) erweitern um Screenshot-spezifische Flags:
- `-ui-screenshot-mode`
- `-ui-screenshot-scenario <id>`
2. Deterministisches Seeding/Initialzustand nur im UI-Testmodus aktivieren.
3. Fehlende iPad-relevante Accessibility-Identifier ergänzen (wo nötig), damit Szenarien stabil navigierbar sind.

### 6) Expliziter Trigger per Skript (gewählt)
1. Neues Skript [scripts/test-functional-ui-serial.sh](/Users/bietiekay/code/miataru-ios-app/miataru/scripts/test-functional-ui-serial.sh):
- Führt `miataru-FunctionalUI` seriell aus.
- Erzwingt 1 Worker / 1 Sim-Destination:
`-parallel-testing-enabled NO`
`-parallel-testing-worker-count 1`
`-maximum-parallel-testing-workers 1`
`-maximum-concurrent-test-simulator-destinations 1`
2. Neues Skript [scripts/test-screenshots.sh](/Users/bietiekay/code/miataru-ios-app/miataru/scripts/test-screenshots.sh):
- Läuft nur bei explizitem Trigger.
- Erzeugt fehlende Simulator-Instanzen für:
`iPhone 16 Pro Max`, `iPad Pro 13-inch (M5)`.
- Iteriert seriell über alle unterstützten Sprachen:
`en, de, ja, fr, es, zh-Hans, nl, da, it, fi`
- Pro Sprache/Gerät: Testlauf + `xcresult` Attachment-Export per `xcrun xcresulttool export attachments`.
3. Exportziel zentral:
- `artifacts/screenshots/<language>/<device>/...png`
- `artifacts/screenshots/manifest.json`
4. In [.gitignore](/Users/bietiekay/code/miataru-ios-app/.gitignore) Artefaktpfade ergänzen (`artifacts/screenshots`, `artifacts/xcresult`).

### 7) Dokumentation und Betriebsregeln
1. [documentation/test-katalog.md](/Users/bietiekay/code/miataru-ios-app/documentation/test-katalog.md) um neue Kategorien/Schemes erweitern.
2. Neue Doku [documentation/screenshot-test-workflow.md](/Users/bietiekay/code/miataru-ios-app/documentation/screenshot-test-workflow.md) mit:
- Trigger-Befehlen
- Geräte/Sprachen
- Artefaktstruktur
- Troubleshooting (fehlende Runtime, leere Attachments, Skip-Logik).

## Wichtige öffentliche Interfaces/Änderungen
- Neue Shared Schemes: `miataru-FunctionalUI`, `miataru-Screenshots`.
- Neue Test-Pläne: `FunctionalSerial.xctestplan`, `Screenshots.xctestplan`.
- Neues UI-Testtarget: `miataruScreenshotUITests`.
- Neue UI-Test-Launch-Argumente in der App:
`-ui-screenshot-mode`, `-ui-screenshot-scenario`.
- Neue CLI-Einstiegspunkte:
`scripts/test-functional-ui-serial.sh`, `scripts/test-screenshots.sh`.
- Neues Artefakt-Interface:
`artifacts/screenshots/<lang>/<device>/*.png` plus `manifest.json`.

## Testfälle und Akzeptanzkriterien
1. `xcodebuild -showTestPlans` zeigt beide neuen Test-Pläne in den neuen Schemes.
2. Functional-Script startet nie mehr als eine Simulator-Testdestination gleichzeitig.
3. Screenshot-Suite läuft nur über `miataru-Screenshots`/`test-screenshots.sh`, nicht im normalen `miataru`-Lauf.
4. Für jede Sprache und jedes der zwei Geräte werden PNGs exportiert, maximal 10 pro Laufgruppe, mit Manifest-Eintrag.
5. Nicht erreichbare Szenarien werden sauber als Skip protokolliert (gewählte „bis zu 10“-Strategie), ohne Gesamtrun zu destabilisieren.
6. Wiederholter Lauf erzeugt reproduzierbare Dateinamen/Ordnerstruktur und überschreibt konsistent.

## Annahmen und fest gewählte Defaults
- Alle unterstützten Sprachen werden genutzt: `en,de,ja,fr,es,zh-Hans,nl,da,it,fi`.
- Exakte Zielgeräte sind Pflicht; fehlende Simulator-Instanzen werden automatisch erstellt.
- Screenshot-Ausgabe erfolgt über `xcresult`-Attachments und Export, nicht über direkten Dateischreibzugriff aus Tests.
- Screenshot-Gruppe ist strikt opt-in und wird nur explizit getriggert.
- Bestehende Haupt-App-Struktur bleibt erhalten; Änderungen sind auf Test-Infrastruktur, minimale UI-Test-Hooks und Doku begrenzt.
