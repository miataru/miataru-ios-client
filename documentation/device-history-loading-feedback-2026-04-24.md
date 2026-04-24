# Device History Loading Feedback

Date: 2026-04-24

## Problem

When users opened a device's location history, the app preloaded history data before navigating. During that request the UI looked blocked or unresponsive. After navigation, the history map could also briefly show the empty-state screen before cached or freshly loaded history entries had been applied to the view model.

## Changes

- Added a visible loading HUD to the iPhone and iPad device map while history is being preloaded.
- Included the selected device name or ID in the loading HUD so users can see what is being loaded.
- Added the localized `history_loading` string for all languages present in the string catalog.
- Delayed the history map empty-state until the initial cache/server load has actually resolved.
- Kept the history map in an initial loading state to avoid an empty-state flash before cached history is hydrated.
- Made history preload failures visible for invalid configuration, invalid server responses, encoding/decoding failures, network failures, server failures, and unknown errors.
- Increased history preload error visibility to 5 seconds and made the common error overlay wrap long messages more reliably.
- Included the release version bump from `3.1.6` to `3.1.7`.

## Verification

- `jq empty miataru/miataru/Assets/Localizable.xcstrings`
- Confirmed relevant history error/loading keys are localized for `da`, `de`, `en`, `es`, `fi`, `fr`, `it`, `ja`, `nl`, and `zh-Hans`.
- `xcodebuild -project miataru/miataru.xcodeproj -scheme miataru -configuration Debug -destination 'generic/platform=iOS Simulator' build`

## Expected UX

Opening a device history now immediately communicates that history data is loading. If history exists, the user should not see the "no location history" fallback during the initial transition. If loading fails or no data exists, the app presents a readable localized message.
