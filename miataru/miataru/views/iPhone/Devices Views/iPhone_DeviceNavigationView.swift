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
import MiataruAPIClient
import NavigationOverlayKit

struct iPhone_DeviceNavigationView: View {
    var device: KnownDevice

    @EnvironmentObject private var routeInfoState: RouteInfoState
    @Environment(\.dismiss) private var dismiss
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
    @State private var isRouteReversed: Bool = true // Default: device to user
    @State private var navigationOverlayViewModel: NavigationOverlayViewModel? = nil
    @State private var lastOverlayStepIndex: Int? = nil
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
    // Legacy fields removed in favor of RouteRequestCounter
    // Fit configuration: reduce padding around both markers when auto-centering
    private let fitPaddingMultiplier: Double = 1.8
    private let fitMinimumSpan = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
    // Minimum route progress required before showing ghost/progress segmentation
    private let minimumProgressToShowGhost: Double = 0.05
    // Distance threshold (meters) for reusing cached routes and detecting significant movement
    private let routeReuseDistanceThreshold: CLLocationDistance = 100
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
    // Generous daily upper bound to prevent accidental request lockout while developing/testing
    private let routeRequestDailyLimit: Int = 17000
    private let mutualNavigationOnSoundName = "confirm"
    private let mutualNavigationOffSoundName = "cancel"

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
                    isRouteReversed.toggle()
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
        .id(device.DeviceID)
            .onChange(of: device.DeviceID) {
            // Reset all device-related state when a new device is injected
            // We intentionally do NOT clear the route cache here; it is keyed by device id
            userCoordinate = nil
            deviceCoordinate = nil
            animatedUserCoordinate = nil
            animatedDeviceCoordinate = nil
            route = nil
            travelTime = nil
            distanceText = nil
            currentRegion = nil
            hasSetInitialRegion = false
            userHasInteractedWithMap = false
            currentMapCamera = nil
            userHasRotatedMap = false
            isProgrammaticCameraChange = false
            isAutoCenteringEnabled = true
            // Ensure auto-update lock state follows global setting for new navigation
            isAutoRouteUpdateLocked = settings.automaticRouteUpdateDuringNavigation
            isRouteReversed = true // Reset to default: device to user
            navigationOverlayViewModel = nil
            lastOverlayStepIndex = nil
            deviceTimestamp = nil
            isLoading = false
            lastRouteUserCoordinate = nil
            lastRouteDeviceCoordinate = nil
            lastRouteUserTimestamp = nil
            lastRouteDeviceTimestamp = nil
            lastRouteTransportType = nil
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
                if settings.showRouteProgress {
                    let knownSpeed = DeviceLocationCacheStore.shared.getLocation(for: device.DeviceID)?.speed
                    let userSpeed = locationManager.currentLocation?.speed
                    if let (done, todo, ghost, progress) = RouteGhostCalculator.ghost(
                        for: route,
                        deviceTimestamp: deviceTimestamp,
                        knownDeviceSpeed: knownSpeed,
                        userTimestamp: userTimestamp,
                        knownUserSpeed: userSpeed,
                        now: now,
                        isRouteReversed: isRouteReversed
                    ) {
                        if progress <= minimumProgressToShowGhost {
                            MapPolyline(route.polyline)
                                .stroke(RouteStyle.remaining, lineWidth: 4)
                            if isMutualNavigation {
                                MapPolyline(route.polyline)
                                    .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                            }
                        } else if progress >= 1 {
                            MapPolyline(route.polyline)
                                .stroke(RouteStyle.completed, lineWidth: 4)
                            if isMutualNavigation {
                                MapPolyline(route.polyline)
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
                    } else {
                        MapPolyline(route.polyline)
                            .stroke(RouteStyle.withoutRemaining, lineWidth: 4)
                        if isMutualNavigation {
                            MapPolyline(route.polyline)
                                .stroke(RouteStyle.mutualNavigation, lineWidth: 2.5)
                        }
                    }
                } else {
                    MapPolyline(route.polyline)
                        .stroke(RouteStyle.withoutRemaining, lineWidth: 4)
                    if isMutualNavigation {
                        MapPolyline(route.polyline)
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
            .onAppear {
                isViewActive = true
                Haptic.impactMedium()
                // Initial wiring on appear: sync settings, set coordinates, try cache, then fetch
                isAutoCenteringEnabled = true
                // Sync auto-update lock state with global setting on appear
                isAutoRouteUpdateLocked = settings.automaticRouteUpdateDuringNavigation
                // Provide cancel handler for bottom accessory (iOS 26)
                routeInfoState.onCancel = {
                    Haptic.impactMedium()
                    dismiss()
                }
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
            }
            .onReceive(cache.$locations) { _ in
                updateCoordinates()
                checkAutoStopCondition()
                updateNavigationOverlayStep()
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { input in
                now = input
            }
            .onDisappear {
                isViewActive = false
                stopAutoUpdate()
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
            .onChange(of: settings.navigationTransportType) { _, _ in
                calculateRoute()
            }
            .onChange(of: isRouteReversed) { _, _ in
                refreshNavigationOverlayForCurrentRoute()
            }
            .onChange(of: travelTime) { _, _ in
                now = Date()
                updateBottomAccessory()
            }
            .onChange(of: distanceText) { _, _ in
                updateBottomAccessory()
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
                    // Ignore user interaction detection for programmatic updates
                    isProgrammaticCameraChange = false
                } else {
                    // User interaction is detected via gestures; here we only deduce rotation state
                    if abs(context.camera.heading) < 0.1 {
                        userHasRotatedMap = false
                    } else if headingChanged {
                        userHasRotatedMap = true
                    }
                }
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
        if let navigationOverlayViewModel, !isRouteReversed, route != nil {
            NavigationOverlayView(viewModel: navigationOverlayViewModel, alignment: .top)
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
        // When isRouteReversed is true (device to user, default): top arrow is accent, bottom is primary
        // When isRouteReversed is false (user to device): top arrow is primary, bottom is accent
        Image(systemName: "arrow.up.arrow.down")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isRouteReversed ? Color.green : Color.primary,
                isRouteReversed ? Color.primary : Color.green
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
                    withAnimation { isUpdating = true }
                    Task {
                        await fetchTargetDeviceLocation(resetAndRecenter: true, ignoreRouteCache: true)
                        withAnimation { isUpdating = false }
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
        .animation(.easeInOut(duration: 0.2), value: isAutoRouteUpdateLocked)
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
                withAnimation { animatedUserCoordinate = coord }
            }
        }
        if let cached = cache.getLocation(for: device.DeviceID) {
            let coord = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            let changed = deviceCoordinate?.latitude != coord.latitude || deviceCoordinate?.longitude != coord.longitude
            deviceCoordinate = coord
            if changed || animatedDeviceCoordinate == nil {
                withAnimation { animatedDeviceCoordinate = coord }
            }
        }
        if let user = userCoordinate, let dest = deviceCoordinate,
           (!hasSetInitialRegion || recenter || isAutoCenteringEnabled) {
            let region = regionThatFits(user: user, dest: dest)
            isProgrammaticCameraChange = true
            withAnimation {
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

    private func calculateRoute(ignoreCache: Bool = false) {
        // Calculate a new route between user and selected device.
        // Prefers a cached route when movement < 100m; applies a daily network request limit.
        guard let user = userCoordinate, let device = deviceCoordinate else { return }
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
        // Draw the route from the current user towards the other device, or reversed if isRouteReversed is true
        if isRouteReversed {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: device))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: user))
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: user))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: device))
        }
        request.transportType = transportTypeFromSetting(settings.navigationTransportType)
        Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                if let first = response.routes.first {
                    route = first
                    let formatter = DateComponentsFormatter()
                    formatter.unitsStyle = .short
                    travelTime = formatter.string(from: first.expectedTravelTime)
                    distanceText = formattedDistance(first.distance)
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
                        route: first,
                        userCoordinate: user,
                        deviceCoordinate: device,
                        userTimestamp: userTimestamp,
                        deviceTimestamp: deviceTimestamp
                    )
                } else {
                    route = nil
                    travelTime = nil
                    distanceText = nil
                    lastRouteTransportType = nil
                    refreshNavigationOverlayForCurrentRoute()
                    showErrorOverlay(
                        "No route found",
                        NSLocalizedString("route_not_found", comment: "Could not generate a route between the locations.")
                    )
                }
            } catch {
                route = nil
                travelTime = nil
                distanceText = nil
                lastRouteTransportType = nil
                refreshNavigationOverlayForCurrentRoute()
                showErrorOverlay(
                    "Route calculation failed: \(error.localizedDescription)",
                    NSLocalizedString("route_generation_failed", comment: "Route calculation failed. Please try again.")
                )
            }
        }
    }

    private func openInAppleMaps() {
        // Open the route in the Apple Maps app using the selected transport type
        guard let dest = deviceCoordinate else { return }
        let source: MKMapItem
        let destination: MKMapItem
        if isRouteReversed {
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
        errorOverlayManager.show(message: userMessage)
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
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [device.DeviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
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
                    withAnimation { animatedDeviceCoordinate = coordinate }
                }
                // Always update coordinates to allow auto-centering when enabled
                updateCoordinates(recenter: resetAndRecenter)
                // Record initial distance if not yet recorded (after first successful fetch)
                if initialDistance == nil {
                    recordInitialDistance()
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
        // and movement since last route is significant, we refresh the route, preferring cache.
        stopAutoUpdate()
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    await fetchTargetDeviceLocation(resetAndRecenter: false)
                    if isAutoRouteUpdateLocked && hasSignificantMovementSinceLastRoute() {
                        if !useCachedRouteIfValid() {
                            calculateRoute()
                        }
                    }
                    // Check if devices are close enough to auto-stop navigation
                    checkAutoStopCondition()
                }
            }
    }

    private func hasSignificantMovementSinceLastRoute() -> Bool {
        // Returns true if user OR device has moved more than the threshold since last route
        // calculation. The threshold is configurable to balance accuracy vs. cost.
        let threshold: CLLocationDistance = routeReuseDistanceThreshold
        var userMoved = false
        if let current = userCoordinate, let last = lastRouteUserCoordinate {
            let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            userMoved = distance > threshold
        } else if lastRouteUserCoordinate == nil {
            userMoved = true
        }
        var deviceMoved = false
        if let current = deviceCoordinate, let last = lastRouteDeviceCoordinate {
            let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            deviceMoved = distance > threshold
        } else if lastRouteDeviceCoordinate == nil {
            deviceMoved = true
        }
        return userMoved || deviceMoved
    }

    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func restartAutoUpdate() {
        startAutoUpdate()
    }

    // Removed: restartTimeUpdateTimer(). We now use an inline Timer publisher directly in .onReceive for per-second updates.

    // MARK: - Map UI Helpers (Scale bar and Compass)

    private func markUserInteraction() {
        userHasInteractedWithMap = true
        isAutoCenteringEnabled = false
    }

    @ViewBuilder
    private func scaleBarView() -> some View {
        Group {
            if let region = currentRegion {
                Button(action: {
                    isAutoCenteringEnabled = true
                    resetZoomToFitBoth()
                }) {
                    MapScaleBar(region: region, width: 50)
                }
                .buttonStyle(.plain)
                .padding([.bottom, .trailing], 16)
                .zIndex(2)
            }
        }
    }

    @ViewBuilder
    private func compassView() -> some View {
        Group {
            if userHasRotatedMap {
                let heading = currentMapCamera?.heading ?? 0
                Button(action: {
                    isAutoCenteringEnabled = true
                    alignMapToNorth()
                }) {
                    MapCompass(heading: heading, size: 40)
                }
                .padding([.top, .trailing], 10)
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userHasRotatedMap)
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
        isProgrammaticCameraChange = true
        withAnimation {
            mapPosition = .camera(newCamera)
            userHasRotatedMap = false
        }
    }

    private func resetZoomToFitBoth() {
        // Smoothly zoom to a region that fits both user and device
        if let user = userCoordinate, let dest = deviceCoordinate {
            let region = regionThatFits(user: user, dest: dest)
            isProgrammaticCameraChange = true
            withAnimation(.easeInOut(duration: 0.5)) {
                mapPosition = .region(region)
            }
        }
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
                duration: 6.0
            )
            // Stop navigation but keep the map view showing both devices
            stopNavigation()
        }
    }
    
    private func stopNavigation() {
        // Stop navigation without dismissing the view
        // Clear route and navigation info, but keep the map showing both devices
        route = nil
        travelTime = nil
        distanceText = nil
        navigationOverlayViewModel = nil
        lastOverlayStepIndex = nil
        routeInfoState.hide()
        stopAutoUpdate()
        // Update bottom accessory to reflect that navigation is stopped
        updateBottomAccessory()
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
        if let cached = routeCache.get(for: self.device.DeviceID, transportType: transport) {
            if routeCache.isValid(
                cached: cached,
                currentUserCoordinate: user,
                currentDeviceCoordinate: device,
                threshold: routeReuseDistanceThreshold
            ) {
                // Apply cached route and keep display fields in sync
                route = cached.route
                let formatter = DateComponentsFormatter()
                formatter.unitsStyle = .short
                travelTime = formatter.string(from: cached.route.expectedTravelTime)
                distanceText = formattedDistance(cached.route.distance)
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

    private func refreshNavigationOverlayForCurrentRoute() {
        guard !isRouteReversed, let route else {
            navigationOverlayViewModel = nil
            lastOverlayStepIndex = nil
            return
        }
        navigationOverlayViewModel = NavigationOverlayViewModel(route: route, unit: navigationOverlayUnit())
        lastOverlayStepIndex = nil
        updateNavigationOverlayStep()
    }

    private func updateNavigationOverlayStep() {
        guard !isRouteReversed,
              let route,
              let navigationOverlayViewModel,
              let location = locationManager.currentLocation else { return }
        guard let stepIndex = closestStepIndex(for: route, to: location.coordinate) else { return }
        if stepIndex != lastOverlayStepIndex {
            navigationOverlayViewModel.update(step: stepIndex)
            lastOverlayStepIndex = stepIndex
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


