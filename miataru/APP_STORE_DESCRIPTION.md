# App Store Copy Source

The copy-ready App Store Connect fields live in `documentation/app-store/`, with one file per supported language: [Danish](../documentation/app-store/da.md), [German](../documentation/app-store/de.md), [English](../documentation/app-store/en.md), [Spanish](../documentation/app-store/es.md), [Finnish](../documentation/app-store/fi.md), [French](../documentation/app-store/fr.md), [Italian](../documentation/app-store/it.md), [Japanese](../documentation/app-store/ja.md), [Dutch](../documentation/app-store/nl.md), and [Simplified Chinese](../documentation/app-store/zh-Hans.md). Each file contains the Promotional Text, Description, What's New, and Keywords fields in that order.

The development checkout metadata is version 3.6, build 18. Tested source commit `fd8a2c07b13c8526ff12c10dd3a5264d3ec0f572` passed the release lane with 413 tests (401 Unit + 12 UI; 0 skipped or failed), was archived, and App Store Connect accepted its upload on 2026-09-30 at 20:59:29 CEST. Build 17's earlier accepted upload at 19:34 CEST is historical. Apple processing, TestFlight availability, App Review, and store availability for Build 18 remain unconfirmed. The copy in this repository is a draft; its transfer to the live App Store Connect fields is unconfirmed. For each distribution build, refresh the `What's New` copy in all ten locales following the [release workflow](../documentation/release-workflow.md). The current 3.6 notes cover more reliable background location sharing after interruptions and the first unlock following a device restart, more efficient Smart tracking during frequent movement, retained updates during temporary connection problems, ordered delivery when several locations arrive together, and own-speed display using the newest valid location reading during navigation. The notes now also describe speed remaining visible during route recalculation when a valid value is available, and briefly carrying the last valid value while navigating from the iPhone to another device; it is hidden once that value is no longer current. Diagnostic and battery-monitoring internals are not part of the user-facing What's New copy. The navigation HUD and Settings search were introduced in 3.5.

## Screenshot Guidance

- Show the device list with available distance, battery, place, and visitor context.
- Show a device map with its marker and any available location details.
- Show either navigation direction with route guidance and ETA.
- Show the QR flow for adding a device or the current device.
- Show the iPad layout or a widget using selected devices.

Use current app captures and avoid implying that server-dependent details are always available.
