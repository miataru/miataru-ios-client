/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * PulsingAccuracyCircle.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI

/// A reusable, GPU-friendly indicator for visualizing location accuracy and
/// presence. Designed for Miataru to be placed under the user's pin or any
/// tracked device, it renders a stable core with outward-expanding halos to
/// communicate activity/accuracy without the core size visually collapsing.
///

/// Implementation overview:
/// - The view consists of a constant-size core circle and two halos.
/// - Each halo scales from 1.0 to `haloMaxScale` with staggered delays to create
///   a layered rhythm. The animation repeats forever with an ease-out curve.
/// - The container frame is set to `size * haloMaxScale` to account for the
///   largest halo extent and prevent clipping.
/// - Rendering is flattened with `drawingGroup()` to reduce 3D perspective
///   warping when composited in MapKit overlays/annotations.
///
/// Typical use cases:
/// - Under the user's current location marker to visualize GPS accuracy.
/// - Behind tracked devices to indicate presence or recent updates.
/// - As a subtle attention cue in lists or detail views.
///
/// Customization:
/// - Use the initializer to tweak scale, opacities, and animation timings.
/// - `size` controls the core diameter; halos expand proportionally.
/// - `pulsingColor` accepts any SwiftUI `Color` (gradients are derived from it).
///
/// Accessibility:
/// - This view is purely decorative. Consider marking it hidden from
///   accessibility where embedded (e.g., `.accessibilityHidden(true)`) and
///   provide descriptive labels on the parent control/annotation as needed.
///
/// Example:
/// ```swift
/// PulsingAccuracyCircle(
///     pulsingColor: .orange,
///     size: 172,
///     haloMaxScale: 1.8
/// )
/// ```

struct PulsingAccuracyCircle: View {
    @Environment(\.animationsAllowed) private var animationsAllowed

    @State private var isPulsing = false

    // MARK: - Configurable parameters (edit in one place)
    /// The base color used to render the core and halos.
    let pulsingColor: Color
    /// Base diameter (in points) of the core circle. The view reserves extra
    /// headroom based on `haloMaxScale` to prevent clipping when halos expand.
    let size: CGFloat
    /// Maximum outward scale factor for halo expansion relative to `size`.
    let haloMaxScale: CGFloat
    /// Opacity of the stable core circle (kept at 1.0 scale).
    let coreOpacity: Double
    /// Opacity of the first (earlier) halo.
    let halo1Opacity: Double
    /// Opacity of the second (later) halo.
    let halo2Opacity: Double
    /// Duration (seconds) for one ease-out cycle (repeats forever with autoreverse).
    let animationDuration: Double
    /// Start delay (seconds) for halo 1 animation to create staggered rhythm.
    let halo1Delay: Double
    /// Start delay (seconds) for halo 2 animation to create staggered rhythm.
    let halo2Delay: Double

    /// Easing used for the repeating pulse. Defined from parameters to keep
    /// animation behavior centralized.
    private var easeGently: Animation {
        Animation.easeOut(duration: animationDuration).repeatForever(autoreverses: true)
    }

    /// Create a new pulsing accuracy indicator.
    /// - Parameters:
    ///   - pulsingColor: Base color for the core and halos.
    ///   - size: Core diameter in points. The view will allocate `size * haloMaxScale` space.
    ///   - haloMaxScale: Maximum outward scale factor for halos (>= 1.0).
    ///   - coreOpacity: Opacity for the core circle.
    ///   - halo1Opacity: Opacity for the first halo.
    ///   - halo2Opacity: Opacity for the second halo.
    ///   - animationDuration: Duration (seconds) of one pulse cycle.
    ///   - halo1Delay: Start delay (seconds) for the first halo.
    ///   - halo2Delay: Start delay (seconds) for the second halo.
    init(
        pulsingColor: Color = .blue,
        size: CGFloat,
        haloMaxScale: CGFloat = 1.6,
        coreOpacity: Double = 0.32,
        halo1Opacity: Double = 0.18,
        halo2Opacity: Double = 0.12,
        animationDuration: Double = 1.0,
        halo1Delay: Double = 0.30,
        halo2Delay: Double = 0.60
    ) {
        self.pulsingColor = pulsingColor
        self.size = size
        self.haloMaxScale = haloMaxScale
        self.coreOpacity = coreOpacity
        self.halo1Opacity = halo1Opacity
        self.halo2Opacity = halo2Opacity
        self.animationDuration = animationDuration
        self.halo1Delay = halo1Delay
        self.halo2Delay = halo2Delay
    }
    
    var body: some View {
        if animationsAllowed {
            ZStack {
                // Core circle stays at base size so the indicator never appears too small
                Circle()
                    .fill(pulsingColor.gradient)
                    .frame(width: size, height: size)
                    .opacity(coreOpacity)

                // Halo 1 - expands outward from 1.0x to `haloMaxScale`
                Circle()
                    .fill(pulsingColor.gradient)
                    .frame(width: size, height: size)
                    .opacity(halo1Opacity)
                    .scaleEffect(isPulsing ? haloMaxScale : 1.0)
                    .animation(easeGently.delay(halo1Delay), value: isPulsing)

                // Halo 2 - stagger start for smoother, layered pulsing effect
                Circle()
                    .fill(pulsingColor.gradient)
                    .frame(width: size, height: size)
                    .opacity(halo2Opacity)
                    .scaleEffect(isPulsing ? haloMaxScale : 1.0)
                    .animation(easeGently.delay(halo2Delay), value: isPulsing)
            }
            // Reserve headroom so expanding halos are not clipped
            .frame(width: size * haloMaxScale, height: size * haloMaxScale)
            // Flatten the rendering to mitigate perspective warping when composited
            // into 3D contexts (e.g., MapKit or other transformed containers)
            .drawingGroup()
            .onAppear {
                // Start the pulse once the view appears
                withAnimation {
                    isPulsing.toggle()
                }
            }
        }
    }
}

#Preview {
    ZStack() {
        PulsingAccuracyCircle(pulsingColor: Color(#colorLiteral(red: 0.9686274529, green: 0.78039217, blue: 0.3450980484, alpha: 1)), size: 172)
    }
    .background(
        LinearGradient(
            gradient: Gradient(colors: [.blue, .purple, .orange]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
