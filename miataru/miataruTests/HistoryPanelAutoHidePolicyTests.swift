import Testing
@testable import miataru

@Suite("History panel auto-hide policy")
struct HistoryPanelAutoHidePolicyTests {
    @Test("Map pan or zoom starts or restarts auto-hide")
    func mapPanZoomStartsAutoHide() {
        #expect(HistoryPanelAutoHidePolicy.action(for: .mapPanZoom) == .startOrRestart)
    }

    @Test("Map point selection starts or restarts auto-hide")
    func mapPointSelectionStartsAutoHide() {
        #expect(HistoryPanelAutoHidePolicy.action(for: .mapPointSelection) == .startOrRestart)
    }

    @Test("Play or pause starts or restarts auto-hide")
    func playPauseStartsAutoHide() {
        #expect(HistoryPanelAutoHidePolicy.action(for: .playbackPlayPause) == .startOrRestart)
    }

    @Test("Non-playback panel interactions do not affect auto-hide")
    func nonPlaybackPanelInteractionsDoNotAffectAutoHide() {
        let events: [HistoryPanelAutoHideEvent] = [
            .playbackSpeedChange,
            .timelineScrub,
            .timelineRangeDrag,
            .quickRangeSelection
        ]

        for event in events {
            #expect(HistoryPanelAutoHidePolicy.action(for: event) == .none)
        }
    }

    @Test("Programmatic and lifecycle events do not affect auto-hide")
    func programmaticAndLifecycleEventsDoNotAffectAutoHide() {
        let events: [HistoryPanelAutoHideEvent] = [
            .programmaticCameraChange,
            .viewAppeared
        ]

        for event in events {
            #expect(HistoryPanelAutoHidePolicy.action(for: event) == .none)
        }
    }
}
