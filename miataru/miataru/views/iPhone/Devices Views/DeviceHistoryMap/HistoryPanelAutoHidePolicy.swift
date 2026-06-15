/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * HistoryPanelAutoHidePolicy.swift
 * miataru
 */

import Foundation

enum HistoryPanelAutoHideEvent {
    case mapPanZoom
    case mapPointSelection
    case playbackPlayPause
    case playbackSpeedChange
    case timelineScrub
    case timelineRangeDrag
    case quickRangeSelection
    case programmaticCameraChange
    case viewAppeared
}

enum HistoryPanelAutoHideAction: Equatable {
    case none
    case startOrRestart
}

struct HistoryPanelAutoHidePolicy {
    static func action(for event: HistoryPanelAutoHideEvent) -> HistoryPanelAutoHideAction {
        switch event {
        case .mapPanZoom,
             .mapPointSelection,
             .playbackPlayPause:
            return .startOrRestart
        case .playbackSpeedChange,
             .timelineScrub,
             .timelineRangeDrag,
             .quickRangeSelection,
             .programmaticCameraChange,
             .viewAppeared:
            return .none
        }
    }
}
