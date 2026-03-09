# Unknown Visitor Alerts Phase 1 (2026-03-09)

## Goal
Introduce an opt-in local notification feature that informs users when an unknown device requests their location.

## Scope
- Feature is disabled by default.
- Feature can be enabled from Settings and from a new full-onboarding step.
- Enabling uses one centralized permission flow.
- Unknown-visitor checks are triggered after successful location delivery.
- Notification dedupe/cooldown is per unknown device (24 hours).
- New strings are fully localized in all supported app locales.

## User-facing Behavior
- New toggle: `unknownVisitorAlertsEnabled` (default `false`).
- If user enables toggle:
  - `notDetermined`: permission request is shown.
  - `authorized`/`provisional`/`ephemeral`: feature remains enabled.
  - `denied`: feature is switched back off and user gets a hint + app-settings shortcut.
- Notification text:
  - Detailed: localized format with slogan and city placeholders.
  - Fallback: localized generic unknown-device message.
- Foreground behavior: alert notifications are presented with banner/list/sound.

## Architecture
### Core Service
- `UnknownVisitorAlertService` (actor) provides:
  - `setFeatureEnabled(_:)`
  - `processAfterSuccessfulLocationUpdate(serverURL:)`
- Responsibilities:
  - permission status evaluation/requesting via a notifier abstraction
  - watermark-based incremental visitor processing
  - filtering out own device, known devices, and ignored devices
  - per-device notification cooldown handling (24h)
  - best-effort enrichment lookup (slogan/city)
  - local notification scheduling
  - in-flight coalescing for parallel trigger calls

### Evaluator
- `UnknownVisitorAlertEvaluator` encapsulates pure selection logic:
  - timestamp parsing/normalization
  - device ID normalization
  - watermark progression
  - cooldown checks

### Trigger Integration
- Hook after direct successful `updateLocation` submit in `LocationManager`.
- Hook after successful outbox flush item delivery in `LocationUpdateDeliveryCoordinator`.

### Onboarding and Settings Integration
- New onboarding page: `iPhone_9_OnboardingUnknownVisitorAlertsView`.
- Added to iPhone/iPad/Mac onboarding container only in `.full` mode and only when tracking is enabled.
- Settings and onboarding use the same `SettingsManager` activation method.

## Persistence and Internal Keys
- Setting key: `unknown_visitor_alerts_enabled`
- Processing watermark: `unknown_visitor_alert_last_processed_ts_ms`
- Last-notified map: `unknown_visitor_alert_last_notified_by_device`

## Localization
Added localized keys for:
- onboarding title/intro/example
- settings toggle + explanation
- permission denied hint + settings CTA
- notification title + detailed/fallback body

Locales covered:
- `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`

## Validation
- Build succeeds for iOS target.
- Unit tests added for evaluator and permission flow.
- Localization completeness test ensures all required new keys exist and are non-empty in all supported locales.
