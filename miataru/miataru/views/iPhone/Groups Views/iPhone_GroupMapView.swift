import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_GroupMapView: View {
    @ObservedObject var group: DeviceGroup
    @StateObject private var deviceStore = KnownDeviceStore.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @Namespace var mapScope
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco as default
        span: spanForZoomLevel(10) // Default zoom level for groups
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: spanForZoomLevel(10)
        )
    )
    @State private var deviceLocations: [String: CLLocationCoordinate2D] = [:]
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
    @State private var editingDeviceID: String? = nil // State für das zu editierende Device
    @State private var showEditDeviceSheet: Bool = false // Sheet-Trigger
    @State private var showNetworkErrorIcon = false // Show network error icon
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Wenn keine Devices in der Gruppe sind, Hinweis anzeigen und keine Map/Serveranfrage
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
                updateButton()
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .onAppear {
            if !groupDeviceIDs.isEmpty {
                // Caching: Sofort gecachte Locations anzeigen
                for deviceID in groupDeviceIDs {
                    if let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) {
                        deviceLocations[deviceID] = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
                        deviceAccuracies[deviceID] = cached.accuracy
                        deviceTimestamps[deviceID] = cached.timestamp
                        now = Date() // <-- Zeit sofort aktualisieren (bei jedem Treffer)
                    }
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
        .onChange(of: group.deviceIDs.count) { _, newCount in
            if newCount > 0 {
                // Devices wurden hinzugefügt: Karte anzeigen und Locations sofort aktualisieren
                Task { await fetchAllLocations() }
                startAutoUpdate()
            }
        }
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
        }
        .onReceive(timeUpdateTimer) { input in
            now = input
        }
        // Sheet für Edit Device
        .sheet(isPresented: $showEditDeviceSheet) {
            if let deviceID = editingDeviceID, let index = deviceStore.devices.firstIndex(where: { $0.DeviceID == deviceID }) {
                iPhone_EditDeviceView(device: $deviceStore.devices[index], isPresented: $showEditDeviceSheet)
            }
        }
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        if #available(iOS 17.0, *) {
            Map(position: $cameraPosition, scope: mapScope) {
                // Show all devices in the group
                ForEach(groupDeviceIDs, id: \.self) { deviceID in
                    if let device = deviceStore.devices.first(where: { $0.DeviceID == deviceID }),
                       let coordinate = deviceLocations[deviceID] {
                        
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
                                    }
                                    
                                    // Custom map marker
                                    MiataruMapMarker(
                                        color: Color(device.DeviceColor ?? UIColor.blue),
                                        pulsing: groupDeviceIDs.count <= 5
                                    )
                                        .shadow(radius: 2)
                                    // Label für Gerätename unter dem Pin mit Stroke und Systemfarben
                                    ZStack {
                                        // Stroke (Outline) – automatisch kontrastierend zur Umgebung
                                        Text(device.DeviceName)
                                            .font(.footnote)
                                            .foregroundColor(Color(UIColor.label).isLight() ? Color.black : Color.white)
                                            .padding(.top, 2)
                                            .overlay(
                                                Text(annotationID)
                                                    .font(.footnote)
                                                    .foregroundColor(Color(UIColor.systemBackground))
                                                    .padding(.top, 2)
                                                    .blur(radius: 1.2)
                                                    .shadow(radius: 4)
                                            )
                                        // Haupttext
                                        Text(annotationID)
                                            .font(.footnote)
                                            .foregroundColor(Color(UIColor.label))
                                            .padding(.top, 2)
                                            .shadow(radius: 4)
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
            .ignoresSafeArea()
            .mapStyle(mapStyleFromSettings(settings.mapType))
        } else {
            // Legacy map view for iOS versions below 17
            iPhone_LegacyGroupMapViewRepresentable(
                region: $region,
                group: group,
                deviceStore: deviceStore,
                deviceLocations: deviceLocations,
                deviceAccuracies: deviceAccuracies,
                mapType: settings.mapType,
                settings: settings
            )
            .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private func updateButton() -> some View {
        NavigationLink(destination: iPhone_GroupDetailView(group: group)) {
            Text("group_detailview_edit")
        }
    }
    
    private var groupDeviceIDs: [String] {
        return Array(group.deviceIDs)
    }
    
    private func fetchAllLocations() async {
        guard let url = URL(string: settings.miataruServerURL), !groupDeviceIDs.isEmpty else {
            if groupDeviceIDs.isEmpty {
                // Keine Devices: Keine Serveranfrage, keine Fehlermeldung
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
            // Erster Versuch: Multi-Device-Call
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: groupDeviceIDs,
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            // Update device locations
            for location in locations {
                let coordinate = CLLocationCoordinate2D(latitude: location.Latitude, longitude: location.Longitude)
                deviceLocations[location.Device] = coordinate
                deviceAccuracies[location.Device] = location.HorizontalAccuracy
                deviceTimestamps[location.Device] = location.TimestampDate
                now = Date() // <-- Zeit sofort aktualisieren (bei jedem Treffer)
                // Caching: Neue Location speichern
                DeviceLocationCacheStore.shared.setLocation(for: location.Device, latitude: location.Latitude, longitude: location.Longitude, accuracy: location.HorizontalAccuracy, timestamp: location.TimestampDate)
            }
            // Update map region to fit all devices
            updateMapRegionToFitDevices()
            // Fehlende Devices: ErrorOverlay anzeigen
            let foundIDs = Set(locations.map { $0.Device })
            let missingIDs = Set(groupDeviceIDs).subtracting(foundIDs)
            for missingID in missingIDs {
                let deviceName = deviceStore.devices.first(where: { $0.DeviceID == missingID })?.DeviceName ?? missingID
                let userMessage = String(format: NSLocalizedString("group_map_could_fetch_device_location", comment: "Could not fetch location for device: %@"), deviceName)
                showErrorOverlay("No location data for device: \(missingID)", userMessage)
            }
        } catch {
            // Multi-Device-Call fehlgeschlagen: Einzelabfragen
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
                        deviceAccuracies[location.Device] = location.HorizontalAccuracy
                        deviceTimestamps[location.Device] = location.TimestampDate
                        anySuccess = true
                    }
                } catch let error as MiataruAPIClient.APIError {
                    // Fehler für dieses Device: Name suchen und anzeigen
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
        let validCoordinates = deviceLocations.values.filter { coordinate in
            coordinate.latitude != 0 && coordinate.longitude != 0
        }
        
        guard !validCoordinates.isEmpty else { return }
        
        // Check if zoom to fit is enabled in settings
        if settings.groupsZoomToFit {
            if validCoordinates.count == 1 {
                // Single device: center on it with default zoom
                let coordinate = validCoordinates.first!
                let span = spanForZoomLevel(settings.mapZoomLevel)
                if #available(iOS 17.0, *) {
                    if userHasRotatedMap, let currentCamera = currentMapCamera {
                        // Preserve user's rotation and pitch
                        let newCamera = MapCamera(
                            centerCoordinate: coordinate,
                            distance: currentCamera.distance,
                            heading: currentCamera.heading,
                            pitch: currentCamera.pitch
                        )
                        cameraPosition = .camera(newCamera)
                    } else {
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                    }
                } else {
                    region = MKCoordinateRegion(center: coordinate, span: span)
                }
            } else {
                // Multiple devices: fit all in view with generous padding
                let latitudes = validCoordinates.map { $0.latitude }
                let longitudes = validCoordinates.map { $0.longitude }
                
                let minLat = latitudes.min()!
                let maxLat = latitudes.max()!
                let minLon = longitudes.min()!
                let maxLon = longitudes.max()!
                
                let centerLat = (minLat + maxLat) / 2
                let centerLon = (minLon + maxLon) / 2
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                
                // Calculate the raw differences
                let rawLatDelta = maxLat - minLat
                let rawLonDelta = maxLon - minLon
                
                // Add generous padding (50% instead of 20%)
                let paddedLatDelta = rawLatDelta * 1.5
                let paddedLonDelta = rawLonDelta * 1.5
                
                // For longitude, account for latitude-dependent scaling
                let avgLatRadians = centerLat * .pi / 180
                let correctedLonDelta = paddedLonDelta / cos(avgLatRadians)
                
                // Ensure minimum spans for visibility and add extra buffer
                let minLatDelta = max(paddedLatDelta, 0.05) // Increased minimum
                let minLonDelta = max(correctedLonDelta, 0.05) // Increased minimum
                
                // Add extra buffer for very small differences
                let finalLatDelta = minLatDelta < 0.1 ? minLatDelta * 2 : minLatDelta
                let finalLonDelta = minLonDelta < 0.1 ? minLonDelta * 2 : minLonDelta
                
                let span = MKCoordinateSpan(
                    latitudeDelta: finalLatDelta,
                    longitudeDelta: finalLonDelta
                )
                
                if #available(iOS 17.0, *) {
                    if userHasRotatedMap, let currentCamera = currentMapCamera {
                        // Preserve user's rotation and pitch
                        let newCamera = MapCamera(
                            centerCoordinate: center,
                            distance: currentCamera.distance,
                            heading: currentCamera.heading,
                            pitch: currentCamera.pitch
                        )
                        cameraPosition = .camera(newCamera)
                    } else {
                        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
                    }
                } else {
                    region = MKCoordinateRegion(center: center, span: span)
                }
            }
        }
        // If zoom to fit is disabled, don't change the current map position
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
        print("Error: \(debugMessage)")
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
            userHasRotatedMap = false // Kompass ausblenden, wenn wieder nach Norden
        }
    }
    
    private func resetZoomToFit() {
        // Always allow manual reset, regardless of settings
        // Reset the user rotation flag since this is a manual reset
        userHasRotatedMap = false
        
        let validCoordinates = deviceLocations.values.filter { coordinate in
            coordinate.latitude != 0 && coordinate.longitude != 0
        }
        
        guard !validCoordinates.isEmpty else { return }
        
        if validCoordinates.count == 1 {
            // Single device: center on it with default zoom
            let coordinate = validCoordinates.first!
            let span = spanForZoomLevel(settings.mapZoomLevel)
            if #available(iOS 17.0, *) {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
            } else {
                region = MKCoordinateRegion(center: coordinate, span: span)
            }
        } else {
            // Multiple devices: fit all in view with generous padding
            let latitudes = validCoordinates.map { $0.latitude }
            let longitudes = validCoordinates.map { $0.longitude }
            
            let minLat = latitudes.min()!
            let maxLat = latitudes.max()!
            let minLon = longitudes.min()!
            let maxLon = longitudes.max()!
            
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            
            // Calculate the raw differences
            let rawLatDelta = maxLat - minLat
            let rawLonDelta = maxLon - minLon
            
            // Add generous padding (50% instead of 20%)
            let paddedLatDelta = rawLatDelta * 1.5
            let paddedLonDelta = rawLonDelta * 1.5
            
            // For longitude, account for latitude-dependent scaling
            let avgLatRadians = centerLat * .pi / 180
            let correctedLonDelta = paddedLonDelta / cos(avgLatRadians)
            
            // Ensure minimum spans for visibility and add extra buffer
            let minLatDelta = max(paddedLatDelta, 0.05) // Increased minimum
            let minLonDelta = max(correctedLonDelta, 0.05) // Increased minimum
            
            // Add extra buffer for very small differences
            let finalLatDelta = minLatDelta < 0.1 ? minLatDelta * 2 : minLatDelta
            let finalLonDelta = minLonDelta < 0.1 ? minLonDelta * 2 : minLonDelta
            
            let span = MKCoordinateSpan(
                latitudeDelta: finalLatDelta,
                longitudeDelta: finalLonDelta
            )
            
            if #available(iOS 17.0, *) {
                cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
            } else {
                region = MKCoordinateRegion(center: center, span: span)
            }
        }
    }
}

// Legacy map view for iOS versions below 17
struct iPhone_LegacyGroupMapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let group: DeviceGroup
    let deviceStore: KnownDeviceStore
    let deviceLocations: [String: CLLocationCoordinate2D]
    let deviceAccuracies: [String: Double]
    let mapType: Int
    @ObservedObject var settings: SettingsManager = SettingsManager.shared

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        mapView.showsUserLocation = false
        mapView.setRegion(region, animated: false)
        mapView.mapType = mapTypeFromSettings(mapType)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)
        uiView.mapType = mapTypeFromSettings(mapType)
        uiView.removeAnnotations(uiView.annotations)
        uiView.removeOverlays(uiView.overlays)
        
        // Add annotations and overlays for all devices in the group
        for deviceID in group.deviceIDs {
            if let device = deviceStore.devices.first(where: { $0.DeviceID == deviceID }),
               let coordinate = deviceLocations[deviceID] {
                
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = device.DeviceName
                uiView.addAnnotation(annotation)
                
                // Accuracy circle
                if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracies[deviceID], accuracy > 0 {
                    let circle = MKCircle(center: coordinate, radius: accuracy)
                    uiView.addOverlay(circle)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: iPhone_LegacyGroupMapViewRepresentable
        init(_ parent: iPhone_LegacyGroupMapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.blue.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.blue.withAlphaComponent(0.4)
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

fileprivate func mapTypeFromSettings(_ mapType: Int) -> MKMapType {
    switch mapType {
    case 2:
        return .hybrid
    case 3:
        return .satellite
    default:
        return .standard
    }
}

#Preview {
    let group = DeviceGroup(name: "Test Group")
    group.addDevice("device1")
    group.addDevice("device2")
    
    let deviceStore = KnownDeviceStore.shared
    deviceStore.devices = [
        KnownDevice(name: "iPhone 13", deviceID: "device1", color: .red),
        KnownDevice(name: "iPad Pro", deviceID: "device2", color: .green)
    ]
    
    return NavigationView {
        iPhone_GroupMapView(group: group)
    }
    .environmentObject(deviceStore)
} 
