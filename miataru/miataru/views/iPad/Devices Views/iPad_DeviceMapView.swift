import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPad_DeviceMapView: View {
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
    @State private var now = Date() // Timer for relative time display
    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect() // Timer for updating 'now'
    @State private var showNetworkErrorIcon = false // Show network error icon on network issues
    @State private var screenSize: CGSize = .zero // Track screen size for off-screen arrows
    
    // Computed property to get the current device from the store
    private var device: KnownDevice? {
        deviceStore.devices.first { $0.DeviceID == deviceID }
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
            
            // Off-screen device arrows for all known devices (only shown when map is not rotated)
            if !screenSize.width.isZero && !screenSize.height.isZero,
               let region = currentRegion ?? cameraPosition.region {
                // Show arrow for the current device
                if let device = device,
                   let coordinate = deviceLocation {
                    OffScreenDeviceArrow(
                        deviceName: device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName,
                        deviceColor: Color(device.DeviceColor ?? UIColor.blue),
                        screenCenter: CGPoint(x: screenSize.width / 2, y: screenSize.height / 2),
                        deviceCoordinate: coordinate,
                        mapRegion: region,
                        screenSize: screenSize,
                        isMapRotated: userHasRotatedMap,
                        arrowIndex: 0,
                        totalArrows: 1,
                        behavior: .jumpToLocation,
                        onTap: {
                            // Animate to device location
                            withAnimation(.easeInOut(duration: 0.8)) {
                                if #available(iOS 17.0, *) {
                                    if let currentRegion = cameraPosition.region {
                                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentRegion.span))
                                    }
                                } else {
                                    // Fallback for older iOS versions
                                    self.region = MKCoordinateRegion(center: coordinate, span: self.region.span)
                                }
                            }
                        }
                    )
                }
                
                // Show arrows for other known devices that are outside the visible area (only if setting is enabled)
                if settings.showOffscreenArrowsForOtherDevices {
                    let offscreenDevices = deviceStore.devices.filter { $0.DeviceID != deviceID }
                    ForEach(Array(offscreenDevices.enumerated()), id: \.element.DeviceID) { index, otherDevice in
                        if let cached = DeviceLocationCacheStore.shared.getLocation(for: otherDevice.DeviceID) {
                            let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                            OffScreenDeviceArrow(
                                deviceName: otherDevice.DeviceName.isEmpty ? otherDevice.DeviceID : otherDevice.DeviceName,
                                deviceColor: Color(otherDevice.DeviceColor ?? UIColor.blue),
                                screenCenter: CGPoint(x: screenSize.width / 2, y: screenSize.height / 2),
                                deviceCoordinate: coordinate,
                                mapRegion: region,
                                screenSize: screenSize,
                                isMapRotated: userHasRotatedMap,
                                arrowIndex: index,
                                totalArrows: offscreenDevices.count,
                                behavior: .navigateToDevice,
                                onTap: {
                                    // Navigate to device detail view
                                    onNavigateToDevice?(otherDevice.DeviceID)
                                }
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
            } else {
                // Initialize animated marker position with preview or default
                animatedDeviceLocation = deviceLocation
            }
            // Set initial zoom level
            let span = spanForZoomLevel(settings.mapZoomLevel)
            currentMapSpan = span // Set initial zoom level
            
            // Use the best available location for map initialization
            let coordinate = bestAvailableLocation
            // iPad-specific: Force animations with longer duration for better visual feedback
            withAnimation(.easeInOut(duration: 1.0)) {
                region = MKCoordinateRegion(center: coordinate, span: span)
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                }
            }
            Task { await fetchLocation(resetZoomToSettings: true) }
            startAutoUpdate()
        }
        .onDisappear {
            stopAutoUpdate()
        }
        .onChange(of: settings.mapUpdateInterval) {
            restartAutoUpdate()
        }
        .onChange(of: settings.mapZoomLevel) {
            let span = spanForZoomLevel(settings.mapZoomLevel)
            // iPad-specific: Enhanced zoom animations
            withAnimation(.easeInOut(duration: 0.8)) {
                region.span = span
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: region.center, span: span))
                }
            }
        }
        // Track map camera and region changes for heading/zoom/region state
        .onMapCameraChange(frequency: .continuous) { context in
            let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
            let zoomChanged = abs((currentRegion?.span.latitudeDelta ?? 0) - context.region.span.latitudeDelta) > 0.0001 ||
                              abs((currentRegion?.span.longitudeDelta ?? 0) - context.region.span.longitudeDelta) > 0.0001
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
        }
        // Update 'now' every second for relative time display
        .onReceive(timeUpdateTimer) { input in
            now = input
        }
        // Show edit device sheet when requested
        .sheet(isPresented: $showEditDeviceSheet) {
            if let index = deviceStore.devices.firstIndex(where: { $0.DeviceID == deviceID }) {
                iPhone_EditDeviceView(device: $deviceStore.devices[index], isPresented: $showEditDeviceSheet)
            }
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
                    .transition(.opacity)
                    .zIndex(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showNetworkErrorIcon)
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
                        alignMapToNorth()
                    }) {
                        MapCompass(heading: heading, size: 40)
                    }
                    .padding([.top, .trailing], 10)
                    .zIndex(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userHasRotatedMap)
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        // Use the new Map API for iOS 17 and above
            if #available(iOS 17.0, *) {
                Map(position: $cameraPosition, scope: mapScope) {
                    // Show device marker if location is available
                    if let coordinate = animatedDeviceLocation, let device = device {
                        // Draw accuracy circle if enabled and accuracy is valid
                        if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracy, accuracy > 0 {
                            MapCircle(center: coordinate, radius: accuracy)
                                .foregroundStyle(Color(device.DeviceColor ?? UIColor.blue).opacity(0.2))
                        }
                        // Marker annotation for the device
                        let annotationID = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
                        Annotation("", coordinate: coordinate, anchor: .bottom) {
                            ZStack {
                                VStack(spacing: 0) {
                                    // Show relative timestamp above marker
                                    if let timestamp = deviceTimestamp {
                                        Text(relativeTimeString(from: timestamp, to: now))
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                            )
                                            .shimmering(active: isLoading)
                                            .shadow(radius: 2)
                                    }
                                    MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                                        .shadow(radius: 2)
                                    // Device name label below the marker with outline for readability
                                    ZStack {
                                        // Draw thicker outline (stroke) in all directions
                                        ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                                            ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                                                if x != 0 || y != 0 {
                                                    Text(annotationID)
                                                        .font(.callout)
                                                        .foregroundColor(Color(UIColor.systemBackground))
                                                        .padding(.top, 2)
                                                        .offset(x: CGFloat(x), y: CGFloat(y))
                                                }
                                            }
                                        }
                                        // Main text
                                        Text(annotationID)
                                            .font(.callout)
                                            .foregroundColor(Color(UIColor.label))
                                            .padding(.top, 2)
                                    }
                                }
                                    // Add a transparent rectangle to increase the tap area for the context menu
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .contentShape(Rectangle())
                                        .frame(width: 60, height: 80)
                                        .zIndex(1)
                                        .contextMenu {
                                            Button("edit_device") {
                                                showEditDeviceSheet = true
                                            }
                                        }
                            }
                            .offset(y:10)
                        }
                    }
                }
                .mapControls {
                    MapCompass(heading: 1, size: 10)
                        .mapControlVisibility(.hidden)
                }
                .ignoresSafeArea()
                .mapStyle(mapStyleFromSettings(settings.mapType))
            } else {
                // For iOS versions below 17, use a legacy map view implementation
                if let currentDevice = device {
                    iPad_LegacyMapViewRepresentable(region: $region, device: currentDevice, deviceLocation: deviceLocation, deviceAccuracy: deviceAccuracy, mapType: settings.mapType)
                        .ignoresSafeArea()
                }
            }

    }

    @ViewBuilder
    private func updateButton() -> some View {
        // Button to manually update device location
        Button("update") {
            Task {
                await fetchLocation(resetZoomToSettings: true)
            }
        }
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
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [deviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
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
                // Cache the new location
                DeviceLocationCacheStore.shared.setLocation(for: deviceID, latitude: loc.Latitude, longitude: loc.Longitude, accuracy: loc.HorizontalAccuracy, timestamp: loc.TimestampDate)
                if coordinateChanged {
                    // iPad-specific: Enhanced location change animations with explicit map movement
                    withAnimation(.easeInOut(duration: 1.2)) {
                        if #available(iOS 17.0, *) {
                            if resetZoomToSettings {
                                // On manual update: realign map to north (heading = 0)
                                let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                                let northCamera = MapCamera(centerCoordinate: coordinate, distance: currentMapCamera?.distance ?? 1000, heading: 0, pitch: currentMapCamera?.pitch ?? 0)
                                cameraPosition = .camera(northCamera)
                                currentMapSpan = settingsSpan // Also update currentMapSpan
                            } else {
                                // On automatic update: keep current orientation (heading) but animate map movement
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
                            } else {
                                // On automatic update: keep current zoom level but animate map movement
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
                showErrorOverlay("Encoding error: \(err.localizedDescription)", NSLocalizedString("encoding_error", comment: "Error encoding the request."))
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
            }
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Error loading location data"))
        }
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
        print("Error: \(debugMessage)")
        errorOverlayManager.show(message: userMessage)
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
        // iPad-specific: Enhanced compass alignment animation
        withAnimation(.easeInOut(duration: 1.0)) {
            cameraPosition = .camera(newCamera)
            userHasRotatedMap = false // Hide compass when aligned to north
        }
    }

    // Resets the map zoom to the value from settings
    private func resetZoomToSettings() {
        let span = spanForZoomLevel(settings.mapZoomLevel)
        let coordinate = bestAvailableLocation
        if #available(iOS 17.0, *) {
            let newRegion = MKCoordinateRegion(center: coordinate, span: span)
            // iPad-specific: Enhanced zoom reset animation
            withAnimation(.easeInOut(duration: 1.0)) {
                cameraPosition = .region(newRegion)
                currentMapSpan = span
            }
        } else {
            // iPad-specific: Enhanced zoom reset animation
            withAnimation(.easeInOut(duration: 1.0)) {
                region = MKCoordinateRegion(center: coordinate, span: span)
            }
        }

    }
}

#Preview {
    let mockDevice = KnownDevice(name: "Test Device", deviceID: "0C7B98BD-F10F-40BC-AFFE-54484493EB25", color: .red)
    let mockLocation = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405) // Berlin
    let mockAccuracy = 15.0
    let mockTimestamp = Date()
    return NavigationView {
        iPad_DeviceMapView(
            deviceID: mockDevice.DeviceID,
            previewDeviceLocation: mockLocation,
            previewDeviceAccuracy: mockAccuracy,
            previewDeviceTimestamp: mockTimestamp,
            onNavigateToDevice: { deviceID in
                print("Preview: Would navigate to device \(deviceID)")
            }
        )
    }
}
