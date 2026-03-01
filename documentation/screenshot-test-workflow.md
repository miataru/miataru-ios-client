# Screenshot Test Workflow

## Goal

Deterministic, explicitly triggered screenshot captures for all supported languages on exactly two target devices:

- `iPhone 16 Pro Max`
- `iPad Pro 13-inch (M5)`

The suite runs serially (maximum 1 parallel simulator instance) and is separated from regular test runs.

## Configuration

- Shared scheme: `miataru-Screenshots`
- Test plan: `Screenshots.xctestplan`
- Test target: `miataruScreenshotUITests`
- Trigger script: `miataru/scripts/test-screenshots.sh`

## Trigger

Run the screenshot suite explicitly:

```bash
cd miataru
./scripts/test-screenshots.sh
```

Show available screenshot tests:

```bash
cd miataru
./scripts/test-screenshots.sh --list
```

Run only one (or multiple) screenshot tests:

```bash
cd miataru
./scripts/test-screenshots.sh --test root-qr
./scripts/test-screenshots.sh --test test_03_root_settings
./scripts/test-screenshots.sh --test root-qr --test settings-navigation
```

Run a single screenshot test on a single device in a single language:

```bash
cd miataru
./scripts/test-screenshots.sh --test root-qr --device "iPhone 16 Pro Max" --languages en
```

Equivalent selector with device slug:

```bash
cd miataru
./scripts/test-screenshots.sh --test root-qr --device iphone-16-pro-max --languages en
```

Run serial functional/UI suite (Unit + Functional UI):

```bash
cd miataru
./scripts/test-functional-ui-serial.sh
```

## Languages and Regions

Default run set:

- `en`/`US`
- `de`/`DE`
- `ja`/`JP`
- `fr`/`FR`
- `es`/`ES`
- `zh-Hans`/`CN`
- `nl`/`NL`
- `da`/`DK`
- `it`/`IT`
- `fi`/`FI`

Limit language scope optionally:

```bash
cd miataru
./scripts/test-screenshots.sh --languages en,de --test root-qr
```

Device scope can also be limited via parameter (repeatable):

```bash
cd miataru
./scripts/test-screenshots.sh --device "iPhone 16 Pro Max" --device "iPad Pro 13-inch (M5)" --languages en
```

Optionally override version/build manually:

```bash
cd miataru
APP_VERSION_OVERRIDE="3.1.2" APP_BUILD_OVERRIDE="6" ./scripts/test-screenshots.sh --test root-qr
```

## Simulator Rules

The script checks whether an exactly named simulator instance exists for each target device. If not, it creates one automatically using the matching device type and the newest available iOS runtime.

Before each capture run, the script enforces simulator language and locale on the target UDID:

- `AppleLanguages` is written via `simctl spawn ... defaults write NSGlobalDomain AppleLanguages ...`
- `AppleLocale` is written via `simctl spawn ... defaults write NSGlobalDomain AppleLocale ...`

In addition, the UI test launch passes explicit app arguments:

- `-AppleLanguages (...)`
- `-AppleLocale ...`

This ensures screenshot language follows `--languages` even when the simulator itself was previously configured in a different language.

## Artifact Structure

All PNGs and metadata are written to:

- `miataru/artifacts/screenshots/<version-build-tag>/<language>/<device>/*.png`
- `miataru/artifacts/screenshots/<version-build-tag>/<language>/<device>/manifest.json`
- `miataru/artifacts/screenshots/<version-build-tag>/manifest.json` (aggregated)
- `miataru/artifacts/xcresult/<version-build-tag>/*` (result bundles and exported data)

`<version-build-tag>` is resolved from the app target by default:

- `MARKETING_VERSION` (version)
- `CURRENT_PROJECT_VERSION` (build)

Example: `v3-1-2-b6`

## Skip Behavior ("up to 10")

The test class contains 10 deterministic scenarios. Unreachable scenarios are recorded via `XCTSkip` so the overall run remains stable while still producing usable PNG output.

## Troubleshooting

- Missing iOS runtime:
  - Check `xcrun simctl list runtimes available`.
  - Install an iOS simulator runtime in Xcode settings.
- Empty PNG output:
  - Check whether tests were skipped.
  - Check `*.xcresult` under `artifacts/xcresult`.
- Unexpected UI overlays:
  - Screenshot runs use `-ui-testing` and `-ui-screenshot-mode` for more deterministic states.
- Screenshot language does not match `--languages`:
  - Re-run once with the same command. The script now configures `AppleLanguages` and `AppleLocale` on the simulator before test execution.
  - Verify command output contains `Configuring simulator locale: language=... locale=...`.
