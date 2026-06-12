# iPad vs iPhone Audit (2026-03-04)

## Scope
Audit focused on iPad/iPhone behavior drift in device management, history flow, testability, and platform-specific UX decisions.

## Decision Matrix
| Bereich | Beleg | Risiko | Entscheidung | Begruendung | Status |
| --- | --- | --- | --- | --- | --- |
| Device deletion + allowlist sync (iPad) | `views/iPad/iPad_DevicesView.swift` vs `views/iPhone/iPhone_DevicesView.swift` (`AllowedDeviceListManager.removeDeviceAndSync`) | iPad could diverge from server-side allowlist and produce inconsistent security state | iPad deletion now uses allowlist sync path when `allowedDeviceListEnabled == true` | Keep data/security behavior identical across platforms | Implemented |
| Device history open flow (iPad) | `views/iPad/Devices Views/iPad_DeviceMapView.swift` (`triggerHistory`) vs iPhone preload flow | Navigation to empty history screen / missing user feedback on no data | iPad now preloads and validates history before navigating | Consistent UX and error behavior on both platforms | Implemented |
| Test-critical accessibility IDs (iPad) | Screenshot/UI tests expect `devices_add_button`, `devices_row_this_device`, `device_map_overview` | Platform-specific test flakiness and false negatives | Added matching IDs on iPad list/map surfaces | Stable cross-platform UI automation and screenshot capture | Implemented |
| Unknown visitors section on iPad devices | Present in `iPhone_DevicesView`, previously absent in `iPad_DevicesView` | Feature parity gap for allow/ignore workflows | Added Unknown Visitors section incl. allow/ignore + prefill add-device sheet | Align allowlist/visitor workflows across iPhone and iPad | Implemented |
| Visitor auto-refresh + retry behavior (iPad) | `iPad_DevicesView`, `iPhone_MyDeviceQRCodeView`, `VisitorHistoryViewModel.refreshIfNeeded` | iPad visitor data could remain stale after transient failures due to pre-emptive refresh throttling and missing periodic parity refresh | Added periodic foreground refresh tasks and changed refresh throttling to advance only on successful loads | Ensures iPad/iPhone visitor visibility recovers consistently after temporary server/network issues | Implemented |
| Groups placement (iPhone embedded vs iPad tab/split) | `CHANGELOG.md` and root view structure (`iPhone_RootView`, `iPad_RootView`) | None (product-intended UX difference) | Keep split behavior as-is | Intentional platform UX: compact vs large-screen navigation model | Intentional |

## Notes
- No public API or persistence schema changes were required.
- Changes are limited to SwiftUI view logic, internal helper flows, and accessibility identifiers.
- Screenshot tests are used for full screenshot runs and were not executed individually in this change.
