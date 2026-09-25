# Navigation Build Warning Cleanup

The current chat also reported two compiler warnings in the tracking-pause sheet and two Swift 6 compatibility warnings in the bundled QRCode library. This commit keeps those small build fixes separate from the navigation feature commit.

- Imported Combine directly where `Timer.publish(...).autoconnect()` declares a stored property.
- Passed the `CodingKeys` metatype with `.self` in QRCode logo-template encode/decode containers.
- Added the warning cleanup to the version 3.5 changelog.

Validation: the Miataru test build in `20260925-201455-miataru-miataruTests.log` compiled `QRCode+LogoTemplate.swift` without `warning:` or `error:` diagnostics; 10 targeted HUD tests later passed in `20260925-204830-miataru-miataruTests.log`. `git diff --check` passed.
