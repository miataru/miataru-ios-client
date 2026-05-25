# Unknown Visitor Add Device Lock

## Kontext

Unknown Visitors konnten bereits aus mehreren Stellen als neues Geraet uebernommen werden: aus der Unknown-Visitor-Liste im Devices-Tab, aus dem Unknown-Device-Action-Sheet, aus Benachrichtigungen und aus der Visitor History im QR-Tab bzw. der standalone Visitor History. Der Add-Dialog verwendete dafuer denselben vorausgefuellten `iPhone_AddDeviceView` wie normale Deep Links.

Dadurch blieb die Device ID im Unknown-Visitor-Fall editierbar und der QR-Code-Scan wurde angeboten, obwohl die App gerade ein konkretes unbekanntes Geraet uebernehmen soll. Das war verwirrend, weil Nutzer die ID in diesem Kontext nicht neu waehlen muessen.

## Ziel

- Unknown-Visitor-Add-Einstiege sollen dieselbe feste Device ID aus dem Besucher-Kontext verwenden.
- In diesem Modus soll kein QR-Code-Scan angeboten werden.
- Die Device ID soll sichtbar bleiben, aber nicht editierbar sein.
- Normales Hinzufuegen ueber den Plus-Button und unbekannte `miataru://` Deep Links sollen weiterhin QR-Scan und Device-ID-Bearbeitung erlauben.

## Umsetzung

Aktualisiert in:

- `miataru/miataru/AppNavigationCoordinator.swift`
- `miataru/miataru/miataruApp.swift`
- `miataru/miataru/views/iPhone/Devices Views/iPhone_AddDeviceView.swift`
- `miataru/miataru/views/iPhone/iPhone_DevicesView.swift`
- `miataru/miataru/views/iPad/iPad_DevicesView.swift`
- `miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift`
- `miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift`

Anpassungen:

- `AddDeviceRequest` traegt jetzt eine Quelle: `.general` oder `.unknownVisitor`.
- `AppNavigationCoordinator.openAddDevice` bleibt standardmaessig `.general`, sodass Deep Links und normale Add-Flows editierbar bleiben.
- Unknown-Visitor-Einstiege setzen `.unknownVisitor`, bevor der zentrale Add-Dialog geoeffnet wird.
- `iPhone_AddDeviceView` akzeptiert `allowsDeviceIDEditing`, standardmaessig `true`.
- Wenn `allowsDeviceIDEditing == false`, zeigt der Device-ID-Abschnitt nur den monospaced, textselektierbaren Device-ID-Wert. QR-Scan-Button und Textfeld werden nicht gerendert.

## Verhalten nach der Aenderung

- Unknown Visitor im Devices-Tab hinzufuegen: Device ID ist fest, QR-Scan ist ausgeblendet.
- Unknown Visitor aus dem Action-Sheet oder einer Benachrichtigung hinzufuegen: gleicher gesperrter Dialog.
- Unknown Visitor aus der QR-tab Visitor History oder standalone Visitor History hinzufuegen: gleicher gesperrter Dialog.
- Plus-Button in der Device-Liste: unveraenderter Add-Dialog mit QR-Scan und editierbarer Device ID.
- Unbekannter `miataru://<DeviceID>` Deep Link: weiterhin vorausgefuellt, aber editierbar.

## Verifikation

- `xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' -only-testing:miataruTests/DeviceLinkResolverTests`
- `xcodebuild test -project miataru/miataru.xcodeproj -scheme miataru -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`
- `git diff --check`

Der vollstaendige Scheme-Lauf war erfolgreich: 141 Unit-Tests und 5 UI-Tests.
