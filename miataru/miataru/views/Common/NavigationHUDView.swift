import SwiftUI
import CoreLocation
import MapKit

struct NavigationHUDView: View {
    @ObservedObject private var preferences = NavigationHUDSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsAllowed) private var animationsAllowed
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var focusedRouteIsVisible = false
    @State private var controlsAreVisible = true
    @State private var controlsAutoHideTask: Task<Void, Never>?

    let location: CLLocation?
    let destination: String
    let remoteLabel: String
    let routeDistance: String?
    let travelTime: String?
    let instruction: String?
    let instructionSymbol: String?
    let directionLabel: String
    let userCoordinate: CLLocationCoordinate2D?
    let userHeadingDegrees: CLLocationDirection?
    let userHeadingIsMeasured: Bool
    let allowsRouteTangentFallback: Bool
    let remoteCoordinate: CLLocationCoordinate2D?
    let routeCoordinates: [CLLocationCoordinate2D]
    let focusedRouteCoordinates: [CLLocationCoordinate2D]
    let canFocusRoute: Bool
    let routeSessionID: UInt64
    let onClose: () -> Void
    let onSetPalette: (NavigationHUDPalette) -> Void
    let onToggleMirror: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let speed = Self.speedText(for: location, now: context.date)
            VStack(spacing: 0) {
                HStack {
                    Button {
                        registerHUDInteraction()
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                    }
                    .accessibilityLabel(Text("navigation_hud_close", tableName: "MapNavigationHistory"))
                    Spacer()
                    Menu {
                        ForEach(NavigationHUDPalette.allCases) { palette in
                            Button {
                                registerHUDInteraction()
                                onSetPalette(palette)
                            } label: {
                                if preferences.palette == palette {
                                    Label(palette.optionTitle, systemImage: "checkmark")
                                } else {
                                    Text(palette.optionTitle)
                                }
                            }
                            .accessibilityIdentifier("navigation_hud_palette_option_\(palette.rawValue)")
                        }
                    } label: {
                        Label(preferences.palette.optionTitle, systemImage: "circle.lefthalf.filled")
                            .font(.headline)
                    }
                    .accessibilityLabel(Text("navigation_hud_palette", tableName: "MapNavigationHistory"))
                    .accessibilityIdentifier("navigation_hud_palette_menu")
                    Button {
                        registerHUDInteraction()
                        onToggleMirror()
                    } label: {
                        Image(systemName: preferences.isMirrored ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "arrow.left.and.right")
                            .font(.title2)
                    }
                    .accessibilityLabel(Text("navigation_hud_mirror", tableName: "MapNavigationHistory"))
                    .padding(.leading, 14)
                }
                .foregroundStyle(toolbarForeground)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .opacity(shouldShowControls ? 1 : 0)
                .allowsHitTesting(shouldShowControls)
                .accessibilityHidden(!shouldShowControls)

                GeometryReader { geometry in
                    if geometry.size.width > geometry.size.height {
                        HStack(spacing: 12) {
                            VStack(spacing: 8) {
                                titleAndSpeed(speed, speedSize: 76)
                                ScrollView(.vertical) {
                                    routeSummary(isLandscape: true)
                                }
                                .scrollIndicators(.hidden)
                                .frame(maxHeight: .infinity)
                            }
                            .frame(width: geometry.size.width * 0.42, height: geometry.size.height)
                            routeVisual
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.trailing, 16)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            titleAndSpeed(speed, speedSize: 94)
                                .padding(.top, 14)
                            routeVisual
                                .frame(maxWidth: 760, maxHeight: .infinity)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                            routeSummary(isLandscape: false)
                                .padding(18)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 18)
                        }
                    }
                }
                .foregroundStyle(foreground)
                .scaleEffect(x: preferences.isMirrored ? -1 : 1, y: 1)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { registerHUDInteraction() })
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .animation(animationsAllowed && !reduceMotion ? .easeInOut(duration: 0.18) : nil, value: preferences.palette)
            .animation(animationsAllowed && !reduceMotion ? .easeInOut(duration: 0.65) : nil, value: focusedRouteIsVisible)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("navigation_hud")
            .task(id: "\(routeSessionID)-\(canFocusRoute)") {
                focusedRouteIsVisible = false
                guard canFocusRoute else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                focusedRouteIsVisible = true
            }
            .onAppear { scheduleControlsAutoHide() }
            .onDisappear { controlsAutoHideTask?.cancel() }
            .onChange(of: voiceOverEnabled) { _, enabled in
                if enabled {
                    controlsAutoHideTask?.cancel()
                    controlsAreVisible = true
                } else {
                    scheduleControlsAutoHide()
                }
            }
        }
    }

    private func titleAndSpeed(_ speed: String, speedSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(destination)
                .font(.title.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(speed)
                    .font(.system(size: speedSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(preferences.palette == .yellow ? .yellow : foreground)
                    .contentTransition(animationsAllowed && !reduceMotion ? .numericText() : .identity)
                    .animation(animationsAllowed && !reduceMotion ? .easeOut(duration: 0.22) : nil, value: speed)
                Text(String(localized: "navigation_speed_kmh_unit", table: "MapNavigationHistory"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(foreground.opacity(0.75))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.speedAccessibilityText(for: speed)))
            .accessibilityIdentifier("navigation_hud_speed")
        }
    }

    private var routeVisual: some View {
        Group {
            if focusedRouteIsVisible && canFocusRoute {
                RouteHUDVectorView(
                    coordinates: focusedRouteCoordinates,
                    userCoordinate: userCoordinate,
                    headingDegrees: userHeadingDegrees,
                    headingIsMeasured: userHeadingIsMeasured,
                    allowsRouteTangentFallback: allowsRouteTangentFallback,
                    remoteCoordinate: nil,
                    userLabel: String(localized: "navigation_hud_you", table: "MapNavigationHistory"),
                    remoteLabel: remoteLabel,
                    tint: accent,
                    lineWidth: preferences.palette == .yellow ? 10 : 8,
                    isForwardFocused: true
                )
                .id("forward-focus")
                .transition(.scale(scale: 1.14, anchor: .bottom).combined(with: .opacity))
            } else {
                RouteHUDVectorView(
                    coordinates: routeCoordinates,
                    userCoordinate: userCoordinate,
                    headingDegrees: userHeadingDegrees,
                    headingIsMeasured: userHeadingIsMeasured,
                    allowsRouteTangentFallback: allowsRouteTangentFallback,
                    remoteCoordinate: remoteCoordinate,
                    userLabel: String(localized: "navigation_hud_you", table: "MapNavigationHistory"),
                    remoteLabel: remoteLabel,
                    tint: accent,
                    lineWidth: preferences.palette == .yellow ? 10 : 8
                )
                .id("route-overview")
                .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityIdentifier("navigation_hud_route_vector")
    }

    private var turnInstruction: some View {
        HStack(alignment: .top, spacing: 8) {
            if let instructionSymbol {
                Image(systemName: instructionSymbol).font(.system(size: 34, weight: .bold))
            }
            Text(instruction ?? String(localized: "navigation_hud_route_overview", table: "MapNavigationHistory"))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("navigation_hud_instruction")
        }
    }

    private func routeSummary(isLandscape: Bool) -> some View {
        VStack(alignment: isLandscape ? .leading : .center, spacing: 10) {
            turnInstruction
                .frame(maxWidth: .infinity, alignment: isLandscape ? .leading : .center)
                .accessibilityElement(children: .combine)
            if isLandscape {
                VStack(alignment: .leading, spacing: 5) {
                    if let routeDistance { Label(routeDistance, systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                    if let travelTime { Label(travelTime, systemImage: "clock") }
                }
                .font(.body.monospacedDigit().weight(.semibold))
                .accessibilityIdentifier("navigation_hud_route_summary")
            } else {
                HStack(spacing: 20) {
                    if let routeDistance { Label(routeDistance, systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                    if let travelTime { Label(travelTime, systemImage: "clock") }
                }
                .font(.title2.monospacedDigit().weight(.semibold))
                .accessibilityIdentifier("navigation_hud_route_summary")
            }
            Text(directionLabel.uppercased()).font(.title3.weight(.semibold)).opacity(0.82)
        }
        .foregroundStyle(foreground)
        .padding(isLandscape ? 12 : 18)
        .background(foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, isLandscape ? 0 : 20)
    }

    private var foreground: Color {
        switch preferences.palette {
        case .white, .yellow: .white
        case .red: .red
        }
    }

    private var toolbarForeground: Color {
        .white
    }

    private var background: Color {
        .black
    }

    private var accent: Color {
        switch preferences.palette {
        case .white: .white
        case .red: .red
        case .yellow: .white
        }
    }

    private var shouldShowControls: Bool { controlsAreVisible || voiceOverEnabled }

    private func registerHUDInteraction() {
        controlsAreVisible = true
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideTask?.cancel()
        guard !voiceOverEnabled else {
            controlsAreVisible = true
            return
        }
        controlsAreVisible = true
        controlsAutoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled, !voiceOverEnabled else { return }
            withAnimation(animationsAllowed && !reduceMotion ? .easeInOut(duration: 0.25) : nil) {
                controlsAreVisible = false
            }
        }
    }

    static func speedText(for location: CLLocation?, now: Date = Date()) -> String {
        guard let location, now.timeIntervalSince(location.timestamp) >= 0,
              now.timeIntervalSince(location.timestamp) <= 15,
              location.speed.isFinite, location.speed >= 0 else { return "—" }
        let value = location.speed * 3.6
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    static func speedAccessibilityText(for formattedSpeed: String) -> String {
        let format = NSLocalizedString(
            "navigation_speed_accessibility_format",
            tableName: "MapNavigationHistory",
            comment: "VoiceOver label for the live speed in kilometers per hour"
        )
        return String.localizedStringWithFormat(format, formattedSpeed)
    }
}

private struct RouteHUDVectorView: View {
    @ObservedObject private var preferences = NavigationHUDSettings.shared
    let coordinates: [CLLocationCoordinate2D]
    let userCoordinate: CLLocationCoordinate2D?
    let headingDegrees: CLLocationDirection?
    let headingIsMeasured: Bool
    let allowsRouteTangentFallback: Bool
    let remoteCoordinate: CLLocationCoordinate2D?
    let userLabel: String
    let remoteLabel: String
    let tint: Color
    let lineWidth: CGFloat
    var isForwardFocused = false

    var body: some View {
        GeometryReader { proxy in
            let projection = NavigationHUDProjection.project(
                routeCoordinates: coordinates,
                userCoordinate: userCoordinate,
                remoteCoordinate: remoteCoordinate,
                size: proxy.size,
                alignForward: isForwardFocused,
                headingDegrees: headingDegrees,
                allowsRouteTangentFallback: allowsRouteTangentFallback
            )
            let projected = projection.route
            ZStack {
                if projected.count > 1 {
                    Path { path in
                        path.addLines(projected)
                    }
                    .stroke(tint.opacity(0.92), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    Path { path in path.addLines(projected) }
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 9]))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "location.slash").font(.system(size: 42))
                        Text("navigation_hud_waiting_for_route", tableName: "MapNavigationHistory")
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                if projected.count > 1, let point = projection.user {
                    positionMarker(
                        label: userLabel,
                        point: point,
                        heading: projection.userHeadingVector,
                        color: userMarkerColor,
                        isMeasured: headingIsMeasured
                    )
                }
                if projected.count > 1, let point = projection.remote {
                    marker(symbol: "mappin.and.ellipse", label: remoteLabel, point: point, color: tint)
                }
            }
        }
        .frame(minHeight: 220)
    }

    private var userMarkerColor: Color {
        switch preferences.palette {
        case .white: Color(red: 0.91, green: 0.94, blue: 1)
        case .red: Color(red: 0.78, green: 0.31, blue: 0.34)
        case .yellow: Color(red: 1, green: 0.75, blue: 0.25)
        }
    }

    private func positionMarker(label: String, point: CGPoint, heading: CGVector?, color: Color, isMeasured: Bool) -> some View {
        VStack(spacing: 5) {
            if let heading {
                HUDPositionArrowView(vector: heading, color: color, isMeasured: isMeasured)
            } else {
                Circle()
                    .fill(color)
                    .overlay(Circle().stroke(.black, lineWidth: 6))
                    .overlay(Circle().stroke(.white, lineWidth: 1.8))
                    .frame(width: 28, height: 28)
                    .shadow(color: .black, radius: 4, y: 2)
            }
            Text(label)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(color)
                .shadow(color: .black, radius: 2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .position(point)
        .accessibilityLabel(label)
    }

    private func marker(symbol: String, label: String, point: CGPoint, color: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(color)
                .shadow(color: .black, radius: 3)
            Text(label)
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
        .position(point)
        .accessibilityLabel(label)
    }

}

private struct HUDPositionArrowView: View {
    @Environment(\.animationsAllowed) private var animationsAllowed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotationDegrees = 0.0

    let vector: CGVector
    let color: Color
    let isMeasured: Bool

    private var targetRotation: Double {
        NavigationHUDAngle.normalized(atan2(vector.dy, vector.dx) * 180 / .pi + 90)
    }

    var body: some View {
        ZStack {
            HUDPositionArrow().fill(color.opacity(isMeasured ? 1 : 0.55))
            HUDPositionArrow().stroke(.black, lineWidth: 6)
            HUDPositionArrow().stroke(.white, lineWidth: 1.8)
        }
        .frame(width: 54, height: 62)
        .rotationEffect(.degrees(rotationDegrees))
        .shadow(color: .black, radius: 4, y: 2)
        .onAppear { rotationDegrees = targetRotation }
        .onChange(of: targetRotation) { _, newValue in
            let delta = NavigationHUDAngle.shortestDelta(from: rotationDegrees, to: newValue)
            guard abs(delta) >= 1 else { return }
            if animationsAllowed && !reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    rotationDegrees += delta
                }
            } else {
                rotationDegrees = newValue
            }
        }
    }
}

private struct HUDPositionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.80))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.63))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.80))
        path.closeSubpath()
        return path
    }
}
