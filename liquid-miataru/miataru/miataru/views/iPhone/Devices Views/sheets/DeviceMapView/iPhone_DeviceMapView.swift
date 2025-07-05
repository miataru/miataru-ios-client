import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_DeviceMapView: View {
    let device: KnownDevice
    @Namespace var mapScope
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco als Standard
        span: spanForZoomLevel(1) // Default, wird in onAppear überschrieben
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
    @State private var deviceAccuracy: Double? // in Metern
    @State private var deviceTimestamp: Date? = nil
    @ObservedObject private var settings = SettingsManager.shared
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var errorOverlayVisible = false
    @State private var currentMapSpan: MKCoordinateSpan = spanForZoomLevel(1) // Aktueller Zoom-Level der Karte
    @State private var mapInteractionID = UUID()
    @State private var currentRegion: MKCoordinateRegion? = nil
    @State private var currentMapCamera: MapCamera? = nil // Speichert die aktuelle Kamera inkl. Heading
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Karte und Fehler-Overlay
            VStack {
                mapSection()
            }
            ErrorOverlay(message: errorMessage, visible: errorOverlayVisible)
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
        .navigationTitle(device.DeviceName)
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
            // Zoom-Level initial setzen
            let span = spanForZoomLevel(settings.mapZoomLevel)
            currentMapSpan = span // Initialen Zoom-Level setzen
            
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
            if headingChanged || zoomChanged {
                currentMapCamera = context.camera
                currentRegion = context.region
                currentMapSpan = context.region.span
            }
        }
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        if #available(iOS 17.0, *) {
            Map(position: $cameraPosition,scope: mapScope) {
                if let coordinate = deviceLocation {
                    if let accuracy = deviceAccuracy, accuracy > 0 {
                        MapCircle(center: coordinate, radius: accuracy)
                            .foregroundStyle(Color.blue.opacity(0.2))
                    }
                    let annotationID = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
                    // Overlay für Zeitangabe
                    Annotation(annotationID, coordinate: coordinate, anchor: .bottom) {
                        if let timestamp = deviceTimestamp {
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
                                .offset(y: -38) // Wert ggf. anpassen, damit es über dem Marker schwebt
                        }
                    }
                    // Nativer Marker
                    Marker(annotationID, systemImage: "mappin", coordinate: coordinate)
                        .tint(Color(device.DeviceColor ?? .blue))
                }
            }
            .ignoresSafeArea()
            .mapStyle(mapStyleFromSettings(settings.mapType))
        } else {
            iPhone_LegacyMapViewRepresentable(region: $region, device: device, deviceLocation: deviceLocation, deviceAccuracy: deviceAccuracy, mapType: settings.mapType)
                .ignoresSafeArea()
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
        guard let url = URL(string: settings.miataruServerURL), !device.DeviceID.isEmpty else {
            showErrorOverlay("Ungültige Server-URL oder DeviceID", NSLocalizedString("server_or_deviceid_invalid", comment: "Error: Server or DeviceID invalid"))
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [device.DeviceID],
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
                            // Bei manuellem Update: Karte wieder nach Norden ausrichten (heading = 0)
                            let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                            let northCamera = MapCamera(centerCoordinate: coordinate, distance: currentMapCamera?.distance ?? 1000, heading: 0, pitch: currentMapCamera?.pitch ?? 0)
                            cameraPosition = .camera(northCamera)
                            currentMapSpan = settingsSpan // Auch currentMapSpan aktualisieren
                        } else {
                            // Bei automatischem Update: Aktuelle Ausrichtung (heading) beibehalten
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
                            // Bei manuellem Update: Zoom-Level aus Settings verwenden
                            let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                            region = MKCoordinateRegion(center: coordinate, span: settingsSpan)
                        } else {
                            // Bei automatischem Update: Aktuellen Zoom-Level beibehalten
                            let currentZoomLevel = currentZoomLevelFromSpan(region.span)
                            let currentSpan = spanForZoomLevel(currentZoomLevel)
                            region = MKCoordinateRegion(center: coordinate, span: currentSpan)
                        }
                    }
                }
            } else {
                showErrorOverlay("Keine Standortdaten gefunden", NSLocalizedString("no_location_data_found", comment: "No location available"))
            }
        } catch let error as MiataruAPIClient.APIError {
            // Differenzierte Fehlerbehandlung
            switch error {
            case .invalidURL:
                showErrorOverlay("Ungültige Server-URL", NSLocalizedString("server_url_invalid", comment: "The server URL is invalid."))
            case .invalidResponse(_):
                showErrorOverlay("Ungültige Serverantwort", NSLocalizedString("server_response_invalid", comment: "The server response was invalid."))
            case .encodingError(let err):
                showErrorOverlay("Fehler beim Kodieren: \(err.localizedDescription)", NSLocalizedString("encoding_error", comment: "Error encoding the request."))
            case .decodingError(let err):
                showErrorOverlay("Fehler beim Verarbeiten der Antwort: \(err.localizedDescription)", NSLocalizedString("decoding_error", comment: "Error processing the server response."))
            case .requestFailed(let err):
                showErrorOverlay("Netzwerkfehler: \(err.localizedDescription)", NSLocalizedString("network_error", comment: "Network error. Please check your internet connection."))
            }
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Error loading location data"))
        }
    }

    private func startAutoUpdate() {
        stopAutoUpdate() // Falls schon ein Timer läuft
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
        print("Fehler: \(debugMessage)") // Debug-Ausgabe
        errorMessage = userMessage
        withAnimation {
            errorOverlayVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                errorOverlayVisible = false
            }
        }
    }

    private func alignMapToNorth() {
        let coordinate = deviceLocation ?? currentMapCamera?.centerCoordinate
        guard let center = coordinate, let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: center,
            distance: currentCamera.distance,
            heading: 0, // Norden
            pitch: currentCamera.pitch
        )
        withAnimation {
            cameraPosition = .camera(newCamera)
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

    // Hilfsfunktion für relative Zeitangabe
    private func relativeTimeString(from date: Date?) -> String {
        guard let date = date else { return "–" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

