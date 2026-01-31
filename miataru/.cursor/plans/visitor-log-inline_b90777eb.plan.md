---
name: visitor-log-inline
overview: Move the visitor history from a separate navigation view into an inline section that renders directly under the QR code tab content, reusing the existing visitor history row UI and data loading logic.
todos:
  - id: extract-visitor-section
    content: Create reusable visitor history section + shared load logic
    status: completed
  - id: embed-qr-tab
    content: Insert inline visitor section below QR code tab content
    status: completed
  - id: wire-standalone-view
    content: Rewire standalone visitor view to reuse shared section
    status: completed
  - id: docs-changelog
    content: Update changelog and relevant docs
    status: completed
isProject: false
---

- Refactor visitor history UI into a reusable inline section view (ex: `VisitorHistorySection`) that renders loading/error/empty/list states using `VisitorHistoryRow` and existing load logic. Keep strings in English-only keys already used.
- Update `[miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_MyDeviceQRCodeView.swift)` to remove the visitor history button/navigation destination and insert the new section below the device ID/share area inside the existing `ScrollView`.
- Adjust `[miataru/views/iPhone/iPhone_VisitorHistoryView.swift](/Users/bietiekay/code/miataru-ios-app/miataru/miataru/views/iPhone/iPhone_VisitorHistoryView.swift)` to use the shared inline section content (or shared view model) so the standalone view still works if used elsewhere, without duplicating logic.
- Verify the layout works in portrait/landscape and that pull-to-refresh still operates in the QR tab (if retained) or provide a retry button when errors occur.
- Update `[CHANGELOG.md](/Users/bietiekay/code/miataru-ios-app/miataru/CHANGELOG.md)` and any relevant docs (for example `[APP_STORE_DESCRIPTION.md](/Users/bietiekay/code/miataru-ios-app/miataru/APP_STORE_DESCRIPTION.md)` or `[APP_FEATURES.md](/Users/bietiekay/code/miataru-ios-app/miataru/APP_FEATURES.md)`) to reflect the new inline visitor log placement.