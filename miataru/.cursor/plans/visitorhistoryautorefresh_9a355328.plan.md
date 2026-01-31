---
name: VisitorHistoryAutoRefresh
overview: Align the QR-code tab visitor history refresh behavior with the Devices tab by adding the same visibility-aware, throttled auto-refresh triggers.
todos:
  - id: add-visitor-refresh-throttle
    content: Add refreshIfNeeded throttling to VisitorHistoryViewModel
    status: completed
  - id: wire-qr-view-auto-refresh
    content: Hook QR view to notifications and visibility
    status: completed
  - id: verify-behavior
    content: Check refreshable + initial load behavior
    status: completed
isProject: false
---

# Visitor History Auto-Refresh Plan

## Current behavior recap

- Devices tab (`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_DevicesView.swift`) triggers refresh on pull-to-refresh plus notifications for own-location updates and app activation, with throttling and visibility checks handled by `DeviceLocationRefresher`.
- QR-code tab visitor history (`/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift`) only loads on first appear and on manual refresh; it does not auto-refresh while visible.
- Visitor history data loading lives in `VisitorHistoryViewModel` within `/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift`.

## Plan

1. **Add a throttled auto-refresh helper for visitor history**

- Extend `VisitorHistoryViewModel` with a `lastRefresh` timestamp and a `refreshIfNeeded(isVisible:force:)` method similar to `DeviceLocationRefresher.shouldRefresh`, using:
  - `SettingsManager.shared.autoRefreshDeviceList` as the enable flag.
  - `SettingsManager.shared.mapUpdateInterval` as the throttle interval.
  - `UIApplication.shared.applicationState == .active` on main thread to avoid background refresh.
- Keep `loadVisitorHistory()` as the core fetch, and make `refreshIfNeeded` call it when conditions are met.

1. **Wire QR-code tab to auto-refresh while visible**

- In `iPhone_MyDeviceQRCodeView`, add a `@State private var isVisible` flag set in `.onAppear` / `.onDisappear`.
- Add `.onReceive(NotificationCenter.default.publisher(for: .didSendOwnLocationUpdate))` to call `visitorHistoryViewModel.refreshIfNeeded(isVisible: isVisible)`.
- Add `.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))` to call the same refresh (matching Devices tab behavior).
- Keep `.refreshable` to perform a forced refresh (bypassing throttle) by calling `refreshIfNeeded(..., force: true)` or `loadVisitorHistory()` directly.

1. **Verify behavior and guardrails**

- Ensure auto-refresh does nothing when `autoRefreshDeviceList` is off or the view is not visible.
- Confirm initial load still happens when the list is empty on first appear.

## Key references

- Devices tab refresh triggers: `/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_DevicesView.swift`
- Visitor history model and loading: `/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift`
- QR-code tab view: `/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift`

## Notes

- This mirrors the Devices tab behavior without introducing new settings; it reuses existing user preferences and the existing update interval.

