# Device Slogan Cleansing And Friendly Error Message (2026-03-12)

## Problem
Users could enter slogan text that contained disallowed control characters (for example tab/newline).  
Those values were forwarded to the backend and could be rejected by `setDeviceSlogan`.

In addition, failed slogan-save operations sometimes surfaced raw server/system error text directly in red UI text.

## Changes
- Added centralized slogan cleansing in `MiataruAppAPI.cleanseDeviceSlogan(...)`:
  - remove control characters (`CharacterSet.controlCharacters`)
  - trim leading/trailing whitespace and newlines
  - enforce max length 40
- Applied that cleansing in all slogan set flows:
  - API wrapper (`MiataruAppAPI.setDeviceSlogan`)
  - iPhone "My Device" slogan editor live input + save path
  - iPhone "Edit Device" slogan editor live input + save path
  - slogan cache normalization (`DeviceSloganCacheStore`)
- Replaced raw fallback error text on slogan-save failures with a fixed localized message key:
  - `device_slogan_set_failed_try_again_later`
  - Added translations for all supported locales: `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, `zh-Hans`

## UX Result
- Invalid control/special characters are filtered before sending to backend.
- Users now see a stable, friendly slogan-save error instead of raw backend error payloads.

## Validation
- Project build completed successfully after the changes.
