# App Store Copy Source

The copy-ready App Store Connect fields live in `documentation/app-store/`, with one file per supported language: [Danish](../documentation/app-store/da.md), [German](../documentation/app-store/de.md), [English](../documentation/app-store/en.md), [Spanish](../documentation/app-store/es.md), [Finnish](../documentation/app-store/fi.md), [French](../documentation/app-store/fr.md), [Italian](../documentation/app-store/it.md), [Japanese](../documentation/app-store/ja.md), [Dutch](../documentation/app-store/nl.md), and [Simplified Chinese](../documentation/app-store/zh-Hans.md). Each file contains the Promotional Text, Description, What's New, and Keywords fields in that order.

The development checkout metadata is version 3.6, build 16. Source metadata does not establish App Store availability. For each distribution build, refresh the `What's New` copy in all ten locales following the [release workflow](../documentation/release-workflow.md). The current 3.6 notes cover more reliable background location sharing after interruptions and the first unlock following a device restart, more efficient Smart tracking during frequent movement, retained updates during temporary connection problems, ordered delivery when several locations arrive together, and the navigation-speed direction correction. Diagnostic and battery-monitoring internals are not part of the user-facing What's New copy. The navigation HUD and Settings search were introduced in 3.5. The copy in this repository is a draft for App Store Connect until the live fields are checked separately.

## Screenshot Guidance

- Show the device list with available distance, battery, place, and visitor context.
- Show a device map with its marker and any available location details.
- Show either navigation direction with route guidance and ETA.
- Show the QR flow for adding a device or the current device.
- Show the iPad layout or a widget using selected devices.

Use current app captures and avoid implying that server-dependent details are always available.
