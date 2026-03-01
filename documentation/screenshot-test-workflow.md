# Screenshot Test Workflow

## Ziel

Deterministische, explizit getriggerte Screenshot-Captures fuer alle unterstuetzten Sprachen auf genau zwei Zielgeraeten:

- `iPhone 16 Pro Max`
- `iPad Pro 13-inch (M5)`

Die Suite laeuft seriell (maximal 1 parallele Simulator-Instanz) und ist von regulaeren Testlaeufen getrennt.

## Konfiguration

- Shared Scheme: `miataru-Screenshots`
- Testplan: `Screenshots.xctestplan`
- Testtarget: `miataruScreenshotUITests`
- Trigger-Skript: `miataru/scripts/test-screenshots.sh`

## Trigger

Screenshot-Suite explizit starten:

```bash
cd miataru
./scripts/test-screenshots.sh
```

Verfuegbare Screenshot-Tests anzeigen:

```bash
cd miataru
./scripts/test-screenshots.sh --list
```

Gezielt nur einen (oder mehrere) Screenshot-Tests ausfuehren:

```bash
cd miataru
./scripts/test-screenshots.sh --test root-qr
./scripts/test-screenshots.sh --test test_03_root_settings
./scripts/test-screenshots.sh --test root-qr --test settings-navigation
```

Funktionale/UI-Serienlaeufe (Unit + Functional UI) starten:

```bash
cd miataru
./scripts/test-functional-ui-serial.sh
```

## Sprachen und Regionen

Der Lauf verwendet standardmaessig:

- `en`/`US`
- `de`/`DE`
- `ja`/`JP`
- `fr`/`FR`
- `es`/`ES`
- `zh-Hans`/`CN`
- `nl`/`NL`
- `da`/`DK`
- `it`/`IT`
- `fi`/`FI`

Optional kannst du den Sprachumfang eingrenzen:

```bash
cd miataru
LANGUAGES_CSV="en,de" ./scripts/test-screenshots.sh --test root-qr
```

Version/Build optional manuell ueberschreiben:

```bash
cd miataru
APP_VERSION_OVERRIDE="3.1.2" APP_BUILD_OVERRIDE="6" ./scripts/test-screenshots.sh --test root-qr
```

## Simulator-Regeln

Das Skript prueft pro Geraet, ob eine exakt benannte Simulator-Instanz vorhanden ist. Falls nicht, wird sie automatisch mit dem passenden Device-Type und der neuesten verfuegbaren iOS-Runtime erzeugt.

## Artefaktstruktur

Alle PNGs und Metadaten landen unter:

- `miataru/artifacts/screenshots/<version-build-tag>/<language>/<device>/*.png`
- `miataru/artifacts/screenshots/<version-build-tag>/<language>/<device>/manifest.json`
- `miataru/artifacts/screenshots/<version-build-tag>/manifest.json` (aggregiert)
- `miataru/artifacts/xcresult/<version-build-tag>/*` (Result Bundles und Exportdaten)

`<version-build-tag>` wird standardmaessig aus dem App-Target gelesen:

- `MARKETING_VERSION` (Version)
- `CURRENT_PROJECT_VERSION` (Build)

Beispiel: `v3-1-2-b6`

## Skip-Verhalten ("bis zu 10")

Die Testklasse umfasst 10 deterministische Szenarien. Nicht erreichbare Szenarien werden per `XCTSkip` protokolliert, damit der Gesamtlauf robust bleibt und trotzdem verwertbare PNGs erzeugt.

## Troubleshooting

- Fehlende iOS-Runtime:
  - Pruefe `xcrun simctl list runtimes available`.
  - Installiere eine iOS-Simulator-Runtime in Xcode Settings.
- Leere PNG-Ausgabe:
  - Pruefe, ob Tests als Skip liefen.
  - Pruefe `*.xcresult` in `artifacts/xcresult`.
- Unerwartete UI-Ueberlagerungen:
  - Screenshot-Lauf nutzt `-ui-testing` und `-ui-screenshot-mode` fuer deterministischere Zustaende.
