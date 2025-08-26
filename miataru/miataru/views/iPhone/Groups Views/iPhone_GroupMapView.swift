/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_GroupMapView.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_GroupMapView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var locationManager = LocationManager.shared // Access to user's location
    
    @Namespace var mapScope
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Will be set in onAppear
        span: spanForZoomLevel(10) // Default zoom level for groups
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0), // Will be set in onAppear
            span: spanForZoomLevel(10)
        )
    )
    @State private var deviceLocations: [String: CLLocationCoordinate2D] = [:]
    @State private var animatedDeviceLocations: [String: CLLocationCoordinate2D] = [:] // Animierte Positionen für Marker
    @State private var deviceAccuracies: [String: Double] = [:]
    @State private var deviceTimestamps: [String: Date] = [:]
    @State private var isLoading = false
    @State private var currentRegion: MKCoordinateRegion? = nil
    @State private var currentMapCamera: MapCamera? = nil
    @StateObject private var errorOverlayManager = ErrorOverlayManager()
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var userHasRotatedMap = false // Track if user manually rotated the map
    @State private var now = Date() // Timer für relative Zeit
    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var editingDeviceID: String? = nil // State for the device being edited
    @State private var showEditDeviceSheet: Bool = false // Sheet trigger for editing device
    @State private var showNetworkErrorIcon = false // Show network error icon
    @State private var screenSize: CGSize = .zero // Track screen size for off-screen arrows
    
    private static let verticalPaddingFactorTop: CLLocationDegrees = 1.7
    private static let verticalPaddingFactorBottom: CLLocationDegrees = 1.4
    private static let horizontalPaddingFactor: CLLocationDegrees = 1.1
    
    // Computed property to get the best available location for map initialization
    private var bestAvailableLocation: CLLocationCoordinate2D {
        // First priority: Any device location from the group (if available)
        if let firstLocation = deviceLocations.values.first {
            return firstLocation
        }
        
        // Second priority: Cached device locations from the group
        for deviceID in groupDeviceIDs {
            if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
                return CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            }
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
    
    private func computeDevicesByEdge(in region: MKCoordinateRegion) -> [Edge: [(device: KnownDevice, coordinate: CLLocationCoordinate2D, onTap: () -> Void)]] {
        var devicesByEdge: [Edge: [(device: KnownDevice, coordinate: CLLocationCoordinate2D, onTap: () -> Void)]] = [:]
        for deviceID in groupDeviceIDs {
            if let device = deviceStore.devices.first(where: { $0.DeviceID == deviceID }),
               let coordinate = deviceLocations[deviceID],
               let edge = OffscreenDeviceEdgeHelper.edge(for: coordinate,
                                                        in: region,
                                                        screenSize: screenSize,
                                                        heading: currentMapCamera?.heading ?? 0) {
                let tap = {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        if #available(iOS 17.0, *) {
                            if let currentRegion = cameraPosition.region {
                                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentRegion.span))
                            }
                        } else {
                            self.region = MKCoordinateRegion(center: coordinate, span: self.region.span)
                        }
                    }
                }
                devicesByEdge[edge, default: []].append((device, coordinate, tap))
            }
        }
        return devicesByEdge
    }

    // Helper view for off-screen device arrows to avoid complex expressions in body
    @ViewBuilder
    private func offscreenDeviceArrowsView() -> some View {
        if let region = currentRegion ?? cameraPosition.region {
            let devicesByEdge = computeDevicesByEdge(in: region)
            let screenCenter = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
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
                            isMapRotated: false,
                            mapHeading: currentMapCamera?.heading ?? 0,
                            arrowIndex: index,
                            totalArrows: group.count,
                            behavior: .jumpToLocation,
                            onTap: info.onTap
                        )
                    }
                }
            }
        } else {
            EmptyView()
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // If there are no devices in the group, show a hint and do not request map/server
            if groupDeviceIDs.isEmpty {
                VStack {
                    Spacer()
                    Text("group_empty_add_devices_message")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else {
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
                ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
                // Network error icon (top left)
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
                
                // Off-screen device arrows (only shown when map is not rotated)
                if !screenSize.width.isZero && !screenSize.height.isZero {
                    offscreenDeviceArrowsView()
                }
                
                // Scale bar always on top
                Group {
                    if #available(iOS 17.0, *) {
                        if let region = currentRegion ?? cameraPosition.region {
                            Button(action: { resetZoomToFit() }) {
                                MapScaleBar(region: region, width: 50)
                            }
                            .buttonStyle(.plain)
                            .padding([.bottom, .trailing], 5)
                            .zIndex(2)
                        }
                    } else {
                        Button(action: { resetZoomToFit() }) {
                            MapScaleBar(region: region, width: 50)
                                .id("scalebar")
                        }
                        .buttonStyle(.plain)
                        .padding([.bottom, .trailing], 5)
                        .zIndex(2)
                    }
                }
                
                // Compass top right
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
        }
        .navigationTitle(group.groupName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                groupEditButton()
            }
        }
        .adaptiveToolbarBackground()
        .onAppear {
            if !groupDeviceIDs.isEmpty {
                // Caching: Immediately show cached locations
                for deviceID in groupDeviceIDs {
                    if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
                        let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                        deviceLocations[deviceID] = coordinate
                        // Initialize animated location with cached location
                        animatedDeviceLocations[deviceID] = coordinate
                        deviceAccuracies[deviceID] = cached.accuracy
                        deviceTimestamps[deviceID] = cached.timestamp
                        now = Date() // Update time immediately for each hit
                    }
                }
                // Animierte Marker-Positionen initialisieren
                animatedDeviceLocations = deviceLocations
                
                // Set initial map position based on available locations
                let bestLocation = bestAvailableLocation
                let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(center: bestLocation, span: span))
                }
                
                Task { await fetchAllLocations() }
                startAutoUpdate()
            }
        }
        .onDisappear {
            stopAutoUpdate()
        }
        .onChange(of: settings.mapUpdateInterval) { _, _ in
            if !groupDeviceIDs.isEmpty {
                restartAutoUpdate()
            }
        }
        .onChange(of: group.deviceIDs) { _, _ in
            // Remove all locations that no longer belong to the group
            let validIDs = Set(groupDeviceIDs)
            deviceLocations = deviceLocations.filter { validIDs.contains($0.key) }
            deviceAccuracies = deviceAccuracies.filter { validIDs.contains($0.key) }
            deviceTimestamps = deviceTimestamps.filter { validIDs.contains($0.key) }
            updateMapRegionToFitDevices()
        }
        .onChange(of: group.id) { _, _ in
            // Reset state when switching to a different group
            deviceLocations.removeAll()
            deviceAccuracies.removeAll()
            deviceTimestamps.removeAll()
            animatedDeviceLocations.removeAll()
            
            // Clear any existing timer
            stopAutoUpdate()
            
            // Re-initialize the view for the new group
            if !groupDeviceIDs.isEmpty {
                // Caching: Immediately show cached locations
                for deviceID in groupDeviceIDs {
                    if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
                        let coordinate = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                        deviceLocations[deviceID] = coordinate
                        // Initialize animated location with cached location
                        animatedDeviceLocations[deviceID] = coordinate
                        deviceAccuracies[deviceID] = cached.accuracy
                        deviceTimestamps[deviceID] = cached.timestamp
                        now = Date() // Update time immediately for each hit
                    }
                }
                // Animierte Marker-Positionen initialisieren
                animatedDeviceLocations = deviceLocations
                
                // Set initial map position based on available locations
                let bestLocation = bestAvailableLocation
                let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(center: bestLocation, span: span))
                }
                
                Task { await fetchAllLocations() }
                startAutoUpdate()
            }
        }
        // TODO: this is not working as expected, the marker is not animated / compile crashes
        /*.onChange(of: deviceLocations) { newValue in
            // Für alle deviceIDs, die sich geändert haben, animiere die Position
            for (deviceID, newCoord) in newValue {
                let oldCoord = animatedDeviceLocations[deviceID]
                if oldCoord?.latitude != newCoord.latitude || oldCoord?.longitude != newCoord.longitude {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        animatedDeviceLocations[deviceID] = newCoord
                    }
                }
            }
            // Entferne Marker, die nicht mehr existieren
            let validIDs = Set(newValue.keys)
            animatedDeviceLocations = animatedDeviceLocations.filter { validIDs.contains($0.key) }
        }*/
        .onMapCameraChange(frequency: .continuous) { context in
            let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
            let zoomChanged = abs((currentRegion?.span.latitudeDelta ?? 0) - context.region.span.latitudeDelta) > 0.0001 ||
                              abs((currentRegion?.span.longitudeDelta ?? 0) - context.region.span.longitudeDelta) > 0.0001
            if abs(context.camera.heading) < 0.1 {
                userHasRotatedMap = false
            } else if headingChanged && !isLoading {
                userHasRotatedMap = true
            }
            if headingChanged || zoomChanged {
                currentMapCamera = context.camera
                currentRegion = context.region
            }
            // Always update region for off-screen arrows
            currentRegion = context.region
        }
        .onReceive(timeUpdateTimer) { input in
            now = input
        }
        // Sheet for editing device
        .sheet(isPresented: $showEditDeviceSheet) {
            if let deviceID = editingDeviceID, let index = deviceStore.devices.firstIndex(where: { $0.DeviceID == deviceID }) {
                iPhone_EditDeviceView(device: $deviceStore.devices[index], isPresented: $showEditDeviceSheet)
            }
        }
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        Map(position: $cameraPosition, scope: mapScope) {
            // Show all devices in the group
            ForEach(groupDeviceIDs, id: \.self) { deviceID in
                if let device = deviceStore.devices.first(where: { $0.DeviceID == deviceID }),
                   let coordinate = animatedDeviceLocations[deviceID] {
                    // Accuracy circle
                    if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracies[deviceID], accuracy > 0 {
                        MapCircle(center: coordinate, radius: accuracy)
                            .foregroundStyle(Color(device.DeviceColor ?? UIColor.blue).opacity(0.2))
                    }
                    // Device marker
                    let annotationID = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        ZStack {
                            VStack(spacing: 0) {
                                // Show timestamp if available
                                if let timestamp = deviceTimestamps[deviceID] {
                                    Text(relativeTimeString(from: timestamp, to: now, unitsStyle: .abbreviated))
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
                                        .zIndex(2)
                                }
                                MiataruMapMarker(
                                    color: Color(device.DeviceColor ?? UIColor.blue),
                                    pulsing: groupDeviceIDs.count <= 5
                                )
                                    .shadow(radius: 2)
                                ZStack {
                                    // Draw device name/ID with shadow for better readability
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
                                    Text(annotationID)
                                        .font(.callout)
                                        .foregroundColor(Color(UIColor.label))
                                        .padding(.top, 2)
                                }
                            }
                            Rectangle()
                                .foregroundColor(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 60, height: 80)
                                .zIndex(1)
                                .contextMenu {
                                    Button {
                                        editingDeviceID = deviceID
                                        showEditDeviceSheet = true
                                    } label: {
                                        Label("edit_device", systemImage: "pencil")
                                    }
                                }
                        }.offset(y: 10)
                    }
                }
            }
        }
        .mapControls {
            MapCompass(heading: 1, size: 10)
                .mapControlVisibility(.hidden)
        }
        .ignoresSafeArea()
        .mapStyle(mapStyleFromSettings(settings.mapType))

    }
    
    @ViewBuilder
    private func groupEditButton() -> some View {
        NavigationLink(destination: iPhone_GroupDetailView(group: group)) {
            Image(systemName: "pencil")
                .accessibilityLabel(Text(NSLocalizedString("group_detailview_edit", comment: "Edit group details")))
        }
    }
    
    private var groupDeviceIDs: [String] {
        return Array(group.deviceIDs)
    }
    
    private func fetchAllLocations() async {
        guard let url = URL(string: settings.miataruServerURL), !groupDeviceIDs.isEmpty else {
            if groupDeviceIDs.isEmpty {
                // No devices: No server request, no error message
                return
            }
            showErrorOverlay("Invalid server URL or no devices in group", NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"))
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
            // First attempt: Multi-device call
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: groupDeviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            // Update device locations
            for location in locations {
                let coordinate = CLLocationCoordinate2D(latitude: location.Latitude, longitude: location.Longitude)
                deviceLocations[location.Device] = coordinate
                // Update animated location immediately to ensure marker moves
                animatedDeviceLocations[location.Device] = coordinate
                deviceAccuracies[location.Device] = location.HorizontalAccuracy
                deviceTimestamps[location.Device] = location.TimestampDate
                now = Date() // Update time immediately for each hit
                // Caching: Save new location
                DeviceLocationCacheStore.shared.setLocation(for: location.Device, latitude: location.Latitude, longitude: location.Longitude, accuracy: location.HorizontalAccuracy, timestamp: location.TimestampDate)
            }
            // Update map region to fit all devices
            updateMapRegionToFitDevices()
            // Missing devices: Show error overlay
            let foundIDs = Set(locations.map { $0.Device })
            let missingIDs = Set(groupDeviceIDs).subtracting(foundIDs)
            for missingID in missingIDs {
                let deviceName = deviceStore.devices.first(where: { $0.DeviceID == missingID })?.DeviceName ?? missingID
                let userMessage = String(format: NSLocalizedString("group_map_could_fetch_device_location", comment: "Could not fetch location for device: %@"), deviceName)
                showErrorOverlay("No location data for device: \(missingID)", userMessage)
            }
        } catch {
            // Multi-device call failed: Try single device requests
            var anySuccess = false
            for deviceID in groupDeviceIDs {
                do {
                    let locations = try await MiataruAPIClient.getLocation(
                        serverURL: url,
                        forDeviceIDs: [deviceID],
                        requestingDeviceID: thisDeviceIDManager.shared.deviceID
                    )
                    if let location = locations.first {
                        let coordinate = CLLocationCoordinate2D(latitude: location.Latitude, longitude: location.Longitude)
                        deviceLocations[location.Device] = coordinate
                        // Update animated location immediately to ensure marker moves
                        animatedDeviceLocations[location.Device] = coordinate
                        deviceAccuracies[location.Device] = location.HorizontalAccuracy
                        deviceTimestamps[location.Device] = location.TimestampDate
                        anySuccess = true
                    }
                } catch let error as MiataruAPIClient.APIError {
                    // Error for this device: Find name and show
                    switch error {
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
                    default:
                        let deviceName = deviceStore.devices.first(where: { $0.DeviceID == deviceID })?.DeviceName ?? deviceID
                        let userMessage = String(format: NSLocalizedString("group_map_could_fetch_device_location", comment: "Could not fetch location for device: %@"), deviceName)
                        showErrorOverlay("Failed to fetch location for device: \(deviceID)", userMessage)
                    }
                } catch {
                    let deviceName = deviceStore.devices.first(where: { $0.DeviceID == deviceID })?.DeviceName ?? deviceID
                    let userMessage = String(format: NSLocalizedString("group_map_could_fetch_device_location", comment: "Could not fetch location for device: %@"), deviceName)
                    showErrorOverlay("Failed to fetch location for device: \(deviceID)", userMessage)
                }
            }
            if anySuccess {
                updateMapRegionToFitDevices()
            }
        }
    }
    
    private func updateMapRegionToFitDevices() {
        let validIDs = Set(groupDeviceIDs)
        let validCoordinates = deviceLocations.filter { validIDs.contains($0.key) }.values.filter { $0.latitude != 0 && $0.longitude != 0 }
        
        // If no valid coordinates, use fallback location
        guard !validCoordinates.isEmpty else {
            let fallbackCoord = fallbackLocation
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: fallbackCoord, span: span))
            }
            return
        }
        if settings.groupsZoomToFit {
            let minDelta: CLLocationDegrees = 0.01 // Minimum span for zoom
            let verticalPaddingFactorTop = Self.verticalPaddingFactorTop
            let verticalPaddingFactorBottom = Self.verticalPaddingFactorBottom
            let horizontalPaddingFactor = Self.horizontalPaddingFactor
            if validCoordinates.count == 1 {
                let coordinate = validCoordinates.first!
                let span = MKCoordinateSpan(latitudeDelta: minDelta, longitudeDelta: minDelta)
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                }
            } else {
                let latitudes = validCoordinates.map { $0.latitude }
                let longitudes = validCoordinates.map { $0.longitude }
                let minLat = latitudes.min()!
                let maxLat = latitudes.max()!
                let minLon = longitudes.min()!
                let maxLon = longitudes.max()!
                let centerLat = (minLat + maxLat) / 2
                let centerLon = (minLon + maxLon) / 2
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                let rawLatDelta = maxLat - minLat
                let rawLonDelta = maxLon - minLon
                if rawLatDelta == 0 && rawLonDelta == 0 {
                    let span = MKCoordinateSpan(latitudeDelta: minDelta, longitudeDelta: minDelta)
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                    return
                }
                // Different padding factors for top/bottom
                let paddedLatDelta = (maxLat - centerLat) * verticalPaddingFactorTop + (centerLat - minLat) * verticalPaddingFactorBottom
                let avgLatRadians = centerLat * .pi / 180
                let cosLat = cos(avgLatRadians)
                let safeCosLat = abs(cosLat) < 0.00001 ? 0.00001 : cosLat
                let paddedLonDelta = (rawLonDelta * horizontalPaddingFactor) / safeCosLat
                let latitudeDelta = max(paddedLatDelta, minDelta)
                let longitudeDelta = max(paddedLonDelta, minDelta)
                debugLog("[Map] latitudeDelta: \(latitudeDelta), longitudeDelta: \(longitudeDelta)")
                if !latitudeDelta.isFinite || !longitudeDelta.isFinite || latitudeDelta < 0.0001 || longitudeDelta < 0.0001 {
                    debugLog("[Map] Invalid region, setting fallback")
                    let span = MKCoordinateSpan(latitudeDelta: minDelta, longitudeDelta: minDelta)
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                    return
                }
                let span = MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                }
            }
        }
    }
    
    private func handleAPIError(_ error: MiataruAPIClient.APIError) {
        switch error {
        case .invalidURL:
            showErrorOverlay("Invalid server URL", NSLocalizedString("server_url_invalid", comment: "The server URL is invalid."))
        case .invalidResponse(_):
            showErrorOverlay("Invalid server response", NSLocalizedString("server_response_invalid", comment: "The server response was invalid."))
        case .encodingError(let err):
            showErrorOverlay("Encoding error: \(err.localizedDescription)", NSLocalizedString("encoding_error", comment: "Error encoding the request."))
        case .decodingError(let err):
            showErrorOverlay("Error processing the response: \(err.localizedDescription)", NSLocalizedString("decoding_error", comment: "Error processing the server response."))
        case .requestFailed(let err):
            showErrorOverlay("Network error: \(err.localizedDescription)", NSLocalizedString("network_error", comment: "Network error. Please check your internet connection."))
        }
    }
    
    private func startAutoUpdate() {
        stopAutoUpdate()
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { await fetchAllLocations() }
            }
    }
    
    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    private func restartAutoUpdate() {
        startAutoUpdate()
    }
    
    private func showErrorOverlay(_ debugMessage: String, _ userMessage: String) {
        debugLog("Error: \(debugMessage)")
        errorOverlayManager.show(message: userMessage)
    }
    
    private func alignMapToNorth() {
        let coordinate = currentMapCamera?.centerCoordinate
        guard let center = coordinate, let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: currentCamera.distance,
            heading: 0, // North
            pitch: currentCamera.pitch
        )
        withAnimation {
            cameraPosition = .camera(newCamera)
            userHasRotatedMap = false // Hide compass when aligned to north
        }
    }
    
    private func resetZoomToFit() {
        userHasRotatedMap = false
        let validCoordinates = deviceLocations.values.filter { coordinate in
            coordinate.latitude != 0 && coordinate.longitude != 0
        }
        guard !validCoordinates.isEmpty else { return }
        let verticalPaddingFactorTop = Self.verticalPaddingFactorTop
        let verticalPaddingFactorBottom = Self.verticalPaddingFactorBottom
        let horizontalPaddingFactor = Self.horizontalPaddingFactor
        if validCoordinates.count == 1 {
            let coordinate = validCoordinates.first!
            let span = spanForZoomLevel(settings.mapZoomLevel)
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
            }
        } else {
            let latitudes = validCoordinates.map { $0.latitude }
            let longitudes = validCoordinates.map { $0.longitude }
            let minLat = latitudes.min()!
            let maxLat = latitudes.max()!
            let minLon = longitudes.min()!
            let maxLon = longitudes.max()!
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            //let rawLatDelta = maxLat - minLat
            let rawLonDelta = maxLon - minLon
            // Different padding factors for top/bottom
            let paddedLatDelta = (maxLat - centerLat) * verticalPaddingFactorTop + (centerLat - minLat) * verticalPaddingFactorBottom
            let avgLatRadians = centerLat * .pi / 180
            let cosLat = cos(avgLatRadians)
            let safeCosLat = abs(cosLat) < 0.00001 ? 0.00001 : cosLat
            let correctedLonDelta = (rawLonDelta * horizontalPaddingFactor) / safeCosLat
            let minLatDelta = max(paddedLatDelta, 0.01)
            let minLonDelta = max(correctedLonDelta, 0.01)
            let span = MKCoordinateSpan(
                latitudeDelta: minLatDelta,
                longitudeDelta: minLonDelta
            )
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
            }
        }
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("0C7B98BD-F10F-40BC-AFFE-54484493EB25")
    group.addDevice("0DBE3740-AF3F-4792-92A8-FAC0C7B220B0")
    
    let deviceStore = KnownDeviceStore.shared
    deviceStore.devices = [
        KnownDevice(name: "iPhone 13", deviceID: "0C7B98BD-F10F-40BC-AFFE-54484493EB25", color: .red),
        KnownDevice(name: "iPad Pro", deviceID: "0DBE3740-AF3F-4792-92A8-FAC0C7B220B0", color: .green)
    ]
    
    return NavigationView {
        iPhone_GroupMapView(group: group)
    }
    .environmentObject(deviceStore)
} 
