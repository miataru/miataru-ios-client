import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_GroupMapView: View {
    let group: DeviceGroup
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
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Map and error overlay
            VStack {
                mapSection()
            }
            ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
            
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
                    Button(action: {
                        alignMapToNorth()
                    }) {
                        MapCompass(heading: heading, size: 40)
                    }
                    .padding([.top, .trailing], 10)
                    .zIndex(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
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
            Task { await fetchAllLocations() }
            startAutoUpdate()
        }
        .onDisappear {
            stopAutoUpdate()
        }
        .onChange(of: settings.mapUpdateInterval) {
            restartAutoUpdate()
        }
        .onMapCameraChange(frequency: .continuous) { context in
            let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
            let zoomChanged = abs((currentRegion?.span.latitudeDelta ?? 0) - context.region.span.latitudeDelta) > 0.0001 ||
                              abs((currentRegion?.span.longitudeDelta ?? 0) - context.region.span.longitudeDelta) > 0.0001
            if headingChanged || zoomChanged {
                currentMapCamera = context.camera
                currentRegion = context.region
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
                        if let accuracy = deviceAccuracies[deviceID], accuracy > 0 {
                            MapCircle(center: coordinate, radius: accuracy)
                                .foregroundStyle(Color(device.DeviceColor ?? UIColor.blue).opacity(0.2))
                        }
                        
                        // Device marker
                        let annotationID = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
                        Annotation(annotationID, coordinate: coordinate, anchor: .bottom) {
                            ZStack {
                                VStack(spacing: 0) {
                                    // Show timestamp if available
                                    if let timestamp = deviceTimestamps[deviceID] {
                                        Text(relativeTimeString(from: timestamp))
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                            )
                                            .shadow(radius: 2)
                                    }
                                    
                                    // Custom map marker
                                    MiataruMapMarker(color: Color(device.DeviceColor ?? UIColor.blue))
                                        .shadow(radius: 2)
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
                mapType: settings.mapType
            )
            .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private func updateButton() -> some View {
        Button("update") {
            Task {
                await fetchAllLocations()
            }
        }
    }
    
    private var groupDeviceIDs: [String] {
        return Array(group.deviceIDs)
    }
    
    private func fetchAllLocations() async {
        guard let url = URL(string: settings.miataruServerURL), !groupDeviceIDs.isEmpty else {
            showErrorOverlay("Invalid server URL or no devices in group", NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"))
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
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
            }
            
            // Update map region to fit all devices
            updateMapRegionToFitDevices()
            
        } catch let error as MiataruAPIClient.APIError {
            handleAPIError(error)
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Error loading location data"))
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
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                } else {
                    region = MKCoordinateRegion(center: coordinate, span: span)
                }
            } else {
                // Multiple devices: fit all in view
                let latitudes = validCoordinates.map { $0.latitude }
                let longitudes = validCoordinates.map { $0.longitude }
                
                let minLat = latitudes.min()!
                let maxLat = latitudes.max()!
                let minLon = longitudes.min()!
                let maxLon = longitudes.max()!
                
                let centerLat = (minLat + maxLat) / 2
                let centerLon = (minLon + maxLon) / 2
                let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
                
                let latDelta = (maxLat - minLat) * 1.2 // Add 20% padding
                let lonDelta = (maxLon - minLon) * 1.2
                let span = MKCoordinateSpan(latitudeDelta: max(latDelta, 0.01), longitudeDelta: max(lonDelta, 0.01))
                
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
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
        let center = currentMapCamera?.centerCoordinate ?? region.center
        guard let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: currentCamera.distance,
            heading: 0, // North
            pitch: currentCamera.pitch
        )
        withAnimation {
            cameraPosition = .camera(newCamera)
        }
    }
    
    private func resetZoomToFit() {
        // Always allow manual reset, regardless of settings
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
            // Multiple devices: fit all in view
            let latitudes = validCoordinates.map { $0.latitude }
            let longitudes = validCoordinates.map { $0.longitude }
            
            let minLat = latitudes.min()!
            let maxLat = latitudes.max()!
            let minLon = longitudes.min()!
            let maxLon = longitudes.max()!
            
            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            
            let latDelta = (maxLat - minLat) * 1.2 // Add 20% padding
            let lonDelta = (maxLon - minLon) * 1.2
            let span = MKCoordinateSpan(latitudeDelta: max(latDelta, 0.01), longitudeDelta: max(lonDelta, 0.01))
            
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
                if let accuracy = deviceAccuracies[deviceID], accuracy > 0 {
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