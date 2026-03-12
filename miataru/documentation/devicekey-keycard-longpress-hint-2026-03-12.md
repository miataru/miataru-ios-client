# DeviceKey Sheet: Keycard Long-Press Hint (2026-03-12)

## Ziel
Den versteckten Admin-Zugang im `Your Device Key`-Sheet sichtbarer machen, damit Nutzer wissen, wie sie die administrativen Optionen öffnen können.

## Umgesetzt

- Im DeviceKey-Sheet wurde ein zusätzlicher Hinweistext ergänzt:
  - `Long press the Keycard to unlock the administrative options.`
- Der Hinweis wird in beiden Zuständen angezeigt:
  - wenn noch kein DeviceKey gesetzt ist,
  - wenn bereits ein DeviceKey gesetzt ist.
- Neuer Lokalisierungs-Key:
  - `device_key_long_press_admin_hint`
- Übersetzungen ergänzt für:
  - `da,de,en,es,fi,fr,it,ja,nl,zh-Hans`

## Betroffene Dateien

- `miataru/miataru/views/iPhone/iPhone_DeviceKeySheetView.swift`
- `miataru/miataru/Assets/Localizable.xcstrings`

## Hinweise

- Funktionalität wurde rein auf UI-/Lokalisierungsebene ergänzt; keine Änderung an API- oder Persistenzlogik.
