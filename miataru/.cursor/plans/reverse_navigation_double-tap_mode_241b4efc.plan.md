---
name: Reverse Navigation Double-Tap Mode
overview: "Implementiert Navigations-Verhalten für Reverse-Navigation-Modus: User-Location-Annotation mit Blickrichtungspfeil, Kartenrotation während Navigation, Double-Tap Aktivierung und initiale Fit-Animation mit verzögertem Zoom, basierend auf der ToiletFinder-Spezifikation."
todos:
  - id: location-manager-heading
    content: "LocationManager: Heading-Pipeline hinzufügen (Course + Compass mischen, glätten, userHeading/isHeadingValid publizieren)"
    status: completed
  - id: user-heading-annotation
    content: UserHeadingAnnotationView Komponente erstellen mit HeadingArrowShape und korrekter Rotation
    status: completed
  - id: user-marker-integration
    content: "iPhone_DeviceNavigationView: User-Marker mit UserHeadingAnnotationView erweitern, Map-Heading tracken"
    status: completed
  - id: double-tap-reverse
    content: Double-Tap Handler für Reverse-Modus erweitern (Navigation-Modus aktivieren)
    status: completed
  - id: follow-camera-user-heading
    content: Follow-Camera mit User-Heading erweitern, Rotation nur bei Navigation-Modus
    status: completed
  - id: initial-fit-animation
    content: Initiale Fit-Animation + verzögerter Zoom (2.5s) bei Navigation-Start implementieren
    status: completed
isProject: false
---

# Plan: Reverse Navigation Double-Tap Mode

## Zielbild

Wenn ein User im Reverse-Navigations-Modus (`isRouteReversed == true`) per Double-Tap die Karte auf Navigation schaltet, sollen folgende Änderungen aktiviert werden:

- **User-Location-Annotation mit Blickrichtungspfeil**: Custom-Annotation mit Richtungspfeil, der die aktuelle Blickrichtung anzeigt und korrekt rotiert (berücksichtigt Kartenrotation)
- **Kartenrotation**: Die Karte rotiert um die Blickrichtung des Users während der Navigation
- **Follow-Camera**: Kamera folgt dem User mit weichen Animationen
- **Initiale Sequenz**: Route wird gefittet, dann nach 2.5s in den Navigation-Look gezoomt

## Aktuelle Situation

- `handleMapDoubleTap()` funktioniert nur wenn `!isRouteReversed` ist (Zeile 1115)
- `LocationManager` hat keine Heading-Logik (nur Course aus `currentLocation?.course`)
- `userMarkerContent` verwendet `MiataruMapMarker` ohne Heading-Pfeil
- `updateFollowCamera()` verwendet `currentDeviceHeading()` (Device-Heading statt User-Heading)
- `onMapCameraChange` trackt bereits `currentMapCamera?.heading`, wird aber nicht für Pfeil-Rotation verwendet

## Implementierungsschritte

### 1. LocationManager: Heading-Pipeline hinzufügen

**Datei**: `[miataru/LocationManagers/LocationManager.swift](miataru/LocationManagers/LocationManager.swift)`

- `CLLocationManager` für Heading-Updates konfigurieren (`startUpdatingHeading()`)
- `@Published var userHeading: Double?` hinzufügen
- `@Published private(set) var isHeadingValid: Bool = false` hinzufügen
- Heading-Logik implementieren:
  - Course (bei Bewegung) mit Compass-Heading (bei Stillstand) mischen
  - Exponential-Smoothing mit Wrap-Around bei 0/360
  - `isHeadingValid` basierend auf Heading-Qualität setzen
- `CLLocationManagerDelegate` erweitern: `locationManager(_:didUpdateHeading:)`

**Referenz**: ToiletFinder `LocationManager.swift` Zeilen 18-127

### 2. UserHeadingAnnotationView Komponente erstellen

**Neue Datei**: `miataru/views/Common/Map/UserHeadingAnnotationView.swift`

- Custom-View mit Layer-Aufbau:
  - Außenring: `Circle().fill(Color.accentColor.opacity(0.16)).frame(width: 36, height: 36)`
  - Kontur: `Circle().stroke(Color.accentColor.opacity(0.5), lineWidth: 2).frame(width: 28, height: 28)`
  - Innerer Kern: `Circle().fill(Color.white.opacity(0.8)).frame(width: 22, height: 22)` mit Drop-Shadow
  - Heading-Pfeil: `HeadingArrowShape()` nur sichtbar wenn `isHeadingValid`
  - Punktkern: `Circle().fill(Color.accentColor).frame(width: 10, height: 10)`
- `HeadingArrowShape`: Dreieck mit Spitze oben (`tipY = -11`, `baseY = 2`, `halfBase = 4.5`)
- Pfeil-Rotation: `rotationEffect(.degrees((heading ?? 0) - mapHeading))` für korrekte Bildschirmrichtung

**Referenz**: ToiletFinder `UserHeadingAnnotationView.swift` Zeilen 10-50

### 3. iPhone_DeviceNavigationView: User-Marker mit Heading erweitern

**Datei**: `[miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)`

- `@State private var currentMapHeadingDegrees: Double = 0` hinzufügen
- In `onMapCameraChange` (Zeile 407): `currentMapHeadingDegrees = context.camera.heading` speichern
- `userMarkerContent` (Zeile 493) anpassen:
  - Wenn `isFollowDeviceHeadingMode` oder Navigation-Modus aktiv: `UserHeadingAnnotationView` verwenden
  - Sonst: bestehenden `MiataruMapMarker` beibehalten
  - `UserHeadingAnnotationView` mit `locationManager.userHeading`, `locationManager.isHeadingValid`, `currentMapHeadingDegrees` befüllen

### 4. Double-Tap Handler für Reverse-Modus erweitern

**Datei**: `[miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)`

- `handleMapDoubleTap()` (Zeile 1114) erweitern:
  - Guard entfernen oder erweitern, um auch bei `isRouteReversed == true` zu funktionieren
  - Wenn `isRouteReversed == true`: Navigation-Modus aktivieren (ähnlich `enableFollowDeviceHeadingMode()`)
  - Neuen State `@State private var isNavigationMode: Bool = false` hinzufügen
  - `enableNavigationMode()` und `disableNavigationMode()` Funktionen erstellen

### 5. Follow-Camera mit User-Heading erweitern

**Datei**: `[miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)`

- `currentDeviceHeading()` (Zeile 1172) umbenennen/erweitern zu `currentUserHeading()`:
  - Wenn Navigation-Modus aktiv: `locationManager.userHeading` verwenden
  - Fallback auf Course, dann Map-Heading
- `updateFollowCamera()` (Zeile 1145) anpassen:
  - Rotation nur aktiv wenn Navigation-Modus aktiv UND `isRouteReversed == true`
  - `MapCamera(heading:)` mit User-Heading verwenden (iOS 17+)
  - Animation: `.easeInOut(duration: 0.35)` wie in ToiletFinder

### 6. Initiale Fit-Animation + verzögerter Zoom

**Datei**: `[miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)`

- `@State private var shouldPerformInitialNavigationZoom: Bool = false` hinzufügen
- Bei Navigation-Modus-Start:
  - Route + User + Ziel in Region fitten (`regionThatFitsRoute()` oder erweitert)
  - Mit `.easeInOut(duration: 0.35)` animieren
  - `shouldPerformInitialNavigationZoom = true` setzen
  - Task mit 2.5s Delay starten
  - Nach Delay: `performInitialNavigationZoom()` aufrufen (Zoom auf User mit Navigation-Distance)
- `updateFollowCamera()`: Updates während `shouldPerformInitialNavigationZoom` überspringen

**Referenz**: ToiletFinder `RootView.swift` Zeilen 988-1047

### 7. Navigation-Overlay für Reverse-Modus (optional)

**Datei**: `[miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)`

- `navigationOverlayContent` (Zeile 448) erweitern:
  - Overlay auch anzeigen wenn `isRouteReversed == true` UND Navigation-Modus aktiv
  - Route-Richtung entsprechend anpassen

## Technische Details

### Heading-Glättung

```swift
private func smoothHeading(_ newHeading: Double) -> Double {
    let normalized = normalizedHeading(newHeading)
    guard let last = lastSmoothedHeading else {
        lastSmoothedHeading = normalized
        return normalized
    }
    let delta = normalized - last
    let wrappedDelta: Double = {
        if delta > 180 { return delta - 360 }
        if delta < -180 { return delta + 360 }
        return delta
    }()
    let smoothed = normalizedHeading(last + wrappedDelta * headingSmoothingAlpha)
    lastSmoothedHeading = smoothed
    return smoothed
}
```

### Map-Heading Tracking

- `onMapCameraChange` liefert `context.camera.heading` kontinuierlich
- In `@State` speichern und für Pfeil-Rotation verwenden

### Animation-Timing

- Kamera-Updates: `.easeInOut(duration: 0.35)`
- Initial Fit: `.easeInOut(duration: 0.35)`
- Verzögerung vor Zoom: 2.5 Sekunden

## Risiken/Abweichungen

- **iOS-Version**: `MapCamera(heading:)` nur iOS 17+; Fallback auf `region` für ältere Versionen
- **Heading-Verfügbarkeit**: Compass-Heading erfordert Gerätebewegung; bei fehlendem Heading Fallback auf Course
- **Map-Update-Loop**: `isProgrammaticCameraChange` verhindert unerwünschte Re-Searches; Logik beibehalten

## Test-Validierung

- Check: Pfeil zeigt stets "screen-forward" bei Kartendrehung
- Check: Double-Tap aktiviert Navigation-Modus auch bei `isRouteReversed == true`
- Check: Karte rotiert mit User-Heading während Navigation
- Check: Initiale Sequenz: Fit → 2.5s → Zoom, danach flüssige Folgebewegung
- Check: Heading-Pfeil verschwindet wenn `isHeadingValid == false`

