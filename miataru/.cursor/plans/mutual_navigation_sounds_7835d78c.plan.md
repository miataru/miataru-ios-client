---
name: Mutual Navigation Sounds
overview: Add subtle on/off sound cues when mutual navigation toggles, using bundled audio files that respect silent mode and triggering only while the navigation view is active.
todos:
  - id: add-audio-assets
    content: Add two sound files to bundle resources with default names.
    status: pending
  - id: add-sound-helper
    content: Implement shared sound player respecting silent mode.
    status: pending
  - id: wire-toggle-sounds
    content: Trigger on/off sounds on mutual navigation changes.
    status: pending
isProject: false
---

# Mutual Navigation Sound Cues

## Context

- Mutual navigation state changes are observed in `[iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)` and already wired via `onChange`.

```324:327:miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift
            .onChange(of: mutualNavigationDetector.isMutualNavigation) { _, newValue in
                isMutualNavigation = newValue
                updateBottomAccessory()
            }
```

- Mutual navigation detection is handled by `[MutualNavigationDetector.swift](miataru/views/Common/MutualNavigationDetector.swift)` with hysteresis and polling; we will hook sounds at the UI layer when the published state changes.

## Plan

- Add two bundled sound files with default names `mutual_navigation_on` and `mutual_navigation_off` under `[miataru/Assets/Sounds/](miataru/Assets/Sounds/)` and register them as resources in `[miataru.xcodeproj/project.pbxproj](miataru.xcodeproj/project.pbxproj)`.
- Create a small sound player helper (new file, e.g. `[miataru/Audio/SoundEffectPlayer.swift](miataru/Audio/SoundEffectPlayer.swift)`) using `AVAudioPlayer`, configured with `AVAudioSession` `.ambient` so it respects silent mode, and cache players for quick playback.
- Update `[iPhone_DeviceNavigationView.swift](miataru/views/iPhone/Devices Views/iPhone_DeviceNavigationView.swift)` to:
  - Track view visibility (e.g. `@State private var isViewActive = false`).
  - In the existing `onChange` for `mutualNavigationDetector.isMutualNavigation`, play `mutual_navigation_on` when `newValue` becomes `true`, and `mutual_navigation_off` when it becomes `false`, guarded by `isViewActive` so it does not play on teardown.
- Optional: add a small, clear debug log when a sound fails to load (no user-facing text changes).

## Notes

- Default filenames assume `.caf` or `.m4a`; the helper will attempt a small list of common extensions (or accept one) so you can drop in the files later without code changes.
- No new localized strings needed; all comments and strings remain English.

