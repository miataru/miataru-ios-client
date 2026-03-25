# Unknown Visitor / Allowed Device List Flow

## Kontext

Auf dem iPad wurde bei Unknown-Visitor-Benachrichtigungen zwar korrekt signalisiert, dass ein unbekanntes Geraet die Position angefragt hat, die betroffenen Geraete erschienen aber nicht konsistent in der Device-Liste. Gleichzeitig war der Add/Edit-Flow fuer unbekannte oder neue Geraete unnoetig umstaendlich, wenn die Allowed Device List noch nicht aktiviert war.

## Ziel

- Unknown Visitors sollen in der Device-Liste auf iPhone und iPad sichtbar sein, auch wenn die Allowed Device List noch deaktiviert ist.
- Die Primäraktion fuer Unknown Visitors soll kontextabhaengig benannt sein:
  - mit aktiver Allowed Device List: `Hinzufuegen und erlauben`
  - ohne aktive Allowed Device List: `Hinzufuegen`
- Add- und Edit-Dialoge sollen die Allowed Device List direkt vor Ort aktivieren koennen, damit der Nutzer die Zugriffskontrolle ohne Umweg ueber die Einstellungen einschalten und danach sofort konfigurieren kann.

## Umsetzung

### Device-Listen

Aktualisiert in:

- `miataru/miataru/views/iPhone/iPhone_DevicesView.swift`
- `miataru/miataru/views/iPad/iPad_DevicesView.swift`

Anpassungen:

- Die Section `unknown_visitors_section_title` ist nicht mehr an `settings.allowedDeviceListEnabled` gekoppelt.
- `UnknownVisitorRow` akzeptiert jetzt einen konfigurierbaren `addActionTitleKey`.
- Die Add-Aktion verwendet jetzt dynamische Labels:
  - `unknown_visitor_add_and_allow`, wenn die Allowed Device List aktiv ist
  - `add`, wenn die Allowed Device List deaktiviert ist

### Add-Dialog

Aktualisiert in:

- `miataru/miataru/views/iPhone/Devices Views/iPhone_AddDeviceView.swift`

Anpassungen:

- Wenn die Allowed Device List aktiv ist, bleibt der bestehende ACL-Abschnitt unveraendert sichtbar.
- Wenn sie deaktiviert ist, erscheint stattdessen direkt im Formular ein Aktivierungsblock mit:
  - `allowed_device_list_enable_button`
  - Ladezustand waehrend der Aktivierung
  - Inline-Fehleranzeige
  - `allowed_device_list_disabled_explanation`
- Nach erfolgreicher Aktivierung wird der Security-Status fuer das aktuell eingegebene Device direkt neu geladen.
- Der Speichern-Button ist waehrend einer laufenden Aktivierung deaktiviert.

### Edit-Dialog

Aktualisiert in:

- `miataru/miataru/views/iPhone/Devices Views/iPhone_EditDeviceView.swift`

Anpassungen:

- Wenn die Allowed Device List deaktiviert ist, erscheint nun auch im Edit-Dialog ein Aktivierungsblock mit demselben Verhalten wie im Add-Dialog.
- Nach erfolgreicher Aktivierung wechselt der Dialog ohne Kontextverlust in den normalen ACL-Konfigurationsmodus fuer fremde Geraete.
- Der Close/Save-Button ist waehrend einer laufenden Aktivierung ebenfalls deaktiviert.

## Verhalten nach der Aenderung

- Unknown-Visitor-Eintraege bleiben sichtbar, unabhaengig davon, ob die Allowed Device List bereits eingeschaltet wurde.
- Nutzer koennen ein unbekanntes Geraet zuerst einfach hinzufuegen und spaeter die Zugriffskontrolle aktivieren.
- Alternativ koennen sie die Zugriffskontrolle direkt aus dem Add/Edit-Dialog einschalten und anschliessend die ACL-Einstellungen fuer das Geraet sofort konfigurieren.

## Verifikation

- Xcode-Projekt erfolgreich gebaut.
- Geprueft, dass die Unknown-Visitor-Aktion auf iPhone und iPad je nach Feature-Status unterschiedlich beschriftet ist.
- Geprueft, dass Add- und Edit-Dialog den Aktivierungszustand der Allowed Device List live reflektieren.
