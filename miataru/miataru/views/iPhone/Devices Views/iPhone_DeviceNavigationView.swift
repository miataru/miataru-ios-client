/*
 * iPhone_DeviceNavigationView.swift
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 *
 * Created by Daniel Kirstenpfad on 25.08.25.
 * Displays route between the user's device and a selected device.
 */

import SwiftUI
import MapKit
import Combine
import CoreLocation
import Foundation
import UIKit
import AudioToolbox
import MiataruAPIClient
import NavigationOverlayKit

struct iPhone_DeviceNavigationView: View {
    var device: KnownDevice

    @EnvironmentObject private var routeInfoState: RouteInfoState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.animationsAllowed) private var animationsAllowed
    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var routeCache = RouteCacheStore.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var deviceStore = KnownDeviceStore.shared

    @Namespace private var mapScope
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var deviceCoordinate: CLLocationCoordinate2D?
    @State private var animatedUserCoordinate: CLLocationCoordinate2D?
    @State private var animatedDeviceCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var mutualRouteOverlayPolyline: MKPolyline?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var travelTime: String?
    @State private var distanceText: String?
    @State private var currentRegion: MKCoordinateRegion?
    @State private var hasSetInitialRegion = false
    @State private var userHasInteractedWithMap = false
    @State private var isUpdating = false
    @State private var currentMapCamera: MapCamera? = nil
    @State private var userHasRotatedMap = false
    @State private var isProgrammaticCameraChange = false
    @State private var isAutoCenteringEnabled = true
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var deviceTimestamp: Date? = nil
    @State private var userTimestamp: Date? = nil
    @State private var isLoading: Bool = false
    @State private var now = Date()
    @State private var isAutoRouteUpdateLocked: Bool = false
    /// true = non-reversed route (standard: selected device → user). false = reversed route (user → selected device, "reverse route" button).
    @State private var isRouteFromDeviceToUser: Bool = true
    @State private var navigationOverlayViewModel: NavigationOverlayViewModel? = nil
    @State private var hasLocationUpdateSinceLastAutoUpdate: Bool = false
    @State private var lastOverlayStepIndex: Int? = nil
    @State private var isChromeVisible: Bool = true
    @State private var isFollowDeviceHeadingMode: Bool = false
    @State private var isNavigationMode: Bool = false
    @State private var lastFollowCameraUpdate: Date? = nil
    @State private var lastFollowCameraCenter: CLLocationCoordinate2D? = nil
    @State private var lastFollowCameraHeading: CLLocationDirection? = nil
    @State private var lastFollowCameraDistance: CLLocationDistance? = nil
    @State private var followCameraDistanceOverride: CLLocationDistance? = nil
    @State private var isFollowAutoZoomEnabled: Bool = true
    @State private var currentMapHeadingDegrees: Double = 0
    @State private var shouldPerformInitialNavigationZoom: Bool = false
    @StateObject private var errorOverlayManager = ErrorOverlayManager()
    @StateObject private var infoOverlayManager = InfoOverlayManager()
    @ObservedObject private var routeCounter = RouteRequestCounter.shared
    @State private var suppressUserCameraChangeDetectionUntil: Date? = nil
    @StateObject private var mutualNavigationDetector = MutualNavigationDetector(
        ourDeviceId: thisDeviceIDManager.shared.deviceID,
        serverURL: SettingsManager.shared.miataruServerURL
    )
    // Track mutual navigation state in @State to ensure Map content updates
    @State private var isMutualNavigation: Bool = false
    @State private var isViewActive: Bool = false
    /// Reference type so the navigation feedback Combine sink always sees current values (not a snapshot from when the sink was created).
    @State private var navigationFeedbackGate = NavigationFeedbackGate()
    @State private var navigationOverlayCancellables = Set<AnyCancellable>()
    @State private var pendingRouteRetryOnReconnect: Bool = false
    @State private var routeRetryTask: Task<Void, Never>? = nil
    private let maxRouteRetryAttempts: Int = 3
    // Legacy fields removed in favor of RouteRequestCounter
    // Fit configuration: reduce padding around both markers when auto-centering
    private let fitPaddingMultiplier: Double = 1.8
    private let fitMinimumSpan = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
    // Minimum route progress required before showing ghost/progress segmentation
    private let minimumProgressToShowGhost: Double = 0.05

    /// Full-screen focused navigation mode (enabled via double-tap) uses a stable route rendering:
    /// base route + optional mutual-navigation overlay, without ghost/progress segmentation.
    private var shouldUseFocusedNavigationRouteRendering: Bool {
        isNavigationMode
    }

    private var offRouteThreshold: CLLocationDistance {
        switch settings.navigationTransportType {
        case 0: return 15
        case 3: return 50
        default: return 25
        }
    }
    private var cacheReuseThreshold: CLLocationDistance {
        switch settings.navigationTransportType {
        case 0: return 50
        case 3: return 150
        default: return 100
        }
    }
    // Distance threshold (meters) for automatically stopping navigation when devices are close
    private let autoStopDistanceThreshold: CLLocationDistance = 50
    // Track the initial distance when navigation started to determine if auto-stop should be enabled
    @State private var initialDistance: CLLocationDistance? = nil
    // Track if navigation has been automatically stopped to prevent re-triggering
    @State private var navigationStopped: Bool = false
    // Track the inputs used for the most recent route calculation to avoid unnecessary recalculations
    @State private var lastRouteUserCoordinate: CLLocationCoordinate2D? = nil
    @State private var lastRouteDeviceCoordinate: CLLocationCoordinate2D? = nil
    @State private var lastRouteUserTimestamp: Date? = nil
    @State private var lastRouteDeviceTimestamp: Date? = nil
    @State private var lastRouteTransportType: Int? = nil
    @State private var hasAppliedInitialFetchRouteSync: Bool = false
    // Generous daily upper bound to prevent accidental request lockout while developing/testing
    private let routeRequestDailyLimit: Int = 17000
    private let followCameraDistance: CLLocationDistance = 1100
    private let followCameraMinDistance: CLLocationDistance = 450
    private let followCameraMaxDistance: CLLocationDistance = 2200
    private let followUpdateMinInterval: TimeInterval = 0.35
    private let followUpdateMinDistance: CLLocationDistance = 3
    private let followUpdateMinHeadingDelta: CLLocationDirection = 2
    private let followUpdateMinDistanceDelta: CLLocationDistance = 40
    private let routeFitPaddingMultiplier: Double = 1.25
    private let navigationSpeedZoomThresholdKmh: CLLocationSpeed = 20
    private let navigationMediumSpeedMinCameraDistance: CLLocationDistance = 600
    private let navigationHighSpeedMinCameraDistance: CLLocationDistance = 900
    private let navigationLookAheadMinDistance: CLLocationDistance = 70
    private let navigationLookAheadMaxDistance: CLLocationDistance = 360
    private let mutualNavigationOnSoundName = "confirm"
    private let mutualNavigationOffSoundName = "cancel"
    private let navigationLeftSoundName = "nav_left"
    private let navigationRightSoundName = "nav_right"
    private let navigationStraightSoundName = "nav_straight"
    // System sound IDs (AudioToolbox): Tink = light pling, Tock = short click; used until nav_left/nav_right.caf are added
    private let navigationLeftSystemSoundID: SystemSoundID = 1103   // Tink.caf – KeyPressed
    private let navigationRightSystemSoundID: SystemSoundID = 1104   // Tock.caf – KeyPressed
    private let leftNavigationHapticInterval: TimeInterval = 0.2
    private let rightNavigationHapticInterval: TimeInterval = 0.12

    var body: some View {
        VStack {
            mapWithModifiers
        }
        .overlay(
            ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
        )
        .overlay(
            InfoOverlay(message: infoOverlayManager.message, visible: infoOverlayManager.visible)
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                reloadToolbarButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    isRouteFromDeviceToUser.toggle()
                    calculateRoute(ignoreCache: true)
                }) {
                    directionIndicatorIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("reverse_navigation_direction", comment: "Reverse navigation direction")))
                .accessibilityHint(Text(NSLocalizedString("reverse_navigation_direction_hint", comment: "Swaps the route to show navigation from the device to you, or from you to the device.")))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: openInAppleMaps) {
                    Image(systemName: "map")
                }
                .buttonStyle(.plain)
            }
        }
        .toolbar(isChromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(isChromeVisible ? .visible : .hidden, for: .tabBar)
        .toolbarBackgroundVisibility(isChromeVisible ? .visible : .hidden, for: .tabBar)
        .id(device.DeviceID)
            .onChange(of: device.DeviceID) {
            // Reset all device-related state when a new device is injected
            // We intentionally do NOT clear the route cache here; it is keyed by device id
            userCoordinate = nil
            deviceCoordinate = nil
            animatedUserCoordinate = nil
            animatedDeviceCoordinate = nil
            setRouteForRendering(nil)
            travelTime = nil
            distanceText = nil
            currentRegion = nil
            hasSetInitialRegion = false
            userHasInteractedWithMap = false
            currentMapCamera = nil
            userHasRotatedMap = false
            isProgrammaticCameraChange = false
            suppressUserCameraChangeDetectionUntil = nil
            isAutoCenteringEnabled = true
            // Ensure auto-update lock state follows global setting for new navigation
            isAutoRouteUpdateLocked = settings.automaticRouteUpdateDuringNavigation
            isRouteFromDeviceToUser = true // Reset to non-reversed (standard: device → user)
            navigationOverlayViewModel = nil
            navigationOverlayCancellables.removeAll()
            lastOverlayStepIndex = nil
            deviceTimestamp = nil
            isLoading = false
            lastRouteUserCoordinate = nil
            lastRouteDeviceCoordinate = nil
            lastRouteUserTimestamp = nil
            lastRouteDeviceTimestamp = nil
            lastRouteTransportType = nil
            hasAppliedInitialFetchRouteSync = false
            initialDistance = nil
            navigationStopped = false
            // Reset mutual navigation state
            isMutualNavigation = false
            // Restart mutual navigation detection for new device
            mutualNavigationDetector.startMonitoring(targetDeviceId: device.DeviceID, serverURL: settings.miataruServerURL)
            // Fetch and recenter for the new device
            Task { await fetchTargetDeviceLocation(resetAndRecenter: true) }
        }
    }

    private var baseMapView: some View {
        Map(position: $mapPosition, scope: mapScope) {
            if let coord = animatedUserCoordinate {
                Annotation("", coordinate: coord, anchor: .bottom) {
                    userMarkerContent
                }
            }
            if let coord = animatedDeviceCoordinate {
                Annotation("", coordinate: coord, anchor: .bottom) {
                    deviceMarkerContent
                }
            }
            if let route = route {
                // Directly reference isMutualNavigation to ensure Map content observes the state change
                // This allows the overlay polyline to be added/removed without reloading the entire map
                if shouldUseFocusedNavigationRouteRendering {
                    MapPolyline(route.polyline)
                        .stroke(RouteStyle.withoutRemaining, lineWidth: 4)
                    if isMutualNavigation, let mutualRouteOverlayPolyline {
                        MapPolyline(mutualRouteOverlayPolyline)
                            .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                    }
                } else if settings.showRouteProgress {
                    let knownSpeed = DeviceLocationCacheStore.shared.getLocation(for: device.DeviceID)?.speed
                    let userSpeed = locationManager.currentLocation?.speed
                    // ETA has passed when time since the route's start (timestamp used when route was calculated) is >= route ETA; then do not draw ghost. Require expectedTravelTime > 0 so short routes still show the ghost.
                    let routeStartTimestamp = isRouteFromDeviceToUser ? lastRouteDeviceTimestamp : lastRouteUserTimestamp
                    let etaHasPassed: Bool = {
                        guard route.expectedTravelTime > 0, let start = routeStartTimestamp else { return false }
                        return now.timeIntervalSince(start) >= route.expectedTravelTime
                    }()
                    if let (done, todo, ghost, progress) = RouteGhostCalculator.ghost(
                        for: route,
                        deviceCoordinate: deviceCoordinate,
                        userCoordinate: userCoordinate,
                        deviceTimestamp: deviceTimestamp,
                        knownDeviceSpeed: knownSpeed,
                        userTimestamp: userTimestamp,
                        knownUserSpeed: userSpeed,
                        now: now,
                        isRouteReversed: isRouteFromDeviceToUser
                    ) {
                        if progress <= minimumProgressToShowGhost {
                            MapPolyline(route.polyline)
                                .stroke(RouteStyle.remaining, lineWidth: 4)
                            if isMutualNavigation, let mutualRouteOverlayPolyline {
                                MapPolyline(mutualRouteOverlayPolyline)
                                    .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                            }
                        } else if progress >= 1 {
                            MapPolyline(route.polyline)
                                .stroke(RouteStyle.completed, lineWidth: 4)
                            if isMutualNavigation, let mutualRouteOverlayPolyline {
                                MapPolyline(mutualRouteOverlayPolyline)
                                    .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                            }
                        } else {
                            MapPolyline(done)
                                .stroke(RouteStyle.completed, lineWidth: 4)
                            MapPolyline(todo)
                                .stroke(RouteStyle.remaining, lineWidth: 4)
                            if isMutualNavigation {
                                MapPolyline(done)
                                    .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                                MapPolyline(todo)
                                    .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                            }
                            // Ghost is shown when: route is non-reversed (device→user), progress is in (0.05, 1), and ETA has not passed.
                            if isRouteFromDeviceToUser, !etaHasPassed {
                                MapCircle(center: ghost, radius: 50)
                                    .foregroundStyle(RouteStyle.completed.opacity(0.5))
                                Annotation("", coordinate: ghost) {
                                    VStack(spacing: 2) {
                                        Image(systemName: transportSymbolName())
                                            .font(.system(size: 16))
                                            .foregroundColor(Color.primary.opacity(0.9))
                                            .shadow(radius: 4)
                                        DeviceNameLabel(
                                            deviceName: device.DeviceName,
                                            deviceID: device.DeviceID,
                                            font: .caption2,
                                            opacity: 0.8
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        MapPolyline(route.polyline)
                            .stroke(RouteStyle.withoutRemaining, lineWidth: 4)
                        if isMutualNavigation, let mutualRouteOverlayPolyline {
                            MapPolyline(mutualRouteOverlayPolyline)
                                .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                        }
                    }
                } else {
                    MapPolyline(route.polyline)
                        .stroke(RouteStyle.withoutRemaining, lineWidth: 4)
                    if isMutualNavigation, let mutualRouteOverlayPolyline {
                        MapPolyline(mutualRouteOverlayPolyline)
                            .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                    }
                }
            }
        }
    }
    
    private var mapWithModifiers: some View {
        baseMapView
            .mapStyle(mapStyleFromSettings(settings.mapType))
            .mapControls {
                MapCompass(heading: 1, size: 10)
                    .mapControlVisibility(.hidden)
            }
            .ignoresSafeArea()
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in markUserInteraction() }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in markUserInteraction() }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { _ in markUserInteraction() }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { showChromeIfNeeded() }
            )
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded { handleMapDoubleTap() }
            )
            .onAppear {
                isViewActive = true
                navigationFeedbackGate.isViewActive = true
                navigationFeedbackGate.isRouteFromDeviceToUser = isRouteFromDeviceToUser
                navigationFeedbackGate.isNavigationMode = isNavigationMode
                Haptic.impactMedium()
                routeInfoState.isChromeVisible = isChromeVisible
                // Initial wiring on appear: sync settings, set coordinates, try cache, then fetch
                isAutoCenteringEnabled = true
                // Sync auto-update lock state with global setting on appear
                isAutoRouteUpdateLocked = settings.automaticRouteUpdateDuringNavigation
                // Provide cancel handler for bottom accessory (iOS 26)
                routeInfoState.onCancel = {
                    Haptic.impactMedium()
                    dismiss()
                }
                hasAppliedInitialFetchRouteSync = false
                updateCoordinates(recenter: true)
                // Record initial distance after coordinates are set
                recordInitialDistance()
                if !useCachedRouteIfValid() { // prefer cached route on appear
                    calculateRoute()
                }
                Task { await fetchTargetDeviceLocation(resetAndRecenter: false) }
                startAutoUpdate()
                updateBottomAccessory()
                // Start mutual navigation detection
                mutualNavigationDetector.startMonitoring(targetDeviceId: device.DeviceID, serverURL: settings.miataruServerURL)
                // Initialize mutual navigation state
                isMutualNavigation = mutualNavigationDetector.isMutualNavigation
            }
            .onReceive(locationManager.$currentLocation) { _ in
                updateCoordinates()
                checkAutoStopCondition()
                updateNavigationOverlayStep()
                updateLiveNavigationRouteSummary()
                hasLocationUpdateSinceLastAutoUpdate = true
            }
            .onReceive(cache.$locations) { _ in
                updateCoordinates()
                checkAutoStopCondition()
                updateNavigationOverlayStep()
                updateLiveNavigationRouteSummary()
                hasLocationUpdateSinceLastAutoUpdate = true
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { input in
                now = input
                updateLiveNavigationRouteSummary()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                guard isViewActive else { return }
                Task { await refreshNavigationAfterAppBecomesActive() }
            }
            .onDisappear {
                isViewActive = false
                navigationFeedbackGate.isViewActive = false
                navigationOverlayCancellables.removeAll()
                stopAutoUpdate()
                routeRetryTask?.cancel()
                routeRetryTask = nil
                routeInfoState.isChromeVisible = true
                // Hide accessory and remove cancel handler when leaving
                routeInfoState.hide()
                routeInfoState.onCancel = nil
                // Stop mutual navigation detection
                mutualNavigationDetector.stopMonitoring()
            }
            .onChange(of: settings.mapUpdateInterval) {
                restartAutoUpdate()
            }
            .onChange(of: settings.automaticRouteUpdateDuringNavigation) { _, newValue in
                // Keep UI and behavior in sync with the global setting
                isAutoRouteUpdateLocked = newValue
            }
            .onChange(of: locationManager.isNetworkAvailable) { _, isAvailable in
                guard isAvailable, pendingRouteRetryOnReconnect else { return }
                pendingRouteRetryOnReconnect = false
                calculateRoute(ignoreCache: true)
            }
            .onChange(of: settings.navigationTransportType) { _, _ in
                if !useCachedRouteIfValid() {
                    calculateRoute()
                }
            }
            .onChange(of: isRouteFromDeviceToUser) { _, newValue in
                navigationFeedbackGate.isRouteFromDeviceToUser = newValue
                // Reversed route = user→device; non-reversed = device→user. Toggle swaps direction.
                // Clear route and overlay immediately when route direction changes to prevent showing stale route data
                // The route will be recalculated and overlay refreshed when the new route is calculated
                setRouteForRendering(nil)
                travelTime = nil
                distanceText = nil
                navigationOverlayViewModel = nil
                navigationOverlayCancellables.removeAll()
                lastOverlayStepIndex = nil
                isFollowDeviceHeadingMode = false
                isNavigationMode = false
                shouldPerformInitialNavigationZoom = false
            }
            .onChange(of: travelTime) { _, _ in
                now = Date()
                updateBottomAccessory()
            }
            .onChange(of: distanceText) { _, _ in
                updateBottomAccessory()
            }
            .onChange(of: isNavigationMode) { _, newValue in
                navigationFeedbackGate.isNavigationMode = newValue
                if newValue {
                    updateLiveNavigationRouteSummary()
                } else {
                    applyStaticRouteSummaryFromCurrentRoute()
                }
            }
            .onChange(of: mutualNavigationDetector.isMutualNavigation) { _, newValue in
                isMutualNavigation = newValue
                updateBottomAccessory()
                guard isViewActive else { return }
                if newValue {
                    SoundEffectPlayer.shared.play(named: mutualNavigationOnSoundName, fileExtension: "caf")
                } else {
                    SoundEffectPlayer.shared.play(named: mutualNavigationOffSoundName, fileExtension: "caf")
                }
                Haptic.impactMedium()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                // Track camera state changes to detect user rotation and keep a compass affordance
                let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
                if isProgrammaticCameraChange {
                    isProgrammaticCameraChange = false
                }
                let now = Date()
                let isSuppressed = suppressUserCameraChangeDetectionUntil.map { now < $0 } ?? false
                if !isSuppressed {
                    suppressUserCameraChangeDetectionUntil = nil
                    if isFollowDeviceHeadingMode || isNavigationMode {
                        followCameraDistanceOverride = context.camera.distance
                        isFollowAutoZoomEnabled = false
                    }
                    // User interaction is detected via gestures; here we only deduce rotation state
                    if abs(context.camera.heading) < 0.1 {
                        userHasRotatedMap = false
                    } else if headingChanged {
                        userHasRotatedMap = true
                    }
                }
                currentMapHeadingDegrees = context.camera.heading
                currentMapCamera = context.camera
                currentRegion = context.region
            }
            .overlay(alignment: .top) {
                topOverlayStack
            }
            .overlay(alignment: .bottomTrailing) {
                scaleBarView()
            }
            .overlay(alignment: .topTrailing) {
                compassView()
            }
    }
    
    @ViewBuilder
    private var topOverlayStack: some View {
        VStack(spacing: 8) {
            navigationOverlayContent
            topOverlayContent
        }
    }

    @ViewBuilder
    private var navigationOverlayContent: some View {
        // Navigation overlay (turn-by-turn) only for reversed route (user → device).
        if let navigationOverlayViewModel, !isRouteFromDeviceToUser, route != nil {
            NavigationOverlayView(viewModel: navigationOverlayViewModel, alignment: .top)
                .padding(.top, isChromeVisible ? -12 : -24)
                .contentShape(Rectangle())
                .onTapGesture { toggleChromeVisibility() }
        }
    }

    @ViewBuilder
    private var topOverlayContent: some View {
        if travelTime != nil || distanceText != nil {
            if #available(iOS 26.0, *) {
                // Use bottom accessory on iOS 26; no top overlay
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    if let travelTime {
                        Image(systemName: "clock")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(travelTime)
                    }
                    if travelTime != nil && distanceText != nil {
                        Image(systemName: transportSymbolName())
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    if let distanceText {
                        let baseText = distanceText
                        let mutualSuffix = mutualNavigationDetector.isMutualNavigation ? " - \(NSLocalizedString("mutual_navigation_active", comment: "Indicates that both devices are actively navigating to each other"))" : ""
                        Text(baseText + mutualSuffix)
                    }
                }
                .font(.callout.monospacedDigit())
                .padding(8)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
            }
        }
    }
    
    
    @ViewBuilder
    private var userMarkerContent: some View {
        let myDevice = deviceStore.devices.first { $0.DeviceID == thisDeviceIDManager.shared.deviceID }
        // User heading only when reversed route (user→device) and in focussed navigation.
        if !isRouteFromDeviceToUser && (isNavigationMode || isFollowDeviceHeadingMode) {
            UserHeadingAnnotationView(
                heading: locationManager.userHeading,
                isHeadingValid: locationManager.isHeadingValid,
                mapHeading: currentMapHeadingDegrees
            )
        } else {
            ZStack {
                // Pulsing behind everything for user marker
                if settings.pulsingMapMarkers {
                    let circleDiameter = (/* marker height */ 40.0) * 0.65
                    let pulsingSize = circleDiameter * 1.5
                    let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                    PulsingAccuracyCircle(pulsingColor: Color(myDevice?.DeviceColor ?? UIColor.systemBlue), size: pulsingSize)
                        .offset(y: pulsingOffset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 0) {
                    if let ts = userTimestamp {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let timeString = relativeTimeString(from: ts, to: context.date)
                            let timezoneOffset = timezoneOffsetString(deviceTimeZone: cache.getTimeZone(for: thisDeviceIDManager.shared.deviceID))
                            let baseText = timezoneOffset != nil ? "\(timeString) (\(timezoneOffset!))" : timeString
                            let speedText = settings.showCurrentSpeedOnMap
                                ? mapSpeedLabelText(speedMetersPerSecond: cache.getLocation(for: thisDeviceIDManager.shared.deviceID)?.speed)
                                : nil
                            let displayText = speedText != nil ? "\(baseText) • \(speedText!)" : baseText
                            Text(displayText)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                )
                                .shimmering(active: settings.pulsingMapMarkers && isLoading)
                                .shadow(radius: 2)
                                .zIndex(2)
                        }
                    }
                    // Device name label above the marker for clarity
                    DeviceNameLabel(
                        deviceName: myDevice?.DeviceName ?? "",
                        deviceID: thisDeviceIDManager.shared.deviceID
                    )
                    MiataruMapMarker(color: Color(myDevice?.DeviceColor ?? UIColor.systemBlue))
                        .shadow(radius: 2)
                }
                Rectangle()
                    .foregroundColor(.clear)
                    .contentShape(Rectangle())
                    .frame(width: 80, height: 120)
                    .offset(y: 12)
                    .zIndex(1)
            }
            .offset(y: 35)
        }
    }
    
    @ViewBuilder
    private var deviceMarkerContent: some View {
        ZStack {
            // Pulsing behind everything for target device marker
            if settings.pulsingMapMarkers {
                let circleDiameter = (/* marker height */ 40.0) * 0.65
                let pulsingSize = circleDiameter * 1.5
                let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                PulsingAccuracyCircle(pulsingColor: Color(device.DeviceColor ?? .red), size: pulsingSize)
                    .offset(y: pulsingOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                if let timestamp = deviceTimestamp {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let timeString = relativeTimeString(from: timestamp, to: context.date)
                        let timezoneOffset = timezoneOffsetString(deviceTimeZone: cache.getTimeZone(for: device.DeviceID))
                        let baseText = timezoneOffset != nil ? "\(timeString) (\(timezoneOffset!))" : timeString
                        let speedText = settings.showCurrentSpeedOnMap
                            ? mapSpeedLabelText(speedMetersPerSecond: cache.getLocation(for: device.DeviceID)?.speed)
                            : nil
                        let displayText = speedText != nil ? "\(baseText) • \(speedText!)" : baseText
                        Text(displayText)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                            .shimmering(active: settings.pulsingMapMarkers && isLoading)
                            .shadow(radius: 2)
                            .zIndex(2)
                    }
                }
                // Device name label above the marker for clarity
                DeviceNameLabel(deviceName: device.DeviceName, deviceID: device.DeviceID)
                MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                    .shadow(radius: 2)
            }
            Rectangle()
                .foregroundColor(.clear)
                .contentShape(Rectangle())
                .frame(width: 80, height: 120)
                .offset(y: 12)
                .zIndex(1)
        }
        .offset(y: 35)
    }
    

    @ViewBuilder
    private func directionIndicatorIcon() -> some View {
        // Two-colored arrow icon using palette rendering mode
        // Non-reversed (device→user): top arrow accent, bottom primary. Reversed (user→device): top primary, bottom accent.
        Image(systemName: "arrow.up.arrow.down")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isRouteFromDeviceToUser ? Color.green : Color.primary,
                isRouteFromDeviceToUser ? Color.primary : Color.green
            )
    }
    
    @ViewBuilder
    private func reloadToolbarButton() -> some View {
        // Toolbar button to reload target device location; long-press toggles auto route updates
        ZStack(alignment: .topTrailing) {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(isAutoRouteUpdateLocked ? Color.green : Color.primary)
                .symbolEffect(.rotate.clockwise.byLayer, options: .nonRepeating, isActive: isUpdating)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if animationsAllowed {
                        withAnimation { isUpdating = true }
                    } else {
                        isUpdating = true
                    }
                    Task {
                        await fetchTargetDeviceLocation(resetAndRecenter: true, ignoreRouteCache: true)
                        if animationsAllowed {
                            withAnimation { isUpdating = false }
                        } else {
                            isUpdating = false
                        }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    // Toggle global setting for automatic route updates while navigating
                    settings.automaticRouteUpdateDuringNavigation.toggle()
                    isAutoRouteUpdateLocked = settings.automaticRouteUpdateDuringNavigation
                    if settings.automaticRouteUpdateDuringNavigation {
                        Haptic.notifySuccess()
                        calculateRoute()
                    } else {
                        Haptic.notifyWarning()
                    }
                }
                .accessibilityLabel(Text(NSLocalizedString("reload", comment: "Reload target device location")))
                .accessibilityHint(Text(NSLocalizedString("reload_longpress_hint", comment: "Long-press to toggle automatic route updates.")))
        }
        .animation(animationsAllowed ? .easeInOut(duration: 0.2) : nil, value: isAutoRouteUpdateLocked)
        .accessibilityAddTraits(.isButton)
    }

    private func updateCoordinates(recenter: Bool = false) {
        // Update user and device coordinates from current sources (LocationManager + cache)
        // Optionally recenter the map if auto-centering is enabled or explicitly requested
        if let loc = locationManager.currentLocation {
            let coord = loc.coordinate
            let changed = userCoordinate?.latitude != coord.latitude || userCoordinate?.longitude != coord.longitude
            userCoordinate = coord
            userTimestamp = loc.timestamp
            if changed || animatedUserCoordinate == nil {
                if animationsAllowed {
                    withAnimation { animatedUserCoordinate = coord }
                } else {
                    animatedUserCoordinate = coord
                }
            }
        }
        if let cached = cache.getLocation(for: device.DeviceID) {
            let coord = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            let changed = deviceCoordinate?.latitude != coord.latitude || deviceCoordinate?.longitude != coord.longitude
            deviceCoordinate = coord
            if changed || animatedDeviceCoordinate == nil {
                if animationsAllowed {
                    withAnimation { animatedDeviceCoordinate = coord }
                } else {
                    animatedDeviceCoordinate = coord
                }
            }
        }
        // In navigation mode, always update camera smoothly
        if isNavigationMode, let _ = userCoordinate {
            updateFollowCamera(animated: true)
            hasSetInitialRegion = true
            return
        }
        
        if let user = userCoordinate, let dest = deviceCoordinate,
           (!hasSetInitialRegion || recenter || isAutoCenteringEnabled) {
            if isFollowDeviceHeadingMode {
                updateFollowCamera(animated: true)
                hasSetInitialRegion = true
                return
            }
            let region = regionThatFits(user: user, dest: dest)
            beginProgrammaticCameraChangeSuppression()
            if animationsAllowed {
                withAnimation {
                    mapPosition = .region(region)
                }
            } else {
                mapPosition = .region(region)
            }
            hasSetInitialRegion = true
        }
    }

    private func regionThatFits(user: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> MKCoordinateRegion {
        // Compute a region that fits both points with padding and minimum span to avoid over-zooming
        let center = CLLocationCoordinate2D(latitude: (user.latitude + dest.latitude) / 2,
                                            longitude: (user.longitude + dest.longitude) / 2)
        let baseLat = abs(user.latitude - dest.latitude)
        let baseLon = abs(user.longitude - dest.longitude)
        let paddedLat = max(baseLat * fitPaddingMultiplier, fitMinimumSpan.latitudeDelta)
        let paddedLon = max(baseLon * fitPaddingMultiplier, fitMinimumSpan.longitudeDelta)
        let span = MKCoordinateSpan(latitudeDelta: paddedLat, longitudeDelta: paddedLon)
        return MKCoordinateRegion(center: center, span: span)
    }

    private func calculateRoute(ignoreCache: Bool = false, retryAttempt: Int = 0) {
        // Calculate a new route between user and selected device.
        // Prefers a cached route when movement < 100m; applies a daily network request limit.
        guard let user = userCoordinate, let device = deviceCoordinate else { return }
        if retryAttempt == 0 {
            routeRetryTask?.cancel()
            routeRetryTask = nil
            pendingRouteRetryOnReconnect = false
        }
        // Try to reuse cached route first unless explicitly told to ignore cache
        if !ignoreCache {
            if useCachedRouteIfValid() { return }
            // Only recalc when one of the positions changed since the last route calculation (or if there's no route yet)
            let userTimestampChanged = userTimestamp != lastRouteUserTimestamp
            let deviceTimestampChanged = deviceTimestamp != lastRouteDeviceTimestamp
            var userCoordinatesChanged = true
            if let lastUser = lastRouteUserCoordinate {
                userCoordinatesChanged = (lastUser.latitude != user.latitude) || (lastUser.longitude != user.longitude)
            }
            var deviceCoordinatesChanged = true
            if let lastDevice = lastRouteDeviceCoordinate {
                deviceCoordinatesChanged = (lastDevice.latitude != device.latitude) || (lastDevice.longitude != device.longitude)
            }
            let transportTypeChanged = settings.navigationTransportType != lastRouteTransportType
            let shouldRecalculate = (route == nil) || userTimestampChanged || deviceTimestampChanged || userCoordinatesChanged || deviceCoordinatesChanged || transportTypeChanged
            if !shouldRecalculate { return }
        }

        // Enforce daily limit through centralized counter with calendar-day reset
        routeCounter.checkAndResetIfNeeded()
        guard routeCounter.count < routeRequestDailyLimit else {
            showErrorOverlay(
                "Daily route request limit reached",
                NSLocalizedString("route_request_limit_reached", comment: "Daily route request limit reached. Try again tomorrow.")
            )
            return
        }
        _ = routeCounter.canRequestAndIncrement(limit: routeRequestDailyLimit)
        let request = MKDirections.Request()
        // Non-reversed (device→user): source=device, dest=user. Reversed (user→device): source=user, dest=device.
        if isRouteFromDeviceToUser {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: device))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: user))
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: user))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: device))
        }
        request.transportType = transportTypeFromSetting(settings.navigationTransportType)
        let hadRouteBeforeRecalculation = route != nil
        Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                if let first = response.routes.first {
                    setRouteForRendering(first)
                    applyStaticRouteSummary(for: first)
                    // Refresh overlay with new route - this ensures overlay matches the route direction
                    refreshNavigationOverlayForCurrentRoute()
                    // Remember inputs used for this route calculation
                    lastRouteUserCoordinate = user
                    lastRouteDeviceCoordinate = device
                    lastRouteUserTimestamp = userTimestamp
                    lastRouteDeviceTimestamp = deviceTimestamp
                    lastRouteTransportType = settings.navigationTransportType
                    // Store in cache for reuse
                    routeCache.set(
                        for: self.device.DeviceID,
                        transportType: settings.navigationTransportType,
                        isRouteReversed: isRouteFromDeviceToUser,
                        route: first,
                        userCoordinate: user,
                        deviceCoordinate: device,
                        userTimestamp: userTimestamp,
                        deviceTimestamp: deviceTimestamp
                    )
                } else {
                    if !hadRouteBeforeRecalculation {
                        setRouteForRendering(nil)
                        travelTime = nil
                        distanceText = nil
                        lastRouteTransportType = nil
                        refreshNavigationOverlayForCurrentRoute()
                    }
                    handleRouteRetry(noRouteFound: true, error: nil, ignoreCache: true, retryAttempt: retryAttempt)
                }
            } catch {
                if !hadRouteBeforeRecalculation {
                    setRouteForRendering(nil)
                    travelTime = nil
                    distanceText = nil
                    lastRouteTransportType = nil
                    refreshNavigationOverlayForCurrentRoute()
                }
                handleRouteRetry(noRouteFound: false, error: error, ignoreCache: true, retryAttempt: retryAttempt)
            }
        }
    }

    private func handleRouteRetry(noRouteFound: Bool, error: Error?, ignoreCache: Bool, retryAttempt: Int) {
        let nextAttempt = retryAttempt + 1
        if !locationManager.isNetworkAvailable {
            pendingRouteRetryOnReconnect = true
            showErrorOverlay(
                "Route request failed while offline",
                NSLocalizedString("network_error", comment: "Network error. Please check your internet connection.")
            )
            return
        }

        guard nextAttempt <= maxRouteRetryAttempts else {
            if noRouteFound {
                showErrorOverlay(
                    "No route found after retries",
                    NSLocalizedString("route_not_found", comment: "Could not generate a route between the locations.")
                )
            } else {
                showErrorOverlay(
                    "Route calculation failed after retries: \(error?.localizedDescription ?? "unknown error")",
                    NSLocalizedString("route_generation_failed", comment: "Route calculation failed. Please try again.")
                )
            }
            return
        }

        guard noRouteFound || isRetryableRouteError(error) else {
            showErrorOverlay(
                "Route calculation failed: \(error?.localizedDescription ?? "unknown error")",
                NSLocalizedString("route_generation_failed", comment: "Route calculation failed. Please try again.")
            )
            return
        }

        let backoffSeconds = UInt64(pow(2.0, Double(nextAttempt - 1)))
        routeRetryTask?.cancel()
        routeRetryTask = Task {
            try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
            guard !Task.isCancelled, isViewActive else { return }
            if !locationManager.isNetworkAvailable {
                pendingRouteRetryOnReconnect = true
                return
            }
            calculateRoute(ignoreCache: ignoreCache, retryAttempt: nextAttempt)
        }
    }

    private func isRetryableRouteError(_ error: Error?) -> Bool {
        guard let error else { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        if let mkError = error as? MKError {
            switch mkError.code {
            case .directionsNotFound, .serverFailure, .loadingThrottled:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func openInAppleMaps() {
        // Open the route in the Apple Maps app using the selected transport type
        guard let dest = deviceCoordinate else { return }
        let source: MKMapItem
        let destination: MKMapItem
        // Non-reversed (device→user): open device→user. Reversed (user→device): open user→device.
        if isRouteFromDeviceToUser {
            source = MKMapItem(placemark: MKPlacemark(coordinate: dest))
            source.name = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
            destination = MKMapItem.forCurrentLocation()
        } else {
            source = MKMapItem.forCurrentLocation()
            destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
            destination.name = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
        }
        var options: [String: Any] = [:]
        switch settings.navigationTransportType {
        case 0: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeWalking
        case 3: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeTransit
        default: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDriving
        }
        MKMapItem.openMaps(with: [source, destination], launchOptions: options)
    }

    private func transportTypeFromSetting(_ value: Int) -> MKDirectionsTransportType {
        switch value {
        case 0: return .walking
        case 3: return .transit
        default: return .automobile
        }
    }

    private func showErrorOverlay(_ debugMessage: String, _ userMessage: String) {
        debugLog("Error: \(debugMessage)")
        errorOverlayManager.show(message: userMessage, animationsAllowed: animationsAllowed)
    }

    // MARK: - Remote updates for the selected device only

    private func fetchTargetDeviceLocation(resetAndRecenter: Bool, ignoreRouteCache: Bool = false) async {
        // Fetch latest location for just the selected device from the server.
        // Updates the shared device cache and view state. Recalculates route only
        // when explicitly re-centered (e.g., manual reload) or when auto-update logic decides so.
        guard let url = URL(string: settings.miataruServerURL) else { return }
        do {
            isLoading = true
            defer { isLoading = false }
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [device.DeviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: settings.deviceKey
            )
            if let loc = locations.first {
                let coordinate = CLLocationCoordinate2D(latitude: loc.Latitude, longitude: loc.Longitude)
                let changed = deviceCoordinate?.latitude != coordinate.latitude || deviceCoordinate?.longitude != coordinate.longitude
                // Update cache first to keep consistency with the rest of the app
                DeviceLocationCacheStore.shared.setLocation(
                    for: device.DeviceID,
                    latitude: loc.Latitude,
                    longitude: loc.Longitude,
                    accuracy: loc.HorizontalAccuracy,
                    timestamp: loc.TimestampDate,
                    batteryLevel: loc.BatteryLevel,
                    altitude: loc.Altitude
                )
                deviceCoordinate = coordinate
                deviceTimestamp = loc.TimestampDate
                if changed || animatedDeviceCoordinate == nil {
                    if animationsAllowed {
                        withAnimation { animatedDeviceCoordinate = coordinate }
                    } else {
                        animatedDeviceCoordinate = coordinate
                    }
                }
                // Always update coordinates to allow auto-centering when enabled
                updateCoordinates(recenter: resetAndRecenter)
                // Record initial distance if not yet recorded (after first successful fetch)
                if initialDistance == nil {
                    recordInitialDistance()
                }
                // One-time sync: if initial route was calculated from stale cache,
                // refresh it after the first successful fetch updates device location.
                if !resetAndRecenter, !hasAppliedInitialFetchRouteSync, route != nil {
                    let coordChanged = (lastRouteDeviceCoordinate?.latitude != coordinate.latitude)
                        || (lastRouteDeviceCoordinate?.longitude != coordinate.longitude)
                    let timestampChanged = lastRouteDeviceTimestamp != loc.TimestampDate
                    if coordChanged || timestampChanged {
                        hasAppliedInitialFetchRouteSync = true
                        calculateRoute(ignoreCache: true)
                        return
                    }
                    hasAppliedInitialFetchRouteSync = true
                }
                // Recalculate route only on explicit reload (or initial load elsewhere) 
                if resetAndRecenter {
                    if ignoreRouteCache {
                        calculateRoute(ignoreCache: true)
                    } else {
                        if !useCachedRouteIfValid() {
                            calculateRoute()
                        }
                    }
                }
            } else {
                DeviceLocationCacheStore.shared.removeLocation(for: device.DeviceID)
            }
        } catch {
            debugLog("[iPhone_DeviceNavigationView] fetchTargetDeviceLocation error: \(error)")
        }
    }

    private func startAutoUpdate() {
        // Start periodic refresh based on user settings. If auto-route updates are enabled
        // and the user is off-route, we refresh the route, preferring cache.
        stopAutoUpdate()
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    await fetchTargetDeviceLocation(resetAndRecenter: false)
                    if !hasLocationUpdateSinceLastAutoUpdate {
                        checkAutoStopCondition()
                        return
                    }
                    hasLocationUpdateSinceLastAutoUpdate = false
                    if isAutoRouteUpdateLocked && isUserOffRoute(threshold: offRouteThreshold) {
                        if !useCachedRouteIfValid() {
                            calculateRoute()
                        }
                    }
                    // Check if devices are close enough to auto-stop navigation
                    checkAutoStopCondition()
                }
            }
    }

    private func isUserOffRoute(threshold: CLLocationDistance? = nil) -> Bool {
        guard let route, let user = userCoordinate else { return false }
        let limit = threshold ?? offRouteThreshold
        let polyline = route.polyline
        guard polyline.pointCount > 1 else { return false }

        let userPoint = MKMapPoint(user)
        let points = polyline.points()
        var minDistance = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(polyline.pointCount - 1) {
            let distance = distanceFromPoint(userPoint, toSegmentStart: points[index], end: points[index + 1])
            minDistance = min(minDistance, distance)
            if minDistance <= limit {
                return false
            }
        }
        return minDistance > limit
    }

    private func distanceFromPoint(_ point: MKMapPoint, toSegmentStart start: MKMapPoint, end: MKMapPoint) -> CLLocationDistance {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return point.distance(to: start)
        }
        let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let clamped = max(0, min(1, t))
        let projection = MKMapPoint(x: start.x + clamped * dx, y: start.y + clamped * dy)
        return point.distance(to: projection)
    }

    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func setRouteForRendering(_ newRoute: MKRoute?) {
        route = newRoute
        guard let newRoute else {
            mutualRouteOverlayPolyline = nil
            return
        }
        let sourcePolyline = newRoute.polyline
        guard sourcePolyline.pointCount > 0 else {
            mutualRouteOverlayPolyline = nil
            return
        }
        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: sourcePolyline.pointCount
        )
        sourcePolyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: sourcePolyline.pointCount)
        )
        mutualRouteOverlayPolyline = MKPolyline(
            coordinates: coordinates,
            count: coordinates.count
        )
    }

    @MainActor
    private func refreshNavigationAfterAppBecomesActive() async {
        // Ensure periodic updates are alive after background suspension and refresh once immediately.
        restartAutoUpdate()
        await fetchTargetDeviceLocation(resetAndRecenter: false)
        // Do not resurrect navigation after automatic stop; keep map-only state as-is.
        guard !navigationStopped else { return }
        // Keep the last known route while offline; retry is handled elsewhere on reconnect.
        guard locationManager.isNetworkAvailable else { return }
        calculateRoute(ignoreCache: true)
    }

    private func restartAutoUpdate() {
        startAutoUpdate()
    }

    // Removed: restartTimeUpdateTimer(). We now use an inline Timer publisher directly in .onReceive for per-second updates.

    // MARK: - Map UI Helpers (Scale bar and Compass)

    private func markUserInteraction() {
        if isFollowDeviceHeadingMode {
            if let currentDistance = currentMapCamera?.distance {
                followCameraDistanceOverride = currentDistance
                isFollowAutoZoomEnabled = false
            }
            return
        }
        userHasInteractedWithMap = true
        isAutoCenteringEnabled = false
    }

    private func beginProgrammaticCameraChangeSuppression(duration: TimeInterval = 0.9) {
        isProgrammaticCameraChange = true
        suppressUserCameraChangeDetectionUntil = Date().addingTimeInterval(duration)
    }

    private func hideChromeIfNeeded() {
        setChromeVisible(false)
    }

    private func showChromeIfNeeded() {
        setChromeVisible(true)
    }

    private func toggleChromeVisibility() {
        setChromeVisible(!isChromeVisible)
    }

    private func setChromeVisible(_ isVisible: Bool) {
        guard isChromeVisible != isVisible else { return }
        if animationsAllowed {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChromeVisible = isVisible
            }
        } else {
            isChromeVisible = isVisible
        }
        routeInfoState.isChromeVisible = isVisible
    }

    @ViewBuilder
    private func scaleBarView() -> some View {
        Group {
            if let region = currentRegion {
                let bottomPadding: CGFloat = isChromeVisible ? 2 : 0
                Button(action: {
                    isAutoCenteringEnabled = true
                    if isFollowDeviceHeadingMode {
                        followCameraDistanceOverride = nil
                        isFollowAutoZoomEnabled = true
                        updateFollowCamera(animated: true, force: true)
                    } else {
                        resetZoomToFitBoth()
                    }
                }) {
                    MapScaleBar(region: region, width: 50)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, bottomPadding)
                .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private func compassView() -> some View {
        Group {
            if userHasRotatedMap && !isNavigationMode && !isFollowDeviceHeadingMode {
                let heading = currentMapCamera?.heading ?? 0
                Button(action: {
                    isAutoCenteringEnabled = true
                    alignMapToNorth()
                }) {
                    MapCompass(heading: heading, size: 40)
                }
                .padding([.top, .trailing], 10)
                .zIndex(3)
                .transition(animationsAllowed ? .opacity : .identity)
            }
        }
        .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: userHasRotatedMap)
    }

    private func alignMapToNorth() {
        // Reset map heading to 0 while preserving other camera properties
        guard let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: currentCamera.centerCoordinate,
            distance: currentCamera.distance,
            heading: 0,
            pitch: currentCamera.pitch
        )
        beginProgrammaticCameraChangeSuppression()
        if animationsAllowed {
            withAnimation {
                mapPosition = .camera(newCamera)
                userHasRotatedMap = false
            }
        } else {
            mapPosition = .camera(newCamera)
            userHasRotatedMap = false
        }
    }

    private func resetZoomToFitBoth() {
        // Smoothly zoom to a region that fits both user and device
        if let user = userCoordinate, let dest = deviceCoordinate {
            let region = regionThatFits(user: user, dest: dest)
            beginProgrammaticCameraChangeSuppression()
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    mapPosition = .region(region)
                }
            } else {
                mapPosition = .region(region)
            }
        }
    }

    private func resetZoomToFitRouteOrBoth() {
        if let routeRegion = regionThatFitsRoute() {
            beginProgrammaticCameraChangeSuppression()
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    mapPosition = .region(routeRegion)
                }
            } else {
                mapPosition = .region(routeRegion)
            }
            return
        }
        resetZoomToFitBoth()
    }

    private func handleMapDoubleTap() {
        // Double-tap to focus on user device only when route is reversed (user → selected device).
        guard !isRouteFromDeviceToUser else { return }
        // Behave like a tap on the navigation overlay: hide chrome for full-screen focussed navigation.
        hideChromeIfNeeded()
        if isNavigationMode {
            disableNavigationMode()
        } else {
            enableNavigationMode()
        }
    }

    private func enableFollowDeviceHeadingMode() {
        isFollowDeviceHeadingMode = true
        isAutoCenteringEnabled = true
        lastFollowCameraUpdate = nil
        lastFollowCameraCenter = nil
        lastFollowCameraHeading = nil
        lastFollowCameraDistance = nil
        followCameraDistanceOverride = nil
        isFollowAutoZoomEnabled = true
        updateFollowCamera(animated: true, force: true)
    }

    private func disableFollowDeviceHeadingMode() {
        isFollowDeviceHeadingMode = false
        isAutoCenteringEnabled = true
        lastFollowCameraUpdate = nil
        lastFollowCameraCenter = nil
        lastFollowCameraHeading = nil
        lastFollowCameraDistance = nil
        followCameraDistanceOverride = nil
        isFollowAutoZoomEnabled = true
        showChromeIfNeeded()
        resetZoomToFitRouteOrBoth()
    }

    private func enableNavigationMode() {
        isNavigationMode = true
        isAutoCenteringEnabled = true
        lastFollowCameraUpdate = nil
        lastFollowCameraCenter = nil
        lastFollowCameraHeading = nil
        lastFollowCameraDistance = nil
        followCameraDistanceOverride = nil
        isFollowAutoZoomEnabled = true
        if let routeRegion = regionThatFitsRoute() {
            beginProgrammaticCameraChangeSuppression()
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.35)) {
                    mapPosition = .region(routeRegion)
                }
            } else {
                mapPosition = .region(routeRegion)
            }
            shouldPerformInitialNavigationZoom = true
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    if shouldPerformInitialNavigationZoom && isNavigationMode {
                        performInitialNavigationZoom()
                    }
                }
            }
        } else {
            shouldPerformInitialNavigationZoom = false
            updateFollowCamera(animated: true, force: true)
        }
    }

    private func disableNavigationMode() {
        isNavigationMode = false
        isAutoCenteringEnabled = true
        lastFollowCameraUpdate = nil
        lastFollowCameraCenter = nil
        lastFollowCameraHeading = nil
        lastFollowCameraDistance = nil
        followCameraDistanceOverride = nil
        isFollowAutoZoomEnabled = true
        shouldPerformInitialNavigationZoom = false
        showChromeIfNeeded()
        resetZoomToFitRouteOrBoth()
    }

    private func updateFollowCamera(animated: Bool, force: Bool = false) {
        guard !shouldPerformInitialNavigationZoom else { return }
        guard let user = userCoordinate else { return }
        let currentDistance = currentMapCamera?.distance ?? followCameraDistance
        let desiredDistance = isFollowAutoZoomEnabled ? followCameraDistanceForNextStep() : nil
        let speedKmh = currentSpeedKmh()
        let minimumDistance = minimumFollowCameraDistance(speedKmh: speedKmh)
        let distance = max(
            minimumDistance,
            min(followCameraDistanceOverride ?? desiredDistance ?? currentDistance, followCameraMaxDistance)
        )
        let pitch = currentMapCamera?.pitch ?? 0
        let heading = currentFollowHeading()
        let center = followCameraCenter(for: user, heading: heading, cameraDistance: distance, speedKmh: speedKmh)
        guard shouldUpdateFollowCamera(center: center, heading: heading, distance: distance, force: force) else { return }
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: heading,
            pitch: pitch
        )
        beginProgrammaticCameraChangeSuppression()
        if animated && animationsAllowed {
            withAnimation(.easeInOut(duration: 0.35)) {
                mapPosition = .camera(newCamera)
            }
        } else {
            mapPosition = .camera(newCamera)
        }
    }

    private func performInitialNavigationZoom() {
        guard let user = userCoordinate else { return }
        let speedKmh = currentSpeedKmh()
        let minimumDistance = minimumFollowCameraDistance(speedKmh: speedKmh)
        let distance = max(minimumDistance, followCameraDistanceForNextStep() ?? followCameraDistance)
        let pitch = currentMapCamera?.pitch ?? 0
        let heading = currentFollowHeading()
        let center = followCameraCenter(for: user, heading: heading, cameraDistance: distance, speedKmh: speedKmh)
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: distance,
            heading: heading,
            pitch: pitch
        )
        beginProgrammaticCameraChangeSuppression()
        if animationsAllowed {
            withAnimation(.easeInOut(duration: 0.35)) {
                mapPosition = .camera(newCamera)
            }
        } else {
            mapPosition = .camera(newCamera)
        }
        shouldPerformInitialNavigationZoom = false
    }

    private func currentFollowHeading() -> CLLocationDirection {
        if isNavigationMode, let heading = locationManager.userHeading {
            return heading
        }
        if let course = locationManager.currentLocation?.course, course >= 0 {
            return course
        }
        return currentMapCamera?.heading ?? 0
    }

    private func currentSpeedKmh() -> CLLocationSpeed? {
        guard let speed = locationManager.currentLocation?.speed, speed >= 0 else { return nil }
        return speed * 3.6
    }

    private func minimumFollowCameraDistance(speedKmh: CLLocationSpeed?) -> CLLocationDistance {
        guard isNavigationMode else { return followCameraMinDistance }
        guard let speedKmh else { return followCameraMinDistance }
        if speedKmh >= navigationSpeedZoomThresholdKmh {
            return max(followCameraMinDistance, navigationHighSpeedMinCameraDistance)
        }
        if speedKmh >= 10 {
            return max(followCameraMinDistance, navigationMediumSpeedMinCameraDistance)
        }
        return followCameraMinDistance
    }

    private func followCameraCenter(
        for user: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        cameraDistance: CLLocationDistance,
        speedKmh: CLLocationSpeed?
    ) -> CLLocationCoordinate2D {
        guard isNavigationMode || isFollowDeviceHeadingMode else { return user }
        let baseLookAhead = cameraDistance * 0.28
        let speedBoost: CLLocationDistance
        if let speedKmh, speedKmh >= navigationSpeedZoomThresholdKmh {
            speedBoost = min(180, (speedKmh - navigationSpeedZoomThresholdKmh) * 6)
        } else {
            speedBoost = 0
        }
        let lookAhead = max(
            navigationLookAheadMinDistance,
            min(baseLookAhead + speedBoost, navigationLookAheadMaxDistance)
        )
        return coordinate(from: user, heading: heading, distanceMeters: lookAhead)
    }

    private func coordinate(
        from origin: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        distanceMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard distanceMeters > 0 else { return origin }
        let earthRadiusMeters = 6_378_137.0
        let angularDistance = distanceMeters / earthRadiusMeters
        let bearing = heading * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180

        let lat2 = asin(
            sin(lat1) * cos(angularDistance)
                + cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        var lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )
        lon2 = (lon2 + 3 * .pi).truncatingRemainder(dividingBy: 2 * .pi) - .pi
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func shouldUpdateFollowCamera(
        center: CLLocationCoordinate2D,
        heading: CLLocationDirection,
        distance: CLLocationDistance,
        force: Bool
    ) -> Bool {
        let now = Date()
        if force {
            lastFollowCameraUpdate = now
            lastFollowCameraCenter = center
            lastFollowCameraHeading = heading
            lastFollowCameraDistance = distance
            return true
        }
        if let lastTime = lastFollowCameraUpdate, now.timeIntervalSince(lastTime) < followUpdateMinInterval {
            return false
        }
        var shouldUpdate = false
        if let lastCenter = lastFollowCameraCenter {
            let lastLocation = CLLocation(latitude: lastCenter.latitude, longitude: lastCenter.longitude)
            let newLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let distance = newLocation.distance(from: lastLocation)
            shouldUpdate = distance >= followUpdateMinDistance
        } else {
            shouldUpdate = true
        }
        if let lastHeading = lastFollowCameraHeading {
            let delta = abs(lastHeading - heading)
            let wrappedDelta = min(delta, 360 - delta)
            shouldUpdate = shouldUpdate || wrappedDelta >= followUpdateMinHeadingDelta
        } else {
            shouldUpdate = true
        }
        if let lastDistance = lastFollowCameraDistance {
            shouldUpdate = shouldUpdate || abs(lastDistance - distance) >= followUpdateMinDistanceDelta
        } else {
            shouldUpdate = true
        }
        if shouldUpdate {
            lastFollowCameraUpdate = now
            lastFollowCameraCenter = center
            lastFollowCameraHeading = heading
            lastFollowCameraDistance = distance
        }
        return shouldUpdate
    }

    private func followCameraDistanceForNextStep() -> CLLocationDistance? {
        guard let route,
              let location = locationManager.currentLocation,
              let stepIndex = closestStepIndex(for: route, to: location.coordinate) else { return nil }
        let nextIndex = min(stepIndex + 1, route.steps.count - 1)
        let step = route.steps[nextIndex]
        guard let targetCoordinate = stepTargetCoordinate(step) else { return nil }
        let userLocation = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let targetLocation = CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
        let distance = userLocation.distance(from: targetLocation)
        return max(followCameraMinDistance, min(distance * 3.0, followCameraMaxDistance))
    }

    private func stepTargetCoordinate(_ step: MKRoute.Step) -> CLLocationCoordinate2D? {
        let pointCount = step.polyline.pointCount
        guard pointCount > 0 else { return nil }
        return step.polyline.points()[pointCount - 1].coordinate
    }

    private func regionThatFitsRoute() -> MKCoordinateRegion? {
        guard let route else { return nil }
        var rect = route.polyline.boundingMapRect
        if rect.isNull || rect.isEmpty { return nil }
        let widthPadding = rect.size.width * (routeFitPaddingMultiplier - 1)
        let heightPadding = rect.size.height * (routeFitPaddingMultiplier - 1)
        rect = rect.insetBy(dx: -widthPadding / 2, dy: -heightPadding / 2)
        if rect.size.width == 0 || rect.size.height == 0 {
            return nil
        }
        return MKCoordinateRegion(rect)
    }
    
    // MARK: - Auto-stop navigation when devices are close
    
    private func recordInitialDistance() {
        // Record the initial distance between devices when navigation starts
        // This is used to determine if auto-stop should be enabled
        guard let user = userCoordinate, let device = deviceCoordinate else { return }
        let userLocation = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let deviceLocation = CLLocation(latitude: device.latitude, longitude: device.longitude)
        let distance = userLocation.distance(from: deviceLocation)
        if initialDistance == nil {
            initialDistance = distance
        }
    }
    
    private func checkAutoStopCondition() {
        // Automatically stop navigation if devices are within 50m of each other,
        // but only if they weren't already within 50m when navigation started
        // Skip check if navigation has already been stopped
        guard !navigationStopped else { return }
        guard let user = userCoordinate, let device = deviceCoordinate else { return }
        guard let initialDist = initialDistance else {
            // If initial distance hasn't been recorded yet, record it now
            recordInitialDistance()
            return
        }
        
        let userLocation = CLLocation(latitude: user.latitude, longitude: user.longitude)
        let deviceLocation = CLLocation(latitude: device.latitude, longitude: device.longitude)
        let currentDistance = userLocation.distance(from: deviceLocation)
        
        // Only auto-stop if:
        // 1. Current distance is within threshold (50m)
        // 2. Initial distance was greater than threshold (devices were not already close)
        if currentDistance <= autoStopDistanceThreshold && initialDist > autoStopDistanceThreshold {
            // Devices have moved close to each other, stop navigation automatically
            // Mark navigation as stopped to prevent re-triggering
            navigationStopped = true
            // Show info overlay and trigger haptics
            Haptic.notifySuccess()
            infoOverlayManager.show(
                message: NSLocalizedString("navigation_stopped_automatically", comment: "Navigation stopped automatically - devices are close"),
                duration: 6.0,
                animationsAllowed: animationsAllowed
            )
            // Stop navigation but keep the map view showing both devices
            stopNavigation()
        }
    }
    
    private func stopNavigation() {
        // Stop navigation without dismissing the view
        // Clear route and navigation info, but keep the map showing both devices
        setRouteForRendering(nil)
        travelTime = nil
        distanceText = nil
        navigationOverlayViewModel = nil
        lastOverlayStepIndex = nil
        routeInfoState.hide()
        stopAutoUpdate()
        showChromeIfNeeded()
        // Disable navigation modes when navigation is stopped
        isNavigationMode = false
        isFollowDeviceHeadingMode = false
        shouldPerformInitialNavigationZoom = false
        // Reset follow camera state
        lastFollowCameraUpdate = nil
        lastFollowCameraCenter = nil
        lastFollowCameraHeading = nil
        lastFollowCameraDistance = nil
        followCameraDistanceOverride = nil
        isFollowAutoZoomEnabled = true
        isAutoCenteringEnabled = true
        // Update bottom accessory to reflect that navigation is stopped
        updateBottomAccessory()
    }

    private func updateLiveNavigationRouteSummary() {
        // Keep ETA/distance continuously updated while focused navigation mode is active.
        guard isNavigationMode, !isRouteFromDeviceToUser else { return }
        guard let route, let currentLocation = locationManager.currentLocation else { return }
        guard let remainingMeters = route.polyline.remainingDistance(toEndFrom: MKMapPoint(currentLocation.coordinate)) else { return }

        let clampedRemainingMeters = max(0, min(remainingMeters, route.distance))
        let remainingSeconds: TimeInterval? = {
            guard route.distance > 0 else { return nil }
            return route.expectedTravelTime * (clampedRemainingMeters / route.distance)
        }()

        let newTravelTime = formattedDuration(remainingSeconds)
        let newDistanceText = formattedDistance(clampedRemainingMeters)

        if travelTime != newTravelTime {
            travelTime = newTravelTime
        }
        if distanceText != newDistanceText {
            distanceText = newDistanceText
        }
    }

    private func applyStaticRouteSummaryFromCurrentRoute() {
        guard let route else { return }
        applyStaticRouteSummary(for: route)
    }

    private func applyStaticRouteSummary(for route: MKRoute) {
        travelTime = formattedDuration(route.expectedTravelTime)
        distanceText = formattedDistance(route.distance)
    }

    private func formattedDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        let clampedSeconds = max(0, seconds)
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = clampedSeconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter.string(from: clampedSeconds)
    }
}

// MARK: - Distance Formatting
extension iPhone_DeviceNavigationView {
    /// Attempts to reuse a previously calculated route if the movement since that
    /// calculation was insignificant. Returns true if a cached route was applied
    /// to the view state, false otherwise.
    ///
    /// A cached route is considered valid when BOTH endpoints (user location and
    /// target device location) have each moved less than the configured threshold since the
    /// route was stored. The cache is segregated by device id and transport type.
    ///
    /// Side effects when a cached route is used:
    /// - Updates `route`, `travelTime`, and `distanceText`
    /// - Aligns all `lastRoute*` fields so subsequent change detection remains accurate
    private func useCachedRouteIfValid() -> Bool {
        guard let user = userCoordinate, let device = deviceCoordinate else { return false }
        let transport = settings.navigationTransportType
        if let cached = routeCache.get(
            for: self.device.DeviceID,
            transportType: transport,
            isRouteReversed: isRouteFromDeviceToUser
        ) {
            if routeCache.isValid(
                cached: cached,
                currentUserCoordinate: user,
                currentDeviceCoordinate: device,
                threshold: cacheReuseThreshold,
                offRouteThreshold: offRouteThreshold
            ) {
                // Apply cached route and keep display fields in sync
                setRouteForRendering(cached.route)
                applyStaticRouteSummary(for: cached.route)
                refreshNavigationOverlayForCurrentRoute()
                // Align last-route inputs so existing change detection logic works
                lastRouteUserCoordinate = cached.userCoordinate
                lastRouteDeviceCoordinate = cached.deviceCoordinate
                lastRouteUserTimestamp = cached.userTimestamp
                lastRouteDeviceTimestamp = cached.deviceTimestamp
                lastRouteTransportType = transport
                return true
            }
        }
        return false
    }
    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        let value: Double
        let unit: UnitLength
        if usesMetric {
            value = meters / 1000.0
            unit = .kilometers
        } else {
            value = meters / 1609.344
            unit = .miles
        }
        let measurement = Measurement(value: value, unit: unit)
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 0
        numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter = numberFormatter
        return formatter.string(from: measurement)
    }

    private func transportSymbolName() -> String {
        switch settings.navigationTransportType {
        case 0: return "figure.walk"
        case 2: return "car"
        case 3: return "tram"
        default: return "car"
        }
    }

    private enum NavigationFeedbackDirection {
        case left
        case right
        case straight
    }

    private enum NavigationHapticStyle {
        case light
        case medium
        case heavy
    }

    private func bindNavigationOverlayFeedback(to viewModel: NavigationOverlayViewModel) {
        navigationOverlayCancellables.removeAll()
        let gate = navigationFeedbackGate
        viewModel.$symbol
            .compactMap { $0 }
            .removeDuplicates()
            .sink { symbol in
                // Use gate (reference type) so we see current state; struct capture would keep isNavigationMode false after double-tap.
                guard gate.isViewActive, !gate.isRouteFromDeviceToUser, gate.isNavigationMode else { return }
                playNavigationFeedback(for: symbol)
            }
            .store(in: &navigationOverlayCancellables)
    }

    private func playNavigationFeedback(for symbol: NavigationInstruction.Symbol) {
        let direction = navigationFeedbackDirection(for: symbol)
        switch direction {
        case .left:
            playNavigationTurnSound(left: true)
            performNavigationHaptic(style: .light, count: 2, interval: leftNavigationHapticInterval)
        case .right:
            playNavigationTurnSound(left: false)
            performNavigationHaptic(style: .medium, count: 3, interval: rightNavigationHapticInterval)
        case .straight:
            // Straight feedback disabled for now
            break
        }
    }

    /// Plays turn sound: custom .caf if present in bundle, otherwise system Tink (left) / Tock (right).
    private func playNavigationTurnSound(left: Bool) {
        let name = left ? navigationLeftSoundName : navigationRightSoundName
        if SoundEffectPlayer.shared.hasResource(named: name, fileExtension: "caf") {
            SoundEffectPlayer.shared.play(named: name, fileExtension: "caf")
        } else {
            let systemID = left ? navigationLeftSystemSoundID : navigationRightSystemSoundID
            SoundEffectPlayer.shared.playSystemSound(systemID)
        }
    }

    private func navigationFeedbackDirection(for symbol: NavigationInstruction.Symbol) -> NavigationFeedbackDirection {
        switch symbol {
        case .slightLeft, .left, .sharpLeft, .uTurn:
            return .left
        case .slightRight, .right, .sharpRight:
            return .right
        case .start, .straight, .arrive, .cross, .tunnel, .bridge, .stairs, .escalator:
            return .straight
        }
    }

    private func performNavigationHaptic(style: NavigationHapticStyle, count: Int, interval: TimeInterval) {
        guard count > 0 else { return }
        for index in 0..<count {
            let delay = interval * Double(index)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                switch style {
                case .light:
                    Haptic.impactLight()
                case .medium:
                    Haptic.impactMedium()
                case .heavy:
                    Haptic.impactHeavy()
                }
            }
        }
    }

    private func refreshNavigationOverlayForCurrentRoute() {
        guard let route else {
            navigationOverlayViewModel = nil
            lastOverlayStepIndex = nil
            navigationOverlayCancellables.removeAll()
            return
        }
        // Create and fully configure the view model before assigning so the view never shows
        // the kit's default step (e.g. "Arrive at destination") for a frame when switching route
        let newViewModel = NavigationOverlayViewModel(route: route, unit: navigationOverlayUnit())
        let effectiveStepIndex: Int
        if let location = locationManager.currentLocation,
           let rawStepIndex = closestStepIndex(for: route, to: location.coordinate) {
            // Never show "Arrive at destination" unless user is actually near the destination:
            // if closest step is the last step, check distance to route end; if far, use step 0
            let lastIndex = route.steps.count - 1
            if rawStepIndex == lastIndex, lastIndex > 0 {
                let lastStep = route.steps[lastIndex]
                let userPoint = MKMapPoint(location.coordinate)
                let distanceToDestination = lastStep.polyline.closestDistance(to: userPoint) ?? .greatestFiniteMagnitude
                if distanceToDestination > 150 {
                    effectiveStepIndex = 0
                } else {
                    effectiveStepIndex = rawStepIndex
                }
            } else {
                effectiveStepIndex = rawStepIndex
            }
            let step = route.steps[effectiveStepIndex]
            newViewModel.update(step: effectiveStepIndex)
            if let remainingMeters = step.polyline.remainingDistance(toEndFrom: MKMapPoint(location.coordinate)) {
                let measurement = Measurement(value: remainingMeters, unit: UnitLength.meters)
                    .converted(to: navigationOverlayUnit())
                newViewModel.updateRemainingDistance(to: measurement)
            } else {
                let fallback = Measurement(value: step.distance, unit: UnitLength.meters)
                    .converted(to: navigationOverlayUnit())
                newViewModel.updateRemainingDistance(to: fallback)
            }
            lastOverlayStepIndex = effectiveStepIndex
        } else if let firstStep = route.steps.first {
            effectiveStepIndex = 0
            newViewModel.update(step: 0)
            let measurement = Measurement(value: firstStep.distance, unit: UnitLength.meters)
                .converted(to: navigationOverlayUnit())
            newViewModel.updateRemainingDistance(to: measurement)
            lastOverlayStepIndex = 0
        } else {
            effectiveStepIndex = -1
            lastOverlayStepIndex = nil
        }
        navigationOverlayViewModel = newViewModel
        bindNavigationOverlayFeedback(to: newViewModel)
    }

    private func updateNavigationOverlayStep() {
        guard let route,
              let navigationOverlayViewModel,
              let location = locationManager.currentLocation else { return }
        guard var stepIndex = closestStepIndex(for: route, to: location.coordinate) else { return }
        // Never show "Arrive at destination" unless user is actually near the destination
        let lastIndex = route.steps.count - 1
        if stepIndex == lastIndex, lastIndex > 0 {
            let lastStep = route.steps[lastIndex]
            let userPoint = MKMapPoint(location.coordinate)
            let distanceToDestination = lastStep.polyline.closestDistance(to: userPoint) ?? .greatestFiniteMagnitude
            if distanceToDestination > 150 {
                stepIndex = 0
            }
        }
        // Only update step if it changed to prevent unnecessary flickering
        if stepIndex != lastOverlayStepIndex {
            navigationOverlayViewModel.update(step: stepIndex)
            lastOverlayStepIndex = stepIndex
        }
        // Always update remaining distance as user moves along the route
        let step = route.steps[stepIndex]
        if let remainingMeters = step.polyline.remainingDistance(toEndFrom: MKMapPoint(location.coordinate)) {
            let measurement = Measurement(value: remainingMeters, unit: UnitLength.meters)
                .converted(to: navigationOverlayUnit())
            navigationOverlayViewModel.updateRemainingDistance(to: measurement)
        } else {
            let fallback = Measurement(value: step.distance, unit: UnitLength.meters)
                .converted(to: navigationOverlayUnit())
            navigationOverlayViewModel.updateRemainingDistance(to: fallback)
        }
    }

    private func closestStepIndex(for route: MKRoute, to coordinate: CLLocationCoordinate2D) -> Int? {
        let point = MKMapPoint(coordinate)
        var bestIndex: Int?
        var bestDistance: CLLocationDistance = .greatestFiniteMagnitude
        for (index, step) in route.steps.enumerated() {
            guard let distance = step.polyline.closestDistance(to: point) else { continue }
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func navigationOverlayUnit() -> UnitLength {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        return usesMetric ? .meters : .feet
    }

    private func updateBottomAccessory() {
        if #available(iOS 26.0, *) {
            let visible = (travelTime != nil || distanceText != nil)
            routeInfoState.update(
                etaText: travelTime,
                distanceText: distanceText,
                transportSymbolName: transportSymbolName(),
                visible: visible,
                isMutualNavigation: mutualNavigationDetector.isMutualNavigation
            )
        }
    }
}

/// Holds current view/mode state so the navigation feedback Combine sink reads live values
/// instead of a struct snapshot (which would keep isNavigationMode false after double-tap).
private final class NavigationFeedbackGate {
    var isViewActive = false
    var isRouteFromDeviceToUser = true
    var isNavigationMode = false
}
