# Settings Advanced Options Hitbox Fix - 2026-06-11

The root Settings `Advanced Options` entry was implemented as a plain SwiftUI `Button` with a custom `HStack` label. Although the row visually occupied the full Settings list width, taps in the trailing whitespace were not consistently handled because the label's tappable content stayed bound to the rendered icon/text/chevron area.

The row label now expands to the available width and declares a rectangular hit-test shape:

- `.frame(maxWidth: .infinity, alignment: .leading)` makes the label occupy the full list row width.
- `.contentShape(Rectangle())` makes that full rectangular area participate in hit testing.

The existing `ExtendedUITests.testSettingsAdvancedOptionsNavigationMovesAdvancedControlsOffRootScreen` regression now taps near the right edge of the `settings_advanced_options_link` accessibility element before verifying that Advanced Options opens. This keeps coverage tied to the original bug: whitespace in the row must behave like the visible label.
