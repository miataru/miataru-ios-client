---
name: post_update_onboarding
overview: Show a one-time, reduced onboarding flow (Welcome → Device Key → Done) for existing users who have already completed onboarding and had location tracking enabled in prior launches, across iPhone/iPad/Mac.
todos:
  - id: add-post-update-flag
    content: Add UserDefaults flag + onboarding mode in app state.
    status: completed
  - id: wire-mode-to-containers
    content: Pass onboarding mode through container views.
    status: completed
  - id: build-reduced-pages
    content: Create reduced onboarding pages and set completion flag.
    status: completed
isProject: false
---

# Post-Update Onboarding Replay

## Context

- Current onboarding display is driven by `UserDefaults.standard.hasCompletedOnboarding` and shows the full wizard via `OnboardingContainerView`.

```14:33:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/miataruApp.swift
extension UserDefaults {
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: "hasCompletedOnboarding") }
        set { set(newValue, forKey: "hasCompletedOnboarding") }
    }
}

class AppState: ObservableObject {
    @Published var showOnboarding: Bool = !UserDefaults.standard.hasCompletedOnboarding
}
```

- The iPhone flow currently assembles all pages and marks completion on the Done view.

```17:34:/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_OnboardingContainerView.swift
private var pages: [AnyView] {
    var pages: [AnyView] = [
        AnyView(iPhone_1_OnboardingWelcomeView()),
        AnyView(iPhone_2_OnboardingLocationPermissionView()),
        AnyView(iPhone_3_OnboardingServerView()),
        AnyView(iPhone_5_OnboardingQRcodeView())
    ]
    if settings.trackAndReportLocation {
        pages.append(AnyView(iPhone_4_OnboardingLocationHistoryView()))
    }
    if settings.trackAndReportLocation {
        pages.append(AnyView(iPhone_6_OnboardingDeviceKeyView()))
    }
    pages.append(AnyView(iPhone_7_OnboardingDoneView(onFinish: {
        UserDefaults.standard.hasCompletedOnboarding = true
        isPresented = false
    })))
    return pages
}
```

## Plan

- Add a new `UserDefaults` flag to track whether the post-update onboarding has been shown (e.g., `hasShownPostUpdateOnboarding`).
- Update `AppState` (in `miataruApp.swift`) to compute a new onboarding mode:
  - If `hasCompletedOnboarding == false` → show full onboarding (current behavior).
  - Else if `hasCompletedOnboarding == true`, `hasShownPostUpdateOnboarding == false`, and location tracking was enabled in prior launches (via `SettingsManager.shared.trackAndReportLocation`) → show post-update onboarding (new reduced flow).
  - Otherwise → no onboarding.
- Extend `OnboardingContainerView` to accept a mode (e.g., `.full` vs `.postUpdate`) and route to platform-specific containers with that mode.
- Update platform-specific containers to build the reduced page list for post-update mode:
  - iPhone: `[Welcome, DeviceKey, Done]`
  - iPad: equivalent views for welcome/device key/done
  - Mac: equivalent views for welcome/device key/done
- When the reduced flow finishes, set `hasShownPostUpdateOnboarding = true` and dismiss.
- Keep all user-facing strings unchanged (English-only).

## Files to change

- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/miataruApp.swift]( /Users/bietiekay/code/miataru-ios-app/miataru/miataru/miataruApp.swift )` — add the new flag and onboarding mode selection.
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/OnboardingContainerView.swift]( /Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/OnboardingContainerView.swift )` — add a mode parameter and pass it to platform containers.
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_OnboardingContainerView.swift]( /Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_OnboardingContainerView.swift )` — build page list based on mode.
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPad/iPad_OnboardingContainerView.swift]( /Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPad/iPad_OnboardingContainerView.swift )` — build page list based on mode.
- `[/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Mac/Mac_OnboardingContainerView.swift]( /Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/Mac/Mac_OnboardingContainerView.swift )` — build page list based on mode.

## Open question assumptions

- The “existing users” check is `hasCompletedOnboarding == true` (per your selection) and applies across all platforms.

