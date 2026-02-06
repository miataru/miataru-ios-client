/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * ShimmeringRoutePolyline.swift
 * miataru
 *
 * Created by Codex on 06.02.26.
 */

import SwiftUI
import MapKit

/// Animation direction for the route shimmer.
enum RouteShimmerDirection {
    /// Animate from the polyline start point to its end point.
    case forward
    /// Animate from the polyline end point back to its start point.
    case backward

    var phaseSign: CGFloat {
        switch self {
        case .forward: return -1
        case .backward: return 1
        }
    }
}

/// Styling and behavior options for an animated route shimmer.
struct RouteShimmerConfiguration {
    var isLooping: Bool = true
    var showsAnimation: Bool = true
    var direction: RouteShimmerDirection = .forward
    var cycleDuration: Double = 1.6
    var baseLineWidth: CGFloat = 4
    var shimmerLineWidth: CGFloat = 6
    var dashLength: CGFloat = 22
    var dashGap: CGFloat = 30
    var baseColor: Color = RouteStyle.withoutRemaining
    var shimmerColor: Color = .white
    var shimmerOpacity: Double = 0.9

    var cycleLength: CGFloat {
        max(1, dashLength + dashGap)
    }
}

/// MapContent component that renders a route polyline with an optional directional shimmer overlay.
struct ShimmeringRoutePolyline: MapContent {
    @Environment(\.animationsAllowed) private var animationsAllowed

    let polyline: MKPolyline
    let configuration: RouteShimmerConfiguration
    let progress: CGFloat

    private var effectiveProgress: CGFloat {
        if configuration.isLooping {
            progress.truncatingRemainder(dividingBy: 1)
        } else {
            min(1, max(0, progress))
        }
    }

    private var dashPhase: CGFloat {
        configuration.direction.phaseSign * effectiveProgress * configuration.cycleLength
    }

    var body: some MapContent {
        MapPolyline(polyline)
            .stroke(configuration.baseColor, lineWidth: configuration.baseLineWidth)

        if configuration.showsAnimation && animationsAllowed {
            MapPolyline(polyline)
                .stroke(
                    LinearGradient(
                        colors: [
                            configuration.shimmerColor.opacity(0),
                            configuration.shimmerColor.opacity(configuration.shimmerOpacity),
                            configuration.shimmerColor.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(
                        lineWidth: configuration.shimmerLineWidth,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [configuration.dashLength, configuration.dashGap],
                        dashPhase: dashPhase
                    )
                )
        }
    }
}
