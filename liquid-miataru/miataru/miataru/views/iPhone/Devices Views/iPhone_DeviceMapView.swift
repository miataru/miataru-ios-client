import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_DeviceMapView: View {
    let deviceID: String // Change from device to deviceID
    // Preview-Parameter (optional)
    var previewDeviceLocation: CLLocationCoordinate2D? = nil
    var previewDeviceAccuracy: Double? = nil
    var previewDeviceTimestamp: Date? = nil
    @Namespace var mapScope
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco as default
        span: spanForZoomLevel(1) // Default, will be overwritten in onAppear
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: spanForZoomLevel(1)
        )
    )
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var deviceLocation: CLLocationCoordinate2D?
    @State private var deviceAccuracy: Double? // in Meters
    @State private var deviceTimestamp: Date? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var deviceStore = KnownDeviceStore.shared // Add device store
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var errorOverlayVisible = false
    @State private var currentMapSpan: MKCoordinateSpan = spanForZoomLevel(1) // Aktueller Zoom-Level der Karte
    @State private var mapInteractionID = UUID()
    @State private var currentRegion: MKCoordinateRegion? = nil
    @State private var currentMapCamera: MapCamera? = nil // Speichert die aktuelle Kamera inkl. Heading
    @State private var userHasRotatedMap = false // Track if user manually rotated the map
    @StateObject private var errorOverlayManager = ErrorOverlayManager()
    @State private var showEditDeviceSheet = false
    @State private var now = Date() // Timer für relative Zeit
    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Computed property to get the current device from store
    private var device: KnownDevice? {
        deviceStore.devices.first { $0.DeviceID == deviceID }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Karte und Fehler-Overlay
            VStack {
                mapSection()
            }
            ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
            // ScaleBar immer ganz oben
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
            // Kompass oben rechts
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
        .navigationTitle(device?.DeviceName ?? "Unknown Device")
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
            // Preview-Parameter übernehmen, falls gesetzt
            if let previewLoc = previewDeviceLocation {
                deviceLocation = previewLoc
            }
            if let previewAcc = previewDeviceAccuracy {
                deviceAccuracy = previewAcc
            }
            if let previewTime = previewDeviceTimestamp {
                deviceTimestamp = previewTime
            }
            // Zoom-Level initial setzen
            let span = spanForZoomLevel(settings.mapZoomLevel)
            currentMapSpan = span // Set initial zoom level
            
            if let coordinate = deviceLocation {
                region = MKCoordinateRegion(center: coordinate, span: span)
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: span))
                }
            } else {
                // Default: San Francisco
                let defaultCoord = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                region = MKCoordinateRegion(center: defaultCoord, span: span)
                if #available(iOS 17.0, *) {
                    cameraPosition = .region(MKCoordinateRegion(center: defaultCoord, span: span))
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
            region.span = span
            if #available(iOS 17.0, *) {
                cameraPosition = .region(MKCoordinateRegion(center: region.center, span: span))
            }
        }
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
        }
        .onReceive(timeUpdateTimer) { input in
            now = input
        }
        .sheet(isPresented: $showEditDeviceSheet) {
            if let index = deviceStore.devices.firstIndex(where: { $0.DeviceID == deviceID }) {
                iPhone_EditDeviceView(device: $deviceStore.devices[index], isPresented: $showEditDeviceSheet)
            }
        }
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        // Use the new Map API for iOS 17 and above
        if #available(iOS 17.0, *) {
            Map(position: $cameraPosition,scope: mapScope) {
                // If the device location is available, show it on the map
                if let coordinate = deviceLocation, let device = device {
                    // 1. Genauigkeitskreis als separates Map-Element
                    if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracy, accuracy > 0 {
                        MapCircle(center: coordinate, radius: accuracy)
                            .foregroundStyle(Color(device.DeviceColor ?? UIColor.blue).opacity(0.2))
                    }
                    // 2. Marker-Annotation (ohne Kreis)
                    let annotationID = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
                   
                    Annotation(annotationID, coordinate: coordinate, anchor: .bottom) {
                        ZStack {
                            VStack(spacing: 0) {
                                // Show the timestamp as a relative time if available
                                if let timestamp = deviceTimestamp {
                                    Text(relativeTimeString(from: timestamp, to: now))
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
                                // Show the custom map marker for the device
                                MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                                    .shadow(radius: 2)
                            }
                            // Add a transparent rectangle to increase the tap area for the context menu
                            Rectangle()
                                .foregroundColor(.clear)
                                .contentShape(Rectangle())
                                .frame(width: 60, height: 80)
                                .zIndex(1)
                                .contextMenu {
                                    Button {
                                        showEditDeviceSheet = true
                                    } label: {
                                        Label("edit_device", systemImage: "pencil")
                                    }
                                }
                        }.offset(y:10)
                    }
                }
            }
            .ignoresSafeArea()
            .mapStyle(mapStyleFromSettings(settings.mapType))
        } else {
            // For iOS versions below 17, use a legacy map view implementation
            if let currentDevice = device {
                iPhone_LegacyMapViewRepresentable(region: $region, device: currentDevice, deviceLocation: deviceLocation, deviceAccuracy: deviceAccuracy, mapType: settings.mapType)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func updateButton() -> some View {
        //Button(isLoading ? "loading" : "update") {
        Button("update") {
            Task {
                await fetchLocation(resetZoomToSettings: true)
            }
        }
        //.disabled(isLoading)
    }
    
    private func fetchLocation(resetZoomToSettings: Bool = false) async {
        guard let url = URL(string: settings.miataruServerURL), !deviceID.isEmpty else {
            showErrorOverlay("Invalid server URL or DeviceID", NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"))
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [deviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            if let loc = locations.first {
                let coordinate = CLLocationCoordinate2D(latitude: loc.Latitude, longitude: loc.Longitude)
                deviceLocation = coordinate
                deviceAccuracy = loc.HorizontalAccuracy
                deviceTimestamp = loc.TimestampDate
                withAnimation {
                    if #available(iOS 17.0, *) {
                        if resetZoomToSettings {
                            // On manual update: realign map to north (heading = 0)
                            let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                            let northCamera = MapCamera(centerCoordinate: coordinate, distance: currentMapCamera?.distance ?? 1000, heading: 0, pitch: currentMapCamera?.pitch ?? 0)
                            cameraPosition = .camera(northCamera)
                            currentMapSpan = settingsSpan // Also update currentMapSpan
                        } else {
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
                        } else {
                            // On automatic update: keep current zoom level
                            let currentZoomLevel = currentZoomLevelFromSpan(region.span)
                            let currentSpan = spanForZoomLevel(currentZoomLevel)
                            region = MKCoordinateRegion(center: coordinate, span: currentSpan)
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
            case .requestFailed(let err):
                showErrorOverlay("Network error: \(err.localizedDescription)", NSLocalizedString("network_error", comment: "Network error. Please check your internet connection."))
            }
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Error loading location data"))
        }
    }

    private func startAutoUpdate() {
        stopAutoUpdate() // If a timer is already running
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { await fetchLocation(resetZoomToSettings: false) }
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
        let coordinate = deviceLocation ?? currentMapCamera?.centerCoordinate
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

    private func resetZoomToSettings() {
        let span = spanForZoomLevel(settings.mapZoomLevel)
        if let coordinate = deviceLocation {
            if #available(iOS 17.0, *) {
                let newRegion = MKCoordinateRegion(center: coordinate, span: span)
                cameraPosition = .region(newRegion)
                currentMapSpan = span
            } else {
                region = MKCoordinateRegion(center: coordinate, span: span)
            }
        }
    }
}

#Preview {
    let mockDevice = KnownDevice(name: "Test Device", deviceID: "1234567890", color: .red)
    let mockLocation = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.405) // Berlin
    let mockAccuracy = 15.0
    let mockTimestamp = Date()
    return NavigationView {
        iPhone_DeviceMapView(
            deviceID: mockDevice.DeviceID,
            previewDeviceLocation: mockLocation,
            previewDeviceAccuracy: mockAccuracy,
            previewDeviceTimestamp: mockTimestamp
        )
    }
}
