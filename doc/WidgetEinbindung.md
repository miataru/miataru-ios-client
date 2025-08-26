# MiataruWidget in Xcode einbinden

1. Öffne die `miataru.xcodeproj` in Xcode.
2. Wähle **File ▸ New ▸ Target...** und erstelle eine **Widget Extension**.
3. Vergib den Namen **MiataruWidget**, wähle *SwiftUI* als Interface und deaktiviere "Include Configuration Intent".
4. Entferne die automatisch erzeugten Dateien und füge stattdessen die vorhandenen Dateien aus `miataru/MiataruWidget` hinzu:
   - `MiataruWidget.swift`
   - `DeviceSelectionIntent.swift`
   - `Info.plist`
   Stelle sicher, dass im *File Inspector* bei allen Dateien die Zielzugehörigkeit (**Target Membership**) auf **MiataruWidget** gesetzt ist.
5. Öffne die *Build Settings* des Targets und setze **Info.plist File** auf `miataru/MiataruWidget/Info.plist`.
6. Vergib eine eindeutige **Bundle Identifier**, z. B. `com.example.miataru.widget`.
7. Aktiviere bei Bedarf Capabilities (z. B. *App Groups*) analog zum Haupt‑App‑Target, damit der Widget auf den Gerätespeicher zugreifen kann.
8. Baue und starte das Projekt. Der Widget erscheint anschließend in der Widget-Galerie und erlaubt die Auswahl eines bekannten Geräts.
