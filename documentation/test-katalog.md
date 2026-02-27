# Test-Katalog (Stand: 2026-02-27)

## 1) Scope und Einordnung

Dieser Katalog trennt drei Bloecke:

1. **Aktiv eingebundene App-Tests** (`miataruTests` + `miataruUITests`)  
2. **Historisch ausgelagerte Testdateien** (vormals unter `miataru.xcodeproj/*.swift`, inzwischen eingebunden)  
3. **Third-Party-Testbestand** unter `miataru/Libraries/*` (nur inventarisiert, nicht im Detail katalogisiert)

Wichtige Projektbeobachtung:

- `miataruTests` ist als `PBXFileSystemSynchronizedRootGroup` eingebunden (`miataruTests`-Ordner wird automatisch als Source fuer das Unit-Testtarget genutzt).
- `miataruUITests` ist jetzt ebenfalls als synchronisierter Quellordner (`miataruUITests`) am UI-Testtarget angebunden.
- Testdateien direkt in `miataru/miataru.xcodeproj/` sind nicht mehr der aktive Ablageort fuer App-Tests.

## 2) Inventar auf einen Blick

- Aktiv eingebundene App-Testfaelle: **64** (Unit: 60, UI: 4)
- Vorhandene, nicht eingebundene App-Testfaelle: **0**
- Third-Party-Testfunktionen in `Libraries`: **172**

## 3) Aktiver Testkatalog (`miataruTests`)

| ID | Test-Case Name | Zweck | Inhalt (kurz) | Komponente | Typ | Daten/Mocks | Prioritaet |
|---|---|---|---|---|---|---|---|
| UT-MND-001 | Hysteresis: Enter mutual state at 60s threshold | Eintrittsgrenze pruefen | Visitor mit Alter 55s, Erwartung: <= 60s | MutualNavigationDetector / Zeitlogik | Unit | Feste Referenzzeit, MiataruVisitor | Hoch |
| UT-MND-002 | Hysteresis: Exit mutual state at 90s threshold | Austrittsgrenze pruefen | Visitor mit Alter 95s, Erwartung: > 90s | MutualNavigationDetector / Zeitlogik | Unit | Feste Referenzzeit, MiataruVisitor | Hoch |
| UT-MND-003 | Hysteresis: Stay in mutual state between 60s and 90s | Hysterese-Zwischenbereich pruefen | Visitor mit Alter 75s, Erwartung: >60 und <=90 | MutualNavigationDetector / Zeitlogik | Unit | Feste Referenzzeit, MiataruVisitor | Hoch |
| UT-MND-004 | Visitor timestamp parsing | Timestamp-Parsing validieren | Millisekunden-String -> Date, Abweichung < 1ms | MiataruVisitor | Unit | Deterministischer Timestamp | Mittel |
| UT-NRP-001 | No refresh in standard mode when target moved but remains on route | Kein unnoetiger Refresh | Standardmodus, Ziel bewegt, nicht off-route -> false | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | Hoch |
| UT-NRP-002 | Refresh in standard mode when target moved and is off route | Refresh bei Off-Route Ziel | Standardmodus + target off-route -> true | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | Hoch |
| UT-NRP-003 | Refresh in reverse mode when target moved significantly | Reverse-Modus Verhalten | Reverse-Modus + signifikante Bewegung -> true | NavigationRouteRefreshPolicy | Unit | CLLocationCoordinate2D | Hoch |
| UT-NRP-004 | No refresh when auto update is disabled | Feature-Flag pruefen | Auto-Update aus -> immer false | NavigationRouteRefreshPolicy | Unit | Bool-Flags + Koordinaten | Hoch |
| UT-NRP-005 | Refresh when no route exists | Initialfall ohne Route | hasRoute=false -> true | NavigationRouteRefreshPolicy | Unit | nil-Koordinaten | Hoch |
| UT-NRP-006 | No refresh when on route and target movement is below threshold | Schwellwert unten pruefen | Zielbewegung unter Schwellwert -> false | NavigationRouteRefreshPolicy | Unit | Kleine Koordinatendifferenz | Hoch |
| UT-NRP-007 | Refresh when user is off route regardless of target movement | User-Off-Route priorisieren | isUserOffRoute=true -> true | NavigationRouteRefreshPolicy | Unit | Identische Start/Ziel-Koordinaten | Hoch |
| UT-NRP-008 | No refresh if target did not move beyond threshold | Kein Refresh ohne relevante Zielbewegung | Sehr hoher Threshold, kleine Bewegung -> false | NavigationRouteRefreshPolicy | Unit | Threshold 1000m | Mittel |
| UT-NRP-009 | No refresh when target coordinates are missing and user is on route | Missing-Data Verhalten | currentDeviceCoordinate=nil, user on route -> false | NavigationRouteRefreshPolicy | Unit | nil + lastRouteCoordinate | Mittel |
| UT-NRP-010 | hasTargetMovedSignificantly returns false for missing coordinates | Helper-Robustheit | Missing current/last -> jeweils false | NavigationRouteRefreshPolicy | Unit | Nil-Parameter | Mittel |
| UT-RGC-001 | Ghost progresses with primary speed and timestamp (non-reversed: user primary) | Ghost-Fortschritt Standardmodus | user speed/timestamp als Primarquelle, progress in (0,1] | RouteGhostCalculator | Unit | FakeRoute (MKRoute Shim), feste Zeit | Hoch |
| UT-RGC-002 | Ghost uses expectedTravelTime fallback when speeds are below threshold | Fallback-Pfad pruefen | Geringe Geschwindigkeiten -> expectedTravelTime genutzt | RouteGhostCalculator | Unit | FakeRoute, Threshold-nahe Geschw. | Hoch |
| UT-RGC-003 | Ghost bases from device when reversed route | Richtungsabhaengige Quelle | isRouteReversed=true -> device als Basis | RouteGhostCalculator | Unit | FakeRoute, feste Zeit | Hoch |
| UT-RCS-001 | Set and get cached route by key | Grundfunktion Cache | set/get ueber Key liefert Route | RouteCacheStore | Unit | `RouteCacheStore.shared`, FakeRoute | Hoch |
| UT-RCS-002 | isValid returns true when both endpoints moved less than threshold and on-route | Validitaet im Normalfall | Kleine Endpoint-Bewegung + on-route -> true | RouteCacheStore | Unit | Threshold + offRouteThreshold | Hoch |
| UT-RCS-003 | isValid returns false when either endpoint moved beyond threshold | Invalidation bei grosser Bewegung | Endpoint weit bewegt -> false | RouteCacheStore | Unit | Bewegungsdelta > 100m | Hoch |
| UT-RCS-004 | isValid returns false when user is off route beyond offRouteThreshold | Off-Route Invalidation | User ~200m neben Route -> false | RouteCacheStore | Unit | offRouteThreshold=25 | Hoch |
| UT-RCS-005 | Keys are isolated by transportType | Key-Segmentierung Transport | Gleiche Device-ID, verschiedene transportType getrennt | RouteCacheStore | Unit | Zwei Routenvarianten | Hoch |
| UT-RCS-006 | Keys are isolated by isRouteReversed | Key-Segmentierung Richtung | Forward/Reverse getrennt abrufbar | RouteCacheStore | Unit | Zwei Richtungsvarianten | Hoch |
| UT-RCS-007 | clear(for:) removes only the specified device's entries | Selektives Loeschen | clear(Device A) entfernt A, behaelt B | RouteCacheStore | Unit | Zwei Device-IDs | Hoch |
| UT-RCS-008 | clear(for:) removes all variants (transport and direction) for a device | Vollstaendiges Device-Clear | Alle Varianten fuer ein Device verschwinden | RouteCacheStore | Unit | 4 Key-Varianten pro Device | Hoch |
| UT-RCS-009 | isValid returns false at the boundary when movement equals threshold | Boundary-Case Gleichheit | Bewegung == threshold -> false | RouteCacheStore | Unit | Dynamisch berechneter Threshold | Hoch |
| UT-RCS-010 | Default validity ignores off-route when offRouteThreshold is nil | Default-Verhalten bei nil Schwelle | Off-route ignoriert, wenn offRouteThreshold=nil | RouteCacheStore | Unit | Route + weit entfernter User | Mittel |
| UT-RCS-011 | Single-point route is never considered off-route in validity check | Degenerierte Route robust behandeln | Ein-Punkt-Route invalidiert nicht ueber Off-Route | RouteCacheStore | Unit | Single-point MKPolyline | Mittel |
| UT-RCS-012 | get returns nil for missing key or mismatched parameters | Negativpfad get() | Unknown device / falscher transportType / direction -> nil | RouteCacheStore | Unit | Variierende Key-Parameter | Mittel |
| UT-RCS-013 | Setting the same key twice overwrites the cached route | Overwrite-Semantik | Zweites set gleicher Key ersetzt Route | RouteCacheStore | Unit | Zwei verschiedene Routen | Mittel |
| UT-RCS-014 | isValid returns true with very large threshold despite large movement | Threshold-Einfluss pruefen | Sehr grosser Threshold -> trotz grosser Bewegung true | RouteCacheStore | Unit | Threshold=1_000_000 | Niedrig |
| UT-VHV-001 | Known device resolution from visitor history | KnownDevice-Aufloesung pruefen | KnownDevice anlegen, Visitor mit gleicher ID findet Name | VisitorHistory / KnownDeviceStore | Unit | Shared Store, cleanup per defer | Hoch |
| UT-VHV-002 | Unknown device resolution from visitor history | Unknown-Fall pruefen | Visitor mit unbekannter ID -> kein Treffer | VisitorHistory / KnownDeviceStore | Unit | Shared Store | Mittel |
| UT-VHV-003 | Device resolution after adding unknown device | Uebergang unknown->known | Erst nil, nach add() Treffer mit Name | VisitorHistory / KnownDeviceStore | Unit | Shared Store, cleanup per defer | Hoch |
| UT-VHV-004 | Visitor history sorting by timestamp | Sortierlogik pruefen | 3 Besucher nach TimeStampDate absteigend sortieren | VisitorHistory | Unit | Fixierte Zeitabstaende | Mittel |
| UT-VHV-005 | Shortened device ID format | Anzeigeformat pruefen | Lange ID wird zu `prefix...suffix` | VisitorHistory (UI-Helfer) | Unit | Statische String-ID | Niedrig |
| UT-GEN-001 | example | Platzhalter/Template | Leerer Beispieltest ohne Assertions | Grundgeruest | Unit | Keine | Niedrig |

## 4) Ehemals nicht eingebundene, jetzt aktive Testfaelle

Diese Testfaelle lagen zuvor unter `miataru.xcodeproj/*.swift` und sind jetzt in aktive Targets uebernommen (`miataruTests` bzw. `miataruUITests`).

| ID | Test-Case Name | Zweck | Inhalt (kurz) | Komponente | Typ | Aktiv im Testtarget |
|---|---|---|---|---|---|---|
| DT-MH-001 | relativeTimeString returns localized 'now' within threshold | relativeTime now-Schwelle | 2s alt -> lokalisierter now-String | MapHelpers | Unit | Ja |
| DT-MH-002 | relativeTimeString returns a non-empty string for past times | Relative Zeit fuer Vergangenheitswerte | 120s alt -> nicht leer / nicht Platzhalter | MapHelpers | Unit | Ja |
| DT-MH-003 | mapSpeedLabelText returns nil for values below default threshold | Geschwindigkeit unter Schwellwert | 2 m/s -> nil | MapHelpers | Unit | Ja |
| DT-MH-004 | mapSpeedLabelText returns formatted value above threshold | Geschwindigkeit ueber Schwellwert | 5 m/s -> Label mit km/h oder mph | MapHelpers | Unit | Ja |
| DT-MH-005 | timezoneOffsetString returns nil for same timezone | Zeitzonenoffset Gleichheit | Device-TZ = current TZ -> nil | MapHelpers | Unit | Ja |
| DT-MH-006 | timezoneOffsetString returns +2 for TZ two hours ahead | Positiver TZ-Offset | +2h gegenueber local -> "+2" | MapHelpers | Unit | Ja |
| DT-MH-007 | spanForZoomLevel produces reasonable deltas and round-trips with currentZoomLevelFromSpan | Zoom Roundtrip | spanForZoomLevel <-> currentZoomLevelFromSpan | MapHelpers | Unit | Ja |
| DT-MH-008 | relativeTimeString with future date returns 'now' | Future-Date Behandlung | Zukunftsdatum -> now-String | MapHelpers | Unit | Ja |
| DT-MH-009 | timezoneOffsetString returns negative offset for behind timezones | Negativer TZ-Offset | -3h gegenueber local -> "-3" | MapHelpers | Unit | Ja |
| DT-MH-010 | mapSpeedLabelText returns non-nil when min threshold is 0 and positive speed | Konfigurierbarer Schwellwert | minSpeedKmh=0 + positive speed -> Label | MapHelpers | Unit | Ja |
| DT-MHA-001 | mapSpeedLabelText returns nil for nil or zero/negative speeds | Guard-Pfade mapSpeedLabelText | nil/0/<0 -> nil | MapHelpers | Unit | Ja |
| DT-MHA-002 | relativeTimeString respects custom timeConsideredNow threshold | Parametrisierte now-Schwelle | 2s alt bei threshold=1 -> nicht now | MapHelpers | Unit | Ja |
| DT-MKP-001 | split(at:) splits a simple horizontal segment correctly | split Grundfall | Halbierung Segment, Laengenkonsistenz, progress ~0.5 | MKPolyline Extension | Unit | Ja |
| DT-MKP-002 | split(at:) at distance 0 yields start interpolation and zero done length | split Distanz 0 | done=0, ghost=start | MKPolyline Extension | Unit | Ja |
| DT-MKP-003 | split(at:) at total length yields end interpolation and zero todo length | split Distanz total | todo=0, ghost=end | MKPolyline Extension | Unit | Ja |
| DT-MKP-004 | split(at:) works across multiple segments | split Multi-Segment | Split in Segment 2, Progress-Pruefung | MKPolyline Extension | Unit | Ja |
| DT-MKP-005 | closestDistance(to:) finds zero for a point on the polyline | Distanz auf Linie | Punkt auf Linie -> Abstand ~0 | MKPolyline Extension | Unit | Ja |
| DT-MKP-006 | closestDistance(to:) returns perpendicular distance when projection falls within segment | Orthogonaler Abstand | Punkt neben Linie -> Abstand ~perpendicular | MKPolyline Extension | Unit | Ja |
| DT-MKP-007 | closestDistance(to:) works for single-point polyline | Distanz Single-Point | same->0, far->>0 | MKPolyline Extension | Unit | Ja |
| DT-MKP-008 | remainingDistance(toEndFrom:) decreases as point moves along the polyline | Monotonie Restdistanz | start > mid > end | MKPolyline Extension | Unit | Ja |
| DT-MKP-009 | remainingDistance(toEndFrom:) equals total when point is before start of polyline | Vor-Start Verhalten | Punkt vor Start -> Rest ~total | MKPolyline Extension | Unit | Ja |
| DT-MKP-010 | remainingDistance(toEndFrom:) works for single-point polyline | Restdistanz Single-Point | Single-Point -> direkte Distanz | MKPolyline Extension | Unit | Ja |
| DT-MKP-011 | split(at:) returns nil for degenerate (single-point) polyline | Degenerierter Split | Single-Point split -> nil | MKPolyline Extension | Unit | Ja |
| DT-UI-001 | testLaunchWithCompletedOnboardingShowsRootTabs | App-Start in stabilem Zustand | Launch mit abgeschlossenem Onboarding, Tab-Root sichtbar, kein Alert | App Bootstrap / Tab Root | UI (XCTest) | Ja |
| DT-UI-002 | testDevicesAddSheetCanOpenAndCancel | Device-Flow Basisvalidierung | Add-Device-Sheet oeffnen und via Cancel sauber schliessen | Device List / Add Device | UI (XCTest) | Ja |
| DT-UI-003 | testSettingsShowOnboardingActionIsReachable | Settings-Onboarding-Aktion absichern | Settings-Aktion ist erreichbar/tappbar und fuehrt nicht zu unerwarteten Alerts | Settings / Onboarding | UI (XCTest) | Ja |
| DT-UI-004 | testQRCodeTabShowsDeviceKeyAction | QR-Tab Kernaktion pruefen | QR-Tab oeffnen, Device-Key-Action vorhanden und tappbar | QR Screen / Device Key | UI (XCTest) | Ja |

## 5) Third-Party Testbestand (`miataru/Libraries`)

Diese Tests stammen aus eingebetteten Bibliotheken und sollten fuer App-Gap-Analysen separat betrachtet werden:

- `QRCode-main`: 155 Testfunktionen
- `SwiftImageReadWrite`: 12 Testfunktionen
- `NavigationOverlayKit-master`: 4 Testfunktionen
- `swift-qrcode-generator`: 1 Testfunktion

## 6) Katalog-Metadaten fuer den naechsten Gap-Schritt

Fuer die Lueckenanalyse sind in diesem Katalog bereits die wichtigsten Vergleichsdimensionen enthalten:

- Testtyp (`Unit`/`UI`)
- Aktivierungsstatus im Target (`ja/nein`)
- Komponentenzuordnung (Policy, Cache, Geometry, UI-Helfer)
- Randfallabdeckung (Boundary, nil, Single-Point, Schwellwerte)
- Abhaengigkeiten (`Shared` Stores, FakeRoute/MKRoute-Shim, Zeitsimulation)

Praktische Ausgangslage fuer den naechsten Schritt:

- Starke Abdeckung bei `RouteCacheStore`, `NavigationRouteRefreshPolicy`, `RouteGhostCalculator`.
- Teilweise nur Logik-nahe Tests ohne Integration (UI-Target ist aktiv und um deterministische Kernfluesse erweitert).
- Die vormals ausgelagerten Map-/UI-Tests sind aktiv eingebunden; naechster Schwerpunkt bleibt Integration/E2E fuer Navigation und Standortpipeline.

## 7) Gap-Matrix Referenz

Die priorisierte Lueckenanalyse und Bereichsbewertung liegt in:

- `documentation/test-gap-matrix.md`

Pflegehinweis:

- Bei jeder Testaenderung muessen **Test-Katalog** und **Gap-Matrix** gemeinsam aktualisiert werden.
