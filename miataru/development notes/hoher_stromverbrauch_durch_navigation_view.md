# Hoher Stromverbrauch durch View-Rendering
_Exported on 2.9.2025 at 8:22:31 MESZ from Cursor (1.5.7)_

---

**User**

diese view verwendet sehr viel Battery/Strom - das iPhone wird immer sehr warm wenn ich eine Route zwischen zwei Geräten anzeige, Selbst wenn die Shimmering und Pulsing Animationen ausgeschaltet sind.

Kann das daran liegen dass zu oft neu gezeichnet wird?  Woran kann es liegen dass dieses View so aufwändig ist

---

**Cursor**

Ich schaue mir die betroffene View an und suche parallel nach Stellen, die häufige Re-Renders, Timer/DisplayLink-Updates, teure Routen-Neuberechnungen oder Map-Overlays auslösen. Danach nenne ich dir die konkreten Ursachen im Code und Quick-Fixes.

Ich habe die View durchgesehen. Mehrere Dinge treiben die Render-/GPU-Last hoch und verursachen Warmwerden/Akkuverbrauch – auch ohne Shimmer/Pulsing.

### Hauptursachen im Code
- Zeitgetriebene Re-Renders der gesamten Map-Inhalte
  - `now` wird periodisch aktualisiert und zwingt die Route/Overlays ständig neu zu zeichnen:
```246:250:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
.onReceive(timeUpdateTimer) { input in
    now = input
}
```
```644:647:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
private func restartTimeUpdateTimer() {
    let interval = max(1.0, Double(settings.mapUpdateInterval))
    timeUpdateTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
}
```
  - Das triggert die Fortschrittsberechnung und Polyline-Neuaufteilung ständig:
```165:183:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
if settings.showRouteProgress, let ts = deviceTimestamp {
    let elapsed = now.timeIntervalSince(ts)
    let expected = route.expectedTravelTime
    let progress = expected > 0 ? max(0, min(1, elapsed / expected)) : 0
    ...
    if let (todo, done, ghost) = route.polyline.split(at: splitDistance) {
        MapPolyline(done)...
        MapPolyline(todo)...
        MapCircle(center: ghost, radius: 50)...
```

- Sehr teure Text-“Outline”-Technik (25-fach Duplikate pro Label)
  - Pro Marker 24 versetzte Kopien + 1 Text → starke Overdraw/CPU/GPU-Kosten:
```87:101:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
    ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
        if x != 0 || y != 0 {
            Text(...).offset(x: CGFloat(x), y: CGFloat(y))
        }
    }
}
Text(...)
```
(gleiches Muster beim Ziel-Marker und beim “ghost”-Annotation-Label)

- Häufiges Re-Centering/Animieren der Kamera bei Standortupdates
  - Jede Positionsänderung kann animiert die Kamera setzen:
```426:434:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
if let user = userCoordinate, let dest = deviceCoordinate,
   (!hasSetInitialRegion || recenter || isAutoCenteringEnabled) {
    let region = regionThatFits(user: user, dest: dest)
    isProgrammaticCameraChange = true
    withAnimation { mapPosition = .region(region) }
    hasSetInitialRegion = true
}
```

- Kontinuierliche Kameraverfolgung erzeugt viele State-Updates
```265:281:/home/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
.onMapCameraChange(frequency: .continuous) { context in
    ...
    currentMapCamera = context.camera
    currentRegion = context.region
}
```

- Breite Beobachtung von Stores löst unnötige Rebuilds aus
  - `@ObservedObject`/`@StateObject` auf Singleton-Stores (z. B. `deviceStore`, `cache`) + Zugriff in den Annotations führt zu Re-Renders, auch wenn sich nur irrelevante Geräte ändern.

### Konkrete, schnelle Optimierungen
- Zeit-/Progress-Updates drosseln
  - `timeUpdateTimer` nur aktivieren, wenn `settings.showRouteProgress` wirklich an ist.
  - Intervall auf 5–10 s erhöhen oder progress nur bei sichtbarer Änderung (z. B. >50–100 m) neu zeichnen.
  - Polyline-Splitting nur bei relevanter Progress-Änderung ausführen (nicht jeden Tick).

- Outline-Labels drastisch vereinfachen
  - Die 5x5-Duplikate durch 4–8 Offsets (N, S, W, O [, NW, NO, SW, SO]) ersetzen oder nur einen dünnen Shadow nutzen.
  - Material/Blur für Zeit-Badges sparsam einsetzen (oder statisch halten).

- Re-Centering/Animationen nur bei signifikanter Bewegung
  - In `updateCoordinates` erst ab Schwellwert (z. B. >50–100 m) re-centern und Animation deaktivieren oder seltener animieren.
  - Nach erstem Fit `isAutoCenteringEnabled` standardmäßig deaktivieren oder nur per User-Action reaktivieren.

- Kamera-Änderungen weniger oft verarbeiten
  - `onMapCameraChange(frequency: .onEnd)` (statt `.continuous`), um State-Updates zu reduzieren.
  - Werte wie `currentRegion` nur dann setzen, wenn sich etwas merklich geändert hat.

- Store-Updates entkoppeln
  - Für Markerfarbe/-name des eigenen Geräts einmalig Werte zwischenspeichern und nicht das gesamte `deviceStore.devices` reaktiv an die Annotations binden.
  - `cache.$locations` gezielter filtern (nur das Zielgerät) bevor `updateCoordinates()` aufgerufen wird.

- Animationen sparsam
  - `withAnimation` nur nutzen, wenn sich Werte deutlich ändern; sonst ohne Animation setzen.
  - Für Map-Anpassungen optional `transaction { $0.disablesAnimations = true }` an passenden Stellen.

Wenn du willst, kann ich die obigen Änderungen zielgerichtet in der Datei umsetzen (beginnend mit: Timer drosseln/bedingen, Outline-Text reduzieren, `.continuous` → `.onEnd`, Re-Centering an Schwellwert koppeln).

Status: Ich habe die View analysiert und Engpässe mit Code-Stellen aufgezeigt. Ich kann direkt die wichtigsten Drosselungen implementieren.

```swift
.onReceive(timeUpdateTimer) { input in
    now = input
}
```

```swift
private func restartTimeUpdateTimer() {
    let interval = max(1.0, Double(settings.mapUpdateInterval))
    timeUpdateTimer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()
}
```

```swift
if settings.showRouteProgress, let ts = deviceTimestamp {
    let elapsed = now.timeIntervalSince(ts)
    let expected = route.expectedTravelTime
    let progress = expected > 0 ? max(0, min(1, elapsed / expected)) : 0
    ...
    if let (todo, done, ghost) = route.polyline.split(at: splitDistance) {
        MapPolyline(done)...
        MapPolyline(todo)...
        MapCircle(center: ghost, radius: 50)...
```

```swift
ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
    ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
        if x != 0 || y != 0 {
            Text(...).offset(x: CGFloat(x), y: CGFloat(y))
        }
    }
}
Text(...)
```

```swift
if let user = userCoordinate, let dest = deviceCoordinate,
   (!hasSetInitialRegion || recenter || isAutoCenteringEnabled) {
    let region = regionThatFits(user: user, dest: dest)
    isProgrammaticCameraChange = true
    withAnimation { mapPosition = .region(region) }
    hasSetInitialRegion = true
}
```

```swift
.onMapCameraChange(frequency: .continuous) { context in
    ...
    currentMapCamera = context.camera
    currentRegion = context.region
}
```

