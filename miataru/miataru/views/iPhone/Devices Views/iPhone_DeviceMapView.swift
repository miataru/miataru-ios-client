/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_DeviceMapView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MapKit
import CoreLocation
import MiataruAPIClient
import Combine

struct iPhone_DeviceMapView: View {
    let deviceID: String // Device identifier
    // Preview parameters (optional, for SwiftUI preview)
    var previewDeviceLocation: CLLocationCoordinate2D? = nil
    var previewDeviceAccuracy: Double? = nil
    var previewDeviceTimestamp: Date? = nil
    var onNavigateToDevice: ((String) -> Void)? = nil // Callback for navigation
    @Namespace var mapScope
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Will be set in onAppear
        span: spanForZoomLevel(1) // Default zoom level, will be overwritten in onAppear
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Will be set in onAppear
            span: spanForZoomLevel(1)
        )
    )
    @State private var isLoading = false // Indicates if location is being fetched
    @State private var showError = false // Controls error overlay visibility
    @State private var errorMessage = "" // Error message to display
    @State private var deviceLocation: CLLocationCoordinate2D? // Current device location
    @State private var animatedDeviceLocation: CLLocationCoordinate2D? // Animated marker position for smooth transitions
    @State private var deviceAccuracy: Double? // Location accuracy in meters
    @State private var deviceTimestamp: Date? = nil // Timestamp of the last location update
    @ObservedObject private var settings = SettingsManager.shared // App settings
    @ObservedObject private var cache = DeviceLocationCacheStore.shared // Device location cache
    @Environment(\.animationsAllowed) private var animationsAllowed
    @StateObject private var deviceStore = KnownDeviceStore.shared // Store for known devices
    @StateObject private var locationManager = LocationManager.shared // Access to user's location
    @State private var timerCancellable: AnyCancellable? = nil // Timer for auto-updating location
    @State private var errorOverlayVisible = false // Controls error overlay visibility
    @State private var currentMapSpan: MKCoordinateSpan = spanForZoomLevel(1) // Current map zoom level
    @State private var mapInteractionID = UUID() // Used to force map updates
    @State private var currentRegion: MKCoordinateRegion? = nil // Current visible region
    @State private var currentMapCamera: MapCamera? = nil // Current camera including heading
    @State private var userHasRotatedMap = false // Tracks if user manually rotated the map
    @StateObject private var errorOverlayManager = ErrorOverlayManager() // Manages error overlay
    @State private var showEditDeviceSheet = false // Controls device edit sheet
    @State private var showNavigationSheet = false // Controls navigation view
    @State private var showHistoryView = false // Controls history view
    @State private var isHistoryPreloading = false // Avoid duplicate history preloads
    @State private var selectedActionDeviceID: String? = nil // Currently selected device for actions
    @State private var showDeviceActionDialog = false // Controls confirmation dialog for actions
    @State private var devicePickerData: DevicePickerData? = nil // Holds nearby devices for picker sheet (triggers sheet when non-nil)
    @State private var cachedDeviceCoordinates: [String: CLLocationCoordinate2D] = [:] // Cached coordinates to avoid recomputing on tap
    @State private var precomputedNearbyDevices: [String: [KnownDevice]] = [:] // Precomputed nearby devices keyed by deviceID
    @State private var now = Date() // Timer for relative time display
    @State private var showNetworkErrorIcon = false // Show network error icon on network issues
    @State private var screenSize: CGSize = .zero // Track screen size for off-screen arrows
    @State private var isUpdating = false // Controls update button animation state
    @State private var isProgrammaticCameraChange = false // Track programmatic camera updates
    @State private var suppressUserCameraChangeDetectionUntil: Date? = nil // Grace window for programmatic animations
    @State private var isAutoCenteringEnabled = true // Disable auto recenter after user interaction
    @State private var visibleDeviceCount: Int = 0 // Number of devices currently visible in the map viewport
    @State private var isMapMoving = false // Track if map is currently moving/animating
    @State private var mapMovementTimer: Timer? = nil // Timer to detect when map movement stops
    
    // MARK: - Identifiable wrapper for device picker sheet
    private struct DevicePickerData: Identifiable {
        let id = UUID()
        let devices: [KnownDevice]
    }
    
    // MARK: - Offscreen arrows support types/helpers
    private struct ArrowData {
        let device: KnownDevice
        let coordinate: CLLocationCoordinate2D
        let distanceKM: Double
        let behavior: ArrowBehavior
        let onTap: () -> Void
    }
    
    private var screenCenterPoint: CGPoint {
        CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
    }
    
    private func computeOffscreenDevicesByEdge(region: MKCoordinateRegion) -> [Edge: [ArrowData]] {
        var devicesByEdge: [Edge: [ArrowData]] = [:]
        
        // Current device
        if let device = device, let coordinate = deviceLocation,
           let edge = OffscreenDeviceEdgeHelper.edge(
                for: coordinate,
                in: region,
                screenSize: screenSize,
                heading: currentMapCamera?.heading ?? 0
            ) {
            let tap = {
                if animationsAllowed {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        if #available(iOS 17.0, *) {
                            if let currentRegion = cameraPosition.region {
                                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentRegion.span))
                            }
                        } else {
                            self.region = MKCoordinateRegion(center: coordinate, span: self.region.span)
                        }
                    }
                } else {
                    if #available(iOS 17.0, *) {
                        if let currentRegion = cameraPosition.region {
                            cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentRegion.span))
                        }
                    } else {
                        self.region = MKCoordinateRegion(center: coordinate, span: self.region.span)
                    }
                }
            }
            let deviceLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            let distanceKM = deviceLocation.distance(from: centerLocation) / 1000.0
            devicesByEdge[edge, default: []].append(ArrowData(device: device, coordinate: coordinate, distanceKM: distanceKM, behavior: .jumpToLocation, onTap: tap))
        }
        
        // Other devices
        if settings.showOffscreenArrowsForOtherDevices {
            let otherDevices = deviceStore.devices.filter { $0.DeviceID != deviceID }
            for otherDevice in otherDevices {
                if let cached = cache.getLocation(for: otherDevice.DeviceID) {
                    let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                    if let edge = OffscreenDeviceEdgeHelper.edge(
                        for: coordinate,
                        in: region,
                        screenSize: screenSize,
                        heading: currentMapCamera?.heading ?? 0
                    ) {
                        let tap: () -> Void = {
                            if let onNavigateToDevice {
                                onNavigateToDevice(otherDevice.DeviceID)
                            }
                        }
                        let deviceLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        let centerLocation = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
                        let distanceKM = deviceLocation.distance(from: centerLocation) / 1000.0
                        devicesByEdge[edge, default: []].append(ArrowData(device: otherDevice, coordinate: coordinate, distanceKM: distanceKM, behavior: .navigateToDevice, onTap: tap))
                    }
                }
            }
        }
        
        return devicesByEdge
    }
    
    // Returns true if the given coordinate lies within the provided region (handles longitude wrap-around)
    private func isCoordinate(_ coordinate: CLLocationCoordinate2D, inside region: MKCoordinateRegion) -> Bool {
        let halfLat = region.span.latitudeDelta / 2.0
        let halfLon = region.span.longitudeDelta / 2.0
        // Latitude simple bounds
        let latOk = abs(coordinate.latitude - region.center.latitude) <= halfLat
        // Longitude shortest-arc difference (wrap-around at +/-180)
        func shortestLongitudeDelta(_ lon1: Double, _ lon2: Double) -> Double {
            var delta = lon1 - lon2
            while delta > 180 { delta -= 360 }
            while delta < -180 { delta += 360 }
            return delta
        }
        let lonDelta = abs(shortestLongitudeDelta(coordinate.longitude, region.center.longitude))
        let lonOk = lonDelta <= halfLon || region.span.longitudeDelta >= 360
        return latOk && lonOk
    }
    
    // Computed property to get the current device from the store
    private var device: KnownDevice? {
        deviceStore.devices.first { $0.DeviceID == deviceID }
    }
    
    private var selectedActionDevice: KnownDevice? {
        deviceStore.devices.first { $0.DeviceID == (selectedActionDeviceID ?? deviceID) }
    }
    
    // Computed property to get the best available location for map initialization
    private var bestAvailableLocation: CLLocationCoordinate2D {
        // First priority: Device location (if available)
        if let deviceLoc = deviceLocation {
            return deviceLoc
        }
        
        // Second priority: Cached device location
        if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
            return CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
        }
        
        // Third priority: User's own location (if available and authorized)
        if locationManager.authorizationStatus == .authorizedWhenInUse || 
           locationManager.authorizationStatus == .authorizedAlways,
           let userLocation = locationManager.currentLocation {
            return userLocation.coordinate
        }
        
        // Fallback: Use fallback location (never returns nil)
        return fallbackLocation
    }
    
    // Computed property to get a sensible default location when no location is available
    private var fallbackLocation: CLLocationCoordinate2D {
        // Use user's location if available, otherwise use a central European location
        if let userLocation = locationManager.currentLocation {
            return userLocation.coordinate
        }
        
        // Fallback to central Europe (Germany) instead of San Francisco
        return CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515)
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Map and error overlay
            VStack {
                mapSection()
            }
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            screenSize = geometry.size
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            screenSize = newSize
                        }
                }
            )
            // Error overlay for user feedback
            ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
            // Network error icon (top left)
            networkErrorIconView()
            
            // Off-screen device arrows grouped by screen edge (only shown when map is not rotated)
            if !screenSize.width.isZero && !screenSize.height.isZero,
               let region = currentRegion ?? cameraPosition.region {
                let devicesByEdge = computeOffscreenDevicesByEdge(region: region)
                let screenCenter = screenCenterPoint
                // Render arrows grouped by edge
                ForEach([Edge.left, .right, .top, .bottom], id: \.self) { edge in
                    if let group = devicesByEdge[edge] {
                        ForEach(Array(group.enumerated()), id: \.element.device.DeviceID) { index, info in
                            OffScreenDeviceArrow(
                                deviceName: info.device.DeviceName.isEmpty ? info.device.DeviceID : info.device.DeviceName,
                                deviceColor: Color(info.device.DeviceColor ?? UIColor.blue),
                                screenCenter: screenCenter,
                                deviceCoordinate: info.coordinate,
                                mapRegion: region,
                                screenSize: screenSize,
                                distanceInKM: info.distanceKM,
                                isMapRotated: false,
                                mapHeading: currentMapCamera?.heading ?? 0,
                                arrowIndex: index,
                                totalArrows: group.count,
                                behavior: info.behavior,
                                isMapMoving: isMapMoving,
                                onTap: info.onTap
                            )
                        }
                    }
                }
            }
            
            // Scale bar always on top
            scaleBarView()
            // Compass in the top right corner
            compassView()
        }
        .modifier(NavigationTitleModifier(deviceName: device?.DeviceName ?? "Unknown Device"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Button to manually update device location
                updateButton()
            }
        }
        .adaptiveToolbarBackground()
        .onAppear {
            settings.lastOpenedDeviceID = deviceID
            selectedActionDeviceID = deviceID
            // Use preview parameters if set (for SwiftUI preview)
            if let previewLoc = previewDeviceLocation {
                deviceLocation = previewLoc
                animatedDeviceLocation = previewLoc
            }
            if let previewAcc = previewDeviceAccuracy {
                deviceAccuracy = previewAcc
            }
            if let previewTime = previewDeviceTimestamp {
                deviceTimestamp = previewTime
                now = Date() // Update time immediately
            }
            // Show cached location immediately if available
            if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
                deviceLocation = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                deviceAccuracy = cached.accuracy
                deviceTimestamp = cached.timestamp
                now = Date() // Update time immediately
                // Initialize animated marker position with cached location
                animatedDeviceLocation = deviceLocation
                refreshCachedDeviceCoordinates()
            } else {
                // Initialize animated marker position with preview or default
                animatedDeviceLocation = deviceLocation
            }
            // Set initial zoom level
            let span = spanForZoomLevel(settings.mapZoomLevel)
            currentMapSpan = span // Set initial zoom level
            
            // Use the best available location for map initialization
            let coordinate = bestAvailableLocation
            // Initial region set is programmatic; suppress user detection for the animation
            beginProgrammaticCameraAnimation(duration: 0.5)
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    region = MKCoordinateRegion(center: coordinate, span: span)
                    if #available(iOS 17.0, *) {
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                    }
                }
            } else {
                region = MKCoordinateRegion(center: coordinate, span: span)
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                }
            }
            if #available(iOS 17.0, *) {
                updateVisibleDeviceCount(with: cameraPosition.region)
            }
            Task { await fetchLocation(resetZoomToSettings: true) }
            startAutoUpdate()
        }
        .onDisappear {
            stopAutoUpdate()
            mapMovementTimer?.invalidate()
            mapMovementTimer = nil
            if settings.lastOpenedDeviceID == deviceID {
                settings.lastOpenedDeviceID = nil
            }
        }
        .onChange(of: settings.mapUpdateInterval) {
            restartAutoUpdate()
        }
        .onChange(of: settings.mapZoomLevel) {
            let span = spanForZoomLevel(settings.mapZoomLevel)
            // Programmatic zoom change; suppress user detection during animation
            beginProgrammaticCameraAnimation(duration: 0.5)
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    region.span = span
                    if #available(iOS 17.0, *) {
                        cameraPosition = .region(MKCoordinateRegion(center: region.center, span: span))
                    }
                }
            } else {
                region.span = span
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: region.center, span: span))
                }
            }
        }
        // Track map camera and region changes for heading/zoom/region state
        .onMapCameraChange(frequency: .continuous) { context in
            // If within suppression window, treat as programmatic and ignore interaction disabling
            if let until = suppressUserCameraChangeDetectionUntil, Date() < until {
                currentMapCamera = context.camera
                currentRegion = context.region
                currentMapSpan = context.region.span
                return
            }
            // Compare against previous values to track compass state
            let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
            let zoomChanged = abs((currentRegion?.span.latitudeDelta ?? 0) - context.region.span.latitudeDelta) > 0.0001 ||
                              abs((currentRegion?.span.longitudeDelta ?? 0) - context.region.span.longitudeDelta) > 0.0001
            let centerChanged = abs((currentRegion?.center.latitude ?? 0) - context.region.center.latitude) > 0.0001 ||
                                abs((currentRegion?.center.longitude ?? 0) - context.region.center.longitude) > 0.0001
            
            // Detect any map movement (pan, zoom, rotate)
            if headingChanged || zoomChanged || centerChanged {
                // Map is moving - set state and reset timer
                if !isMapMoving {
                    if animationsAllowed {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isMapMoving = true
                        }
                    } else {
                        isMapMoving = true
                    }
                }
                
                // Cancel existing timer
                mapMovementTimer?.invalidate()
                
                // Start new timer to detect when movement stops (after 0.3 seconds of no movement)
                mapMovementTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                    if animationsAllowed {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            isMapMoving = false
                        }
                    } else {
                        isMapMoving = false
                    }
                }
            }
            
            if abs(context.camera.heading) < 0.1 {
                userHasRotatedMap = false
            } else if headingChanged {
                userHasRotatedMap = true
            }
            if headingChanged || zoomChanged {
                currentMapCamera = context.camera
                currentRegion = context.region
                currentMapSpan = context.region.span
            }
            // Always update region for off-screen arrows
            currentRegion = context.region
            updateVisibleDeviceCount(with: context.region)
            refreshCachedDeviceCoordinates()
            if isProgrammaticCameraChange {
                isProgrammaticCameraChange = false
                suppressUserCameraChangeDetectionUntil = nil
            }
        }
        // Update 'now' every second for relative time display (inline publisher to avoid autoconnect disconnects)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { input in
            now = input
        }
        // Show edit device sheet when requested
        .sheet(isPresented: $showEditDeviceSheet) {
            let targetID = selectedActionDeviceID ?? deviceID
            if let index = deviceStore.devices.firstIndex(where: { $0.DeviceID == targetID }) {
                iPhone_EditDeviceView(device: $deviceStore.devices[index], isPresented: $showEditDeviceSheet)
            }
        }
        .navigationDestination(isPresented: $showNavigationSheet) {
            if let device = selectedActionDevice ?? device {
                iPhone_DeviceNavigationView(device: device)
            }
        }
        .navigationDestination(isPresented: $showHistoryView) {
            if let device = selectedActionDevice ?? device {
                iPhone_DeviceHistoryMapView(device: device)
            }
        }
        .confirmationDialog(
            selectedActionDevice?.DeviceName.isEmpty == false ? (selectedActionDevice?.DeviceName ?? "") : NSLocalizedString("device_actions", comment: "Actions for the selected device"),
            isPresented: $showDeviceActionDialog,
            titleVisibility: .visible
        ) {
            if let actionDevice = selectedActionDevice {
                Button(NSLocalizedString("edit_device", comment: "Edit this device")) {
                    triggerEdit(for: actionDevice.DeviceID)
                }
                if actionDevice.DeviceID != thisDeviceIDManager.shared.deviceID {
                    Button(NSLocalizedString("navigation", comment: "Navigate to this device")) {
                        triggerNavigation(for: actionDevice.DeviceID)
                    }
                }
                Button(NSLocalizedString("show_history", comment: "Show device history")) {
                    triggerHistory(for: actionDevice)
                }
            }
            Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) { }
        }
        .sheet(item: $devicePickerData) { pickerData in
            let _ = print("Sheet content closure evaluated: pickerData.devices.count = \(pickerData.devices.count), devices: \(pickerData.devices.map { $0.DeviceName })")
            VStack(spacing: 0) {
                Text(NSLocalizedString("select_device", comment: "Select a device to show actions"))
                    .font(.headline)
                    .padding(.top, 16)
                List {
                    ForEach(pickerData.devices, id: \.DeviceID) { device in
                        Button {
                            presentActions(for: device.DeviceID)
                        } label: {
                            HStack {
                                Text(device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName)
                                    .foregroundStyle(Color.primary)
                                if device.DeviceID == deviceID {
                                    Spacer()
                                    Text(NSLocalizedString("current_device", comment: "Current device"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    print("List onAppear: pickerData.devices.count = \(pickerData.devices.count)")
                }
                Button(NSLocalizedString("cancel", comment: "Cancel"), role: .cancel) {
                    devicePickerData = nil
                }
                .padding()
            }
            .onAppear {
                print("Sheet VStack onAppear: pickerData.devices.count = \(pickerData.devices.count)")
            }
            .presentationDetents([.medium, .large])
        }
    }
    
    // MARK: - View Components
    
    @ViewBuilder
    private func networkErrorIconView() -> some View {
        Group {
            if showNetworkErrorIcon {
                Image(systemName: "network.slash")
                    .foregroundColor(Color(.systemRed))
                    .font(.system(size: 28))
                    .padding(.top, 10)
                    .padding(.leading, 10)
                    .shadow(color: Color(.systemRed).opacity(0.5), radius: 8, x: 0, y: 4)
                    .transition(animationsAllowed ? .opacity : .identity)
                    .zIndex(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: showNetworkErrorIcon)
    }
    
    @ViewBuilder
    private func scaleBarView() -> some View {
        Group {
            if #available(iOS 17.0, *) {
                if let region = currentRegion ?? cameraPosition.region {
                    Button(action: { resetZoomToSettings() }) {
                        MapScaleBar(region: region, width: 50)
                    }
                    .buttonStyle(.plain)
                    .padding([.bottom, .trailing], 5)
                    .zIndex(2)
                }
            } else {
                Button(action: { resetZoomToSettings() }) {
                    MapScaleBar(region: region, width: 50)
                        .id("scalebar")
                }
                .buttonStyle(.plain)
                .padding([.bottom, .trailing], 5)
                .zIndex(2)
            }
        }
    }
    
    @ViewBuilder
    private func compassView() -> some View {
        Group {
            if #available(iOS 17.0, *) {
                let heading = currentMapCamera?.heading ?? 0
                if userHasRotatedMap {
                    Button(action: {
                        isAutoCenteringEnabled = true
                        alignMapToNorth()
                    }) {
                        MapCompass(heading: heading, size: 40)
                    }
                    .padding([.top, .trailing], 10)
                    .zIndex(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(animationsAllowed ? .opacity : .identity)
                }
            }
        }
        .animation(animationsAllowed ? .easeInOut(duration: 0.3) : nil, value: userHasRotatedMap)
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        // Use the new Map API for iOS 17 and above
        if #available(iOS 17.0, *) {
            Map(position: $cameraPosition,scope: mapScope) {
                // Show device marker if location is available
                if let coordinate = animatedDeviceLocation, let device = device {
                    // Draw accuracy circle if enabled and accuracy is valid
                    if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracy, accuracy > 0 {
                        MapCircle(center: coordinate, radius: accuracy)
                            .foregroundStyle(Color(device.DeviceColor ?? UIColor.blue).opacity(0.2))
                    }
                    // Marker annotation for the device
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        ZStack {
                            // Pulsing behind everything
                            if settings.pulsingMapMarkers && visibleDeviceCount < 5 {
                                let circleDiameter = (/* marker height */ 40.0) * 0.65
                                let pulsingSize = circleDiameter * 1.5
                                let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                                PulsingAccuracyCircle(pulsingColor: Color(device.DeviceColor ?? .red), size: pulsingSize)
                                    .offset(y: pulsingOffset)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            VStack(spacing: 0) {
                                // Show relative timestamp above marker (force per-second updates within Map annotation)
                                if let timestamp = deviceTimestamp {
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        let timeString = relativeTimeString(from: timestamp, to: context.date)
                                        let timezoneOffset = timezoneOffsetString(deviceTimeZone: cache.getTimeZone(for: deviceID))
                                        let baseText = timezoneOffset != nil ? "\(timeString) (\(timezoneOffset!))" : timeString
                                        let speedText = settings.showCurrentSpeedOnMap
                                            ? mapSpeedLabelText(speedMetersPerSecond: cache.getLocation(for: deviceID)?.speed)
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
                                            .shimmering(active: settings.pulsingMapMarkers && isLoading && visibleDeviceCount < 5)
                                            .shadow(radius: 2)
                                            .zIndex(2)
                                    }
                                }
                                // Device name label above the marker with outline for readability
                                DeviceNameLabel(deviceName: device.DeviceName, deviceID: device.DeviceID)
                                MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                                    .shadow(radius: 2)
                            }
                            // Add a transparent rectangle to increase the tap area for the context menu
                            Rectangle()
                                .foregroundColor(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 120, height: 160)
                                .offset(y: 12)
                                .zIndex(1)
                                .accessibilityLabel(Text(device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint(Text(NSLocalizedString("open_device_actions_hint", comment: "Open actions for this device")))
                                .onTapGesture {
                                    handleDeviceTap(deviceID: device.DeviceID, coordinate: coordinate)
                                }
                                .contextMenu {
                                    Button {
                                        triggerEdit(for: device.DeviceID)
                                    } label: {
                                        Label(NSLocalizedString("edit_device", comment: "Edit this device"), systemImage: "pencil")
                                    }
                                    if device.DeviceID != thisDeviceIDManager.shared.deviceID {
                                        Button {
                                            triggerNavigation(for: device.DeviceID)
                                        } label: {
                                            Label(NSLocalizedString("navigation", comment: "Navigate to this device"), systemImage: "location")
                                        }
                                    }
                                    Button {
                                        triggerHistory(for: device)
                                    } label: {
                                        Label(NSLocalizedString("show_history", comment: "Show device history"), systemImage: "clock.arrow.circlepath")
                                    }
                                }
                        }.offset(y: 35)
                    }
                }
                // Other device markers visible in the current viewport only (iOS 17+)
                if settings.showOffscreenArrowsForOtherDevices, let visibleRegion = (currentRegion ?? cameraPosition.region) {
                    ForEach(deviceStore.devices.filter { $0.DeviceID != deviceID }, id: \.DeviceID) { other in
                        if let cached = cache.getLocation(for: other.DeviceID) {
                            let coord = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                            if isCoordinate(coord, inside: visibleRegion) {
                                Annotation("", coordinate: coord, anchor: .bottom) {
                                    ZStack {
                                        // Pulsing behind everything
                                        if settings.pulsingMapMarkers && visibleDeviceCount < 5 {
                                            let circleDiameter = (/* marker height */ 40.0) * 0.65
                                            let pulsingSize = circleDiameter * 1.5
                                            let pulsingOffset = (pulsingSize * 1.6) / 2 + 2
                                            PulsingAccuracyCircle(pulsingColor: Color(other.DeviceColor ?? UIColor.systemBlue), size: pulsingSize)
                                                .offset(y: pulsingOffset)
                                                .allowsHitTesting(false)
                                                .accessibilityHidden(true)
                                        }
                                        VStack(spacing: 0) {
                                            // Timestamp above marker (force per-second updates within Map annotation)
                                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                                let timeString = relativeTimeString(from: cached.timestamp, to: context.date)
                                                let timezoneOffset = timezoneOffsetString(deviceTimeZone: cache.getTimeZone(for: other.DeviceID))
                                                let baseText = timezoneOffset != nil ? "\(timeString) (\(timezoneOffset!))" : timeString
                                                let speedText = settings.showCurrentSpeedOnMap
                                                    ? mapSpeedLabelText(speedMetersPerSecond: cached.speed)
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
                                                    .shimmering(active: settings.pulsingMapMarkers && isLoading && visibleDeviceCount < 5)
                                                    .shadow(radius: 2)
                                                    .zIndex(2)
                                            }
                                            // Device name label above the marker with outline for readability
                                            DeviceNameLabel(deviceName: other.DeviceName, deviceID: other.DeviceID)
                                            MiataruMapMarker(color: Color(other.DeviceColor ?? UIColor.systemBlue))
                                                .shadow(radius: 2)
                                        }
                                        // Larger transparent rectangle to match main device hit area and avoid clipping
                                        Rectangle()
                                            .foregroundColor(.clear)
                                            .contentShape(Rectangle())
                                            .frame(width: 120, height: 160)
                                            .offset(y: 12)
                                            .zIndex(1)
                                            .accessibilityLabel(Text(other.DeviceName.isEmpty ? other.DeviceID : other.DeviceName))
                                            .accessibilityAddTraits(.isButton)
                                            .accessibilityHint(Text(NSLocalizedString("open_device_actions_hint", comment: "Open actions for this device")))
                                            .onTapGesture {
                                                handleDeviceTap(deviceID: other.DeviceID, coordinate: coord)
                                            }
                                            .contextMenu {
                                                Button {
                                                    triggerEdit(for: other.DeviceID)
                                                } label: {
                                                    Label(NSLocalizedString("edit_device", comment: "Edit this device"), systemImage: "pencil")
                                                }
                                                if other.DeviceID != thisDeviceIDManager.shared.deviceID {
                                                    Button {
                                                        triggerNavigation(for: other.DeviceID)
                                                    } label: {
                                                        Label(NSLocalizedString("navigation", comment: "Navigate to this device"), systemImage: "location")
                                                    }
                                                }
                                                Button {
                                                    triggerHistory(for: other)
                                                } label: {
                                                    Label(NSLocalizedString("show_history", comment: "Show device history"), systemImage: "clock.arrow.circlepath")
                                                }
                                            }
                                    }
                                    .offset(y: 35)
                                }
                            }
                        }
                    }
                }
            }
            .mapControls {
                MapCompass(heading: 1, size: 10)
                    .mapControlVisibility(.hidden)
            }
            .ignoresSafeArea()
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in isAutoCenteringEnabled = false }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in isAutoCenteringEnabled = false }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { _ in isAutoCenteringEnabled = false }
            )
            .mapStyle(mapStyleFromSettings(settings.mapType))
        } else {
            // For iOS versions below 17, use a legacy map view implementation
            if let currentDevice = device {
                iPhone_LegacyMapViewRepresentable(region: $region, device: currentDevice, deviceLocation: deviceLocation, deviceAccuracy: deviceAccuracy, mapType: settings.mapType)
                    .ignoresSafeArea()
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { _ in isAutoCenteringEnabled = false }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { _ in isAutoCenteringEnabled = false }
                    )
                    .simultaneousGesture(
                        RotationGesture()
                            .onChanged { _ in isAutoCenteringEnabled = false }
                    )
            }
        }
    }

    // MARK: - Programmatic animation helper
    private func beginProgrammaticCameraAnimation(duration: Double) {
        isProgrammaticCameraChange = true
        // Add grace period to cover chained animations and map settling
        suppressUserCameraChangeDetectionUntil = Date().addingTimeInterval(max(0.2, duration + 1.0))
    }

    @ViewBuilder
    private func updateButton() -> some View {
        // Button to manually update device location
        Button {
            withAnimation {
                isUpdating = true
            }
            Task {
                await fetchLocation(resetZoomToSettings: true)
                withAnimation {
                    isUpdating = false
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate.clockwise.byLayer, options: .nonRepeating, isActive: isUpdating)
        }
        .accessibilityLabel(Text(NSLocalizedString("refresh_location", comment: "Refresh the device location now")))
        .accessibilityHint(Text(NSLocalizedString("refresh_location_hint", comment: "Fetches the latest location and resets zoom if configured")))
    }
    // Fetches the latest location for the device from the server
    private func fetchLocation(resetZoomToSettings: Bool = false) async {
        guard let url = URL(string: settings.miataruServerURL), !deviceID.isEmpty else {
            showErrorOverlay("Invalid server URL or DeviceID", NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"))
            return
        }
        let minShimmerDuration: TimeInterval = 1.5
        let startTime = Date()
        isLoading = true
        defer {
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = minShimmerDuration - elapsed
            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                    isLoading = false
                }
            } else {
                isLoading = false
            }
        }
        do {
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [deviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: settings.deviceKey
            )
            if let loc = locations.first {
                let coordinate = CLLocationCoordinate2D(latitude: loc.Latitude, longitude: loc.Longitude)
                let coordinateChanged = deviceLocation?.latitude != coordinate.latitude || deviceLocation?.longitude != coordinate.longitude
                deviceLocation = coordinate
                // Update animated location immediately to ensure marker moves
                animatedDeviceLocation = coordinate
                deviceAccuracy = loc.HorizontalAccuracy
                deviceTimestamp = loc.TimestampDate
                now = Date() // Update time immediately
                // Cache the new location including optional speed
                DeviceLocationCacheStore.shared.setLocation(
                    for: deviceID,
                    latitude: loc.Latitude,
                    longitude: loc.Longitude,
                    accuracy: loc.HorizontalAccuracy,
                    timestamp: loc.TimestampDate,
                    batteryLevel: loc.BatteryLevel,
                    altitude: loc.Altitude,
                    speed: loc.Speed
                )
                refreshCachedDeviceCoordinates()
                if coordinateChanged {
                    beginProgrammaticCameraAnimation(duration: 0.8)
                    withAnimation {
                        if #available(iOS 17.0, *) {
                            if resetZoomToSettings {
                                // On manual update: realign map to north (heading = 0)
                                let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                                let northCamera = MapCamera(centerCoordinate: coordinate, distance: currentMapCamera?.distance ?? 1000, heading: 0, pitch: currentMapCamera?.pitch ?? 0)
                                cameraPosition = .camera(northCamera)
                                currentMapSpan = settingsSpan // Also update currentMapSpan
                            } else if isAutoCenteringEnabled {
                                // On automatic update: keep current orientation (heading)
                                if let currentCamera = currentMapCamera {
                                    let newCamera = MapCamera(
                                        centerCoordinate: coordinate,
                                        distance: currentCamera.distance,
                                        heading: currentCamera.heading,
                                        pitch: currentCamera.pitch
                                    )
                                    cameraPosition = .camera(newCamera)
                                } else {
                                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentMapSpan))
                                }
                            }
                        } else {
                            if resetZoomToSettings {
                                // On manual update: use zoom level from settings
                                let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                                region = MKCoordinateRegion(center: coordinate, span: settingsSpan)
                            } else if isAutoCenteringEnabled {
                                // On automatic update: keep current zoom level
                                let currentZoomLevel = currentZoomLevelFromSpan(region.span)
                                let currentSpan = spanForZoomLevel(currentZoomLevel)
                                region = MKCoordinateRegion(center: coordinate, span: currentSpan)
                            }
                        }
                    }
                }
            } else {
                showErrorOverlay("No location data found", NSLocalizedString("no_location_data_found", comment: "No location available"))
            }
        } catch let error as MiataruAPIClient.APIError {
            // Differentiated error handling
            switch error {
            case .invalidURL:
                showErrorOverlay("Invalid server URL", NSLocalizedString("server_url_invalid", comment: "The server URL is invalid."))
            case .invalidResponse(_):
                showErrorOverlay("Invalid server response", NSLocalizedString("server_response_invalid", comment: "The server response was invalid."))
            case .encodingError(let err):
                debugLog("[iPhone_DeviceMapView] Suppressed encoding error overlay while fetching location: \(err.localizedDescription)")
            case .decodingError(let err):
                showErrorOverlay("Error processing the response: \(err.localizedDescription)", NSLocalizedString("decoding_error", comment: "Error processing the server response."))
            case .requestFailed(_):
                // Show only the network error icon, not the overlay
                withAnimation {
                    showNetworkErrorIcon = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        showNetworkErrorIcon = false
                    }
                }
            case .serverError(_, let message):
                let userMessage = String(format: NSLocalizedString("server_error", comment: "Server error: %@"), message)
                showErrorOverlay("Server error: \(message)", userMessage)
            }
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Error loading location data"))
        }
    }

    // MARK: - Device action helpers
    
    private func triggerEdit(for deviceID: String) {
        selectedActionDeviceID = deviceID
        showDeviceActionDialog = false
        showEditDeviceSheet = true
    }
    
    private func triggerNavigation(for deviceID: String) {
        selectedActionDeviceID = deviceID
        showDeviceActionDialog = false
        showNavigationSheet = true
    }
    
    private func triggerHistory(for device: KnownDevice) {
        selectedActionDeviceID = device.DeviceID
        showDeviceActionDialog = false
        preloadHistoryAndNavigate(for: device)
    }

    private func refreshCachedDeviceCoordinates() {
        var dict: [String: CLLocationCoordinate2D] = [:]
        if let mainCoord = deviceCoordinate(for: deviceID) {
            dict[deviceID] = mainCoord
        }
        for other in deviceStore.devices where other.DeviceID != deviceID {
            if let coord = deviceCoordinate(for: other.DeviceID) {
                dict[other.DeviceID] = coord
            }
        }
        cachedDeviceCoordinates = dict
        precomputedNearbyDevices = computeNearbyGroups(from: dict)
    }
    
    private func presentActions(for deviceID: String) {
        selectedActionDeviceID = deviceID
        devicePickerData = nil
        showDeviceActionDialog = true
    }
    
    private func handleDeviceTap(deviceID: String, coordinate: CLLocationCoordinate2D) {
        let tapStart = Date()
        let nearby: [KnownDevice]
        
        if let precomputed = precomputedNearbyDevices[deviceID] {
            nearby = precomputed
            let elapsed = Date().timeIntervalSince(tapStart)
            print("Device tap handled with precomputed nearby for \(deviceID) in \(String(format: "%.3f", elapsed))s (count: \(precomputed.count))")
        } else {
            nearby = nearbyDevices(around: deviceID, coordinate: coordinate)
            let elapsed = Date().timeIntervalSince(tapStart)
            print("Device tap computed nearby for \(deviceID) in \(String(format: "%.3f", elapsed))s (count: \(nearby.count))")
        }
        
        if nearby.count > 1 {
            print("About to set devicePickerData with \(nearby.count) devices: \(nearby.map { $0.DeviceName })")
            devicePickerData = DevicePickerData(devices: nearby)
            let elapsed = Date().timeIntervalSince(tapStart)
            print("Device tap result for \(deviceID): showing picker with \(nearby.count) devices after \(String(format: "%.3f", elapsed))s")
        } else if let first = nearby.first {
            presentActions(for: first.DeviceID)
            let elapsed = Date().timeIntervalSince(tapStart)
            print("Device tap result for \(deviceID): presenting actions for \(first.DeviceID) after \(String(format: "%.3f", elapsed))s (nearby count: \(nearby.count))")
        } else {
            presentActions(for: deviceID)
            let elapsed = Date().timeIntervalSince(tapStart)
            print("Device tap result for \(deviceID): presenting fallback actions after \(String(format: "%.3f", elapsed))s (no nearby devices)")
        }
    }
    
    private func nearbyDevices(around deviceID: String, coordinate: CLLocationCoordinate2D, thresholdMeters: Double = 35) -> [KnownDevice] {
        let targetLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let devicesWithCoordinates: [(KnownDevice, CLLocationCoordinate2D)] = deviceStore.devices.compactMap { known in
            if let cached = cachedDeviceCoordinates[known.DeviceID] {
                return (known, cached)
            }
            guard let coord = deviceCoordinate(for: known.DeviceID) else { return nil }
            return (known, coord)
        }
        
        let closeDevices = devicesWithCoordinates.filter { pair in
            let loc = CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude)
            return targetLocation.distance(from: loc) <= thresholdMeters
        }.map { $0.0 }
        
        let tapped = closeDevices.first(where: { $0.DeviceID == deviceID })
        let others = closeDevices.filter { $0.DeviceID != deviceID }
            .sorted { $0.DeviceName.localizedCaseInsensitiveCompare($1.DeviceName) == .orderedAscending }
        
        if let tapped {
            return [tapped] + others
        }
        return others
    }
    
    private func deviceCoordinate(for deviceID: String) -> CLLocationCoordinate2D? {
        if deviceID == self.deviceID {
            if let animated = animatedDeviceLocation {
                return animated
            }
            if let current = deviceLocation {
                return current
            }
        }
        if let cached = cache.getLocation(for: deviceID) {
            return CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
        }
        return nil
    }
    
    private func computeNearbyGroups(from coords: [String: CLLocationCoordinate2D], thresholdMeters: Double = 35) -> [String: [KnownDevice]] {
        var result: [String: [KnownDevice]] = [:]
        let deviceLookup = Dictionary(uniqueKeysWithValues: deviceStore.devices.map { ($0.DeviceID, $0) })
        
        for (id, coord) in coords {
            let targetLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            var nearbyIDs: [String] = []
            for (otherID, otherCoord) in coords {
                guard otherID != id else { continue }
                let loc = CLLocation(latitude: otherCoord.latitude, longitude: otherCoord.longitude)
                if targetLocation.distance(from: loc) <= thresholdMeters {
                    nearbyIDs.append(otherID)
                }
            }
            guard !nearbyIDs.isEmpty else { continue }
            let ordered = ([id] + nearbyIDs.sorted { (deviceLookup[$0]?.DeviceName ?? $0)
                .localizedCaseInsensitiveCompare(deviceLookup[$1]?.DeviceName ?? $1) == .orderedAscending })
                .compactMap { deviceLookup[$0] }
            if ordered.count > 1 {
                result[id] = ordered
            }
        }
        return result
    }

    // Preloads history before navigating to the dedicated history map to avoid switching views when no data exists.
    private func preloadHistoryAndNavigate(for device: KnownDevice) {
        guard !isHistoryPreloading else { return }
        isHistoryPreloading = true
        Task {
            await fetchHistoryBeforeNavigation(for: device)
            await MainActor.run {
                isHistoryPreloading = false
            }
        }
    }

    // Fetches history and navigates only when entries are available. Shows an overlay on the current map if empty or failed.
    private func fetchHistoryBeforeNavigation(for device: KnownDevice) async {

        // Prefer cached history; do not navigate if cache is empty.
        if let cachedHistory = DeviceHistoryCacheStore.shared.getHistory(for: device.DeviceID) {
            if cachedHistory.isEmpty {
                await MainActor.run {
                    errorOverlayManager.show(
                        message: NSLocalizedString("history_no_data", comment: "No history available placeholder"),
                        animationsAllowed: animationsAllowed
                    )
                }
            } else {
                await MainActor.run {
                    showHistoryView = true
                }
            }
            return
        }

        guard let url = URL(string: settings.miataruServerURL), !device.DeviceID.isEmpty else {
            await MainActor.run {
                errorOverlayManager.show(
                    message: NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"),
                    animationsAllowed: animationsAllowed
                )
            }
            return
        }

        let requestingDeviceID = thisDeviceIDManager.shared.deviceID

        do {
            APIRequestCounter.shared.record(.getLocationHistory)
            let data = try await MiataruAPIClient.getLocationHistory(
                serverURL: url,
                forDeviceID: device.DeviceID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: settings.deviceKey,
                amount: 10000
            )
            let normalized = normalizeHistoryEntries(from: data)
            let sorted = normalized.sorted { $0.TimestampDate < $1.TimestampDate }

            guard !sorted.isEmpty else {
                await MainActor.run {
                    errorOverlayManager.show(
                        message: NSLocalizedString("history_no_data", comment: "No history available placeholder"),
                        animationsAllowed: animationsAllowed
                    )
                }
                return
            }

            await MainActor.run {
                DeviceHistoryCacheStore.shared.setHistory(sorted, for: device.DeviceID)
                showHistoryView = true
            }
        } catch let apiError as MiataruAPIClient.APIError {
            let message = mapHistoryAPIError(apiError)
            await MainActor.run {
                if let message {
                    errorOverlayManager.show(message: message, animationsAllowed: animationsAllowed)
                }
            }
        } catch {
            await MainActor.run {
                errorOverlayManager.show(message: error.localizedDescription, animationsAllowed: animationsAllowed)
            }
        }
    }

    private func mapHistoryAPIError(_ error: MiataruAPIClient.APIError) -> String? {
        switch error {
        case .invalidURL:
            return NSLocalizedString("server_url_invalid", comment: "The server URL is invalid.")
        case .invalidResponse(_):
            return NSLocalizedString("server_response_invalid", comment: "The server response was invalid.")
        case .encodingError(let err):
            debugLog("[iPhone_DeviceMapView] Suppressed encoding error overlay while loading history: \(err.localizedDescription)")
            return nil
        case .decodingError(let err):
            return "\(NSLocalizedString("decoding_error", comment: "Error processing the server response.")) \(err.localizedDescription)"
        case .requestFailed(let err):
            return "\(NSLocalizedString("network_error", comment: "Network error. Please check your internet connection.")) \(err.localizedDescription)"
        case .serverError(_, let message):
            return String(format: NSLocalizedString("server_error", comment: "Server error: %@"), message)
        }
    }

    private func normalizeHistoryEntries(from entries: [MiataruLocationData]) -> [MiataruLocationData] {
        var uniqueEntries: [MiataruLocationData] = []
        uniqueEntries.reserveCapacity(entries.count)

        var seenKeys = Set<String>()
        var droppedDuplicates = 0
        var droppedInvalid = 0

        for entry in entries {
            guard entry.Latitude.isFinite, entry.Longitude.isFinite else {
                droppedInvalid += 1
                continue
            }

            let key = "\(entry.Timestamp)|\(entry.Latitude)|\(entry.Longitude)"
            if seenKeys.insert(key).inserted {
                uniqueEntries.append(entry)
            } else {
                droppedDuplicates += 1
            }
        }

        if droppedDuplicates > 0 || droppedInvalid > 0 {
            debugLog("[DeviceMapView] Normalized history for device \(deviceID) dropped duplicates=\(droppedDuplicates) invalid=\(droppedInvalid)")
        }

        return uniqueEntries
    }

    // Starts the auto-update timer for fetching location
    private func startAutoUpdate() {
        stopAutoUpdate() // Cancel any existing timer
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { await fetchLocation(resetZoomToSettings: false) }
            }
    }

    // Stops the auto-update timer
    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    // Restarts the auto-update timer
    private func restartAutoUpdate() {
        startAutoUpdate()
    }

    // Shows the error overlay with a debug and user message
    private func showErrorOverlay(_ debugMessage: String, _ userMessage: String) {
        debugLog("Error: \(debugMessage)")
        errorOverlayManager.show(message: userMessage, animationsAllowed: animationsAllowed)
    }

    // Aligns the map to north (heading = 0)
    private func alignMapToNorth() {
        let coordinate = bestAvailableLocation
        guard let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: coordinate,
            distance: currentCamera.distance,
            heading: 0, // North
            pitch: currentCamera.pitch
        )
        beginProgrammaticCameraAnimation(duration: 0.5)
        if animationsAllowed {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(newCamera)
                userHasRotatedMap = false // Hide compass when aligned to north
            }
        } else {
            cameraPosition = .camera(newCamera)
            userHasRotatedMap = false
        }
    }

    // Resets the map zoom to the value from settings
    private func resetZoomToSettings() {
        isAutoCenteringEnabled = true
        let span = spanForZoomLevel(settings.mapZoomLevel)
        let coordinate = bestAvailableLocation
        if #available(iOS 17.0, *) {
            let newRegion = MKCoordinateRegion(center: coordinate, span: span)
            beginProgrammaticCameraAnimation(duration: 0.5)
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(newRegion)
                    currentMapSpan = span
                }
            } else {
                cameraPosition = .region(newRegion)
                currentMapSpan = span
            }
        } else {
            beginProgrammaticCameraAnimation(duration: 0.5)
            if animationsAllowed {
                withAnimation(.easeInOut(duration: 0.5)) {
                    region = MKCoordinateRegion(center: coordinate, span: span)
                }
            } else {
                region = MKCoordinateRegion(center: coordinate, span: span)
            }
        }

    }
}

// Custom modifier to conditionally show navigation title based on iOS version
struct NavigationTitleModifier: ViewModifier {
    let deviceName: String
    
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.navigationTitle(deviceName)
        }
    }
}

// MARK: - Visible devices calculation (iOS 17+)
extension iPhone_DeviceMapView {
    private func updateVisibleDeviceCount(with region: MKCoordinateRegion?) {
        guard let region = region else {
            visibleDeviceCount = 0
            return
        }
        var count = 0
        // Main device
        if let coord = animatedDeviceLocation, isCoordinate(coord, inside: region) {
            count += 1
        }
        // Other devices shown on the map (when inside the viewport)
        let others = deviceStore.devices.filter { $0.DeviceID != deviceID }
        for other in others {
            if let cached = cache.getLocation(for: other.DeviceID) {
                let coord = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                if isCoordinate(coord, inside: region) {
                    count += 1
                }
            }
        }
        visibleDeviceCount = count
    }
}

#Preview {
    let mockDevice = KnownDevice(name: "Test Device", deviceID: "0C7B98BD-F10F-40BC-AFFE-54484493EB25", color: .red)
    let mockLocation = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405) // Berlin
    let mockAccuracy = 15.0
    let mockTimestamp = Date()
    return NavigationView {
        iPhone_DeviceMapView(
            deviceID: mockDevice.DeviceID,
            previewDeviceLocation: mockLocation,
            previewDeviceAccuracy: mockAccuracy,
            previewDeviceTimestamp: mockTimestamp,
            onNavigateToDevice: { deviceID in
                debugLog("Preview: Would navigate to device \(deviceID)")
            }
        )
    }
}
