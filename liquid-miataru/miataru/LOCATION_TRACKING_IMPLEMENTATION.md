# Miataru iOS App - Kontinuierliches Location-Tracking

## Übersicht

Diese Implementierung ermöglicht es der Miataru iOS App, kontinuierlich die aktuelle Position des Geräts sowohl im Vorder- als auch im Hintergrund zu verfolgen und an den Miataru-Server zu senden.

## Implementierte Komponenten

### 1. LocationManager.swift
**Hauptkomponente für Location-Tracking**

- **Funktionen:**
  - Kontinuierliche Location-Updates im Vorder- und Hintergrund
  - Automatische Server-Kommunikation über MiataruAPIClient
  - Integration mit SettingsManager für Konfiguration
  - Status-Tracking und Fehlerbehandlung

- **Wichtige Features:**
  - `allowsBackgroundLocationUpdates = true`
  - `pausesLocationUpdatesAutomatically = false`
  - `showsBackgroundLocationIndicator = true`
  - Automatische Berechtigungsanfrage für "Always" Location-Zugriff

### 2. BackgroundLocationManager.swift
**Erweiterte Background-Funktionalität**

- **Funktionen:**
  - Background Tasks für zuverlässiges Background-Tracking
  - Push-Benachrichtigungen für Status-Updates
  - App-Lifecycle-Management
  - Erweiterte Background-Task-Scheduling

- **Background Task Identifiers:**
  - `com.miataru.ios.background-location`
  - `com.miataru.ios.background-server-update`

### 3. LocationStatusView.swift
**UI-Komponente für Status-Anzeige**

- **Features:**
  - Echtzeit-Status des Location-Trackings
  - Aktuelle Position und Genauigkeit
  - Server-Update-Status
  - Berechtigungs-Status
  - Toggle für Tracking-Aktivierung

### 4. Info.plist Konfiguration
**Notwendige Berechtigungen und Background-Modes**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
    <string>background-processing</string>
</array>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Miataru benötigt Zugriff auf Ihren Standort, um Ihre Position kontinuierlich an den Miataru-Server zu senden. Dies funktioniert sowohl im Vorder- als auch im Hintergrund.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Miataru benötigt Zugriff auf Ihren Standort, um Ihre Position an den Miataru-Server zu senden.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Miataru benötigt Zugriff auf Ihren Standort im Hintergrund, um Ihre Position kontinuierlich zu verfolgen und an den Miataru-Server zu senden.</string>
```

## Konfiguration

### SettingsManager Integration
Die Location-Tracking-Funktionalität ist vollständig in den bestehenden SettingsManager integriert:

- `trackAndReportLocation`: Aktiviert/Deaktiviert Location-Tracking
- `saveLocationHistoryOnServer`: Aktiviert/Deaktiviert Server-Historie
- `locationDataRetentionTime`: Speicherzeit für Location-Daten
- `miataruServerURL`: Server-URL für Location-Updates

### Automatische Aktivierung
- Location-Tracking startet automatisch, wenn `trackAndReportLocation = true`
- Background-Tasks werden automatisch geplant, wenn die App in den Hintergrund wechselt
- Server-Updates erfolgen alle 30 Sekunden bei neuen Location-Daten

## Verwendung

### 1. Location-Tracking aktivieren
```swift
// In Settings oder programmatisch
SettingsManager.shared.trackAndReportLocation = true
```

### 2. Status überwachen
```swift
// LocationManager Status beobachten
@ObservedObject private var locationManager = LocationManager.shared

// Status prüfen
if locationManager.isTracking {
    print("Location-Tracking ist aktiv")
}
```

### 3. Manuelle Kontrolle
```swift
// Location-Tracking manuell starten/stoppen
LocationManager.shared.startTracking()
LocationManager.shared.stopTracking()

// Background-Tracking
BackgroundLocationManager.shared.startBackgroundTracking()
BackgroundLocationManager.shared.stopBackgroundTracking()
```

## Technische Details

### Location-Update-Intervall
- **GPS-Updates:** Kontinuierlich bei Bewegung (10m Filter)
- **Server-Updates:** Alle 30 Sekunden oder bei neuen Location-Daten
- **Background-Updates:** Alle 30-60 Sekunden je nach System-Ressourcen

### Genauigkeit
- **Desired Accuracy:** `kCLLocationAccuracyBest`
- **Distance Filter:** 10 Meter
- **Background Indicator:** Aktiviert für Benutzer-Feedback

### Fehlerbehandlung
- Automatische Wiederholung bei Netzwerkfehlern
- Status-Tracking für UI-Feedback
- Logging für Debugging

## Berechtigungen

### Erforderliche Berechtigungen
1. **Location Always and When In Use** - Für kontinuierliches Tracking
2. **Background App Refresh** - Für Background-Tasks
3. **Notifications** - Für Status-Benachrichtigungen (optional)

### Berechtigungsanfrage
```swift
// Automatisch beim App-Start
LocationManager.shared.requestLocationPermission()
```

## Background-Tracking

### Funktionsweise
1. **App im Vordergrund:** Normales Location-Tracking mit CLLocationManager
2. **App im Hintergrund:** 
   - Background Tasks für Location-Updates
   - UIBackgroundTask für erweiterte Ausführungszeit
   - Push-Benachrichtigungen für Status-Updates

### System-Limitationen
- iOS begrenzt Background-Ausführungszeit
- Background Tasks werden vom System priorisiert
- Location-Updates sind zuverlässiger als andere Background-Tasks

## Debugging

### Logging
Alle wichtigen Events werden geloggt:
```
Location-Tracking gestartet
Neue Location erhalten: 52.5200, 13.4050
Location erfolgreich an Server gesendet
Background Tasks registriert
```

### Status-Überwachung
Die `LocationStatusView` zeigt:
- Aktuelle Position
- GPS-Genauigkeit
- Letzte Update-Zeiten
- Server-Status
- Berechtigungs-Status

## Best Practices

### Batterie-Optimierung
- Location-Updates nur bei Bedarf
- Automatische Pausierung bei Inaktivität
- Effiziente Server-Kommunikation

### Datenschutz
- Klare Berechtigungsanfragen
- Transparente Datennutzung
- Benutzer-Kontrolle über Tracking

### Zuverlässigkeit
- Automatische Wiederholung bei Fehlern
- Status-Tracking für Debugging
- Graceful Degradation bei Problemen

## Troubleshooting

### Häufige Probleme

1. **Location-Tracking funktioniert nicht im Hintergrund**
   - Prüfen Sie "Always" Location-Berechtigung
   - Stellen Sie sicher, dass Background App Refresh aktiviert ist
   - Prüfen Sie die Info.plist Konfiguration

2. **Server-Updates schlagen fehl**
   - Prüfen Sie die Server-URL in den Einstellungen
   - Stellen Sie sicher, dass eine Internetverbindung besteht
   - Prüfen Sie die Server-Logs

3. **Batterieverbrauch ist hoch**
   - Reduzieren Sie das Update-Intervall
   - Prüfen Sie andere Apps, die Location verwenden
   - Stellen Sie sicher, dass keine doppelten Location-Manager laufen

### Debug-Schritte
1. Prüfen Sie die Console-Logs
2. Verwenden Sie die LocationStatusView für Status-Informationen
3. Testen Sie mit verschiedenen Network-Bedingungen
4. Prüfen Sie die Background-Task-Registrierung

## Fazit

Diese Implementierung bietet eine robuste, benutzerfreundliche Lösung für kontinuierliches Location-Tracking in der Miataru iOS App. Sie berücksichtigt iOS-System-Limitationen, Datenschutz-Anforderungen und Batterie-Optimierung, während sie gleichzeitig eine zuverlässige Server-Kommunikation gewährleistet. 