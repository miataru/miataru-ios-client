# Settings Search, Live Speed, and Navigation HUD

This chat implemented the requested Settings search, live own-device speed, and a mirrored Head-Up Display for both Miataru route directions. Subsequent feedback enlarged the navigation typography, added a brief overview followed by a forward-looking route focus, hid idle HUD controls, and made the own-position arrow follow a valid heading with palette-aware colors.

- Indexed individual Settings controls and prerequisites, and routed search results to the owning control or prerequisite.
- Displayed the iPhone's speed in km/h independently of map-marker speed settings, including zero and a dash for invalid or stale locations.
- Added a full-screen HUD with three palettes, horizontal mirroring, route/device vectors, instruction or summary, persistent palette/mirror preferences, and temporary idle-lock suppression.
- Added a forward-looking perspective after a brief full-route overview for user-to-device guidance, adaptive portrait/landscape layout, idle-hiding controls, and a projected own-position arrow.
- Localized the new text across all ten app languages and updated the Settings and navigation topic references plus both test inventories.

Validation: targeted Settings/HUD unit tests passed (10 tests in one suite; `20260925-204830-miataru-miataruTests.log`); the three Settings-search UI tests passed (`20260925-183310-miataru-miataruUITests.log`); localization completeness was checked across all ten locales. The live HUD appearance still requires a device route fixture for visual validation.
