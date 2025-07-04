import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_DeviceMapView: View {
    let device: KnownDevice
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
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack {
                mapSection()
            }
            errorOverlay()
            // Eigene ScaleBar unten rechts für alle iOS-Versionen
            if #available(iOS 17.0, *) {
                if let region = cameraPosition.region {
                    MapScaleBar(region: region, width: 100)
                        .padding([.bottom, .trailing], 16)
                }
            } else {
                MapScaleBar(region: region, width: 100)
                    .padding([.bottom, .trailing], 16)
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
    }
    
    @ViewBuilder
    private func mapSection() -> some View {
        if #available(iOS 17.0, *) {
            Map(position: $cameraPosition) {
                if let coordinate = deviceLocation {
                    if let accuracy = deviceAccuracy, accuracy > 0 {
                        MapCircle(center: coordinate, radius: accuracy)
                            .foregroundStyle(Color.blue.opacity(0.2))
                    }
                    Marker(device.DeviceName, systemImage: "mappin", coordinate: coordinate)
                        .tint(Color(device.DeviceColor ?? .blue))
                }
            }
            .onMapCameraChange { context in
                // Aktuellen Zoom-Level aus der Karte speichern
                currentMapSpan = context.region.span
            }
            .ignoresSafeArea()
            .mapStyle(mapStyleFromSettings(settings.mapType))
        } else {
            iPhone_LegacyMapViewRepresentable(region: $region, device: device, deviceLocation: deviceLocation, deviceAccuracy: deviceAccuracy, mapType: settings.mapType)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func errorOverlay() -> some View {
        if errorOverlayVisible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(errorMessage)
                        .padding(16)
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                Spacer()
            }
            .transition(.scale.combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: errorOverlayVisible)
            .zIndex(1)
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
            showErrorOverlay("Ungültige Server-URL oder DeviceID", NSLocalizedString("server_or_deviceid_invalid", comment: "Fehler: Server oder DeviceID ungültig"))
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
                            // Bei manuellem Update: Zoom-Level aus Settings verwenden
                            let settingsSpan = spanForZoomLevel(settings.mapZoomLevel)
                            cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: settingsSpan))
                            currentMapSpan = settingsSpan // Auch currentMapSpan aktualisieren
                        } else {
                            // Bei automatischem Update: Aktuellen Zoom-Level beibehalten
                            cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: currentMapSpan))
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
                showErrorOverlay("Keine Standortdaten gefunden", NSLocalizedString("no_location_data_found", comment: "Kein Standort verfügbar"))
            }
        } catch let error as MiataruAPIClient.APIError {
            // Differenzierte Fehlerbehandlung
            switch error {
            case .invalidURL:
                showErrorOverlay("Ungültige Server-URL", NSLocalizedString("server_url_invalid", comment: "Die Server-URL ist ungültig."))
            case .invalidResponse(_):
                showErrorOverlay("Ungültige Serverantwort", NSLocalizedString("server_response_invalid", comment: "Die Antwort des Servers war ungültig."))
            case .encodingError(let err):
                showErrorOverlay("Fehler beim Kodieren: \(err.localizedDescription)", NSLocalizedString("encoding_error", comment: "Fehler beim Kodieren der Anfrage."))
            case .decodingError(let err):
                showErrorOverlay("Fehler beim Verarbeiten der Antwort: \(err.localizedDescription)", NSLocalizedString("decoding_error", comment: "Fehler beim Verarbeiten der Serverantwort."))
            case .requestFailed(let err):
                showErrorOverlay("Netzwerkfehler: \(err.localizedDescription)", NSLocalizedString("network_error", comment: "Netzwerkfehler. Bitte Internetverbindung prüfen."))
            }
        } catch {
            showErrorOverlay(error.localizedDescription, NSLocalizedString("error_loading_locationdata", comment: "Fehler beim Laden der Standortdaten"))
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
}

// Hilfsfunktion für MapStyle
@available(iOS 17.0, *)
fileprivate func mapStyleFromSettings(_ mapType: Int) -> MapStyle {
    switch mapType {
    case 2:
        return .hybrid(elevation: .automatic)
    case 3:
        return .imagery(elevation: .automatic)
    default:
        return .standard(elevation: .automatic)
    }
}

// Hilfsfunktion für Zoom-Level (in km)
fileprivate func spanForZoomLevel(_ zoomLevel: Int) -> MKCoordinateSpan {
    // 1° Breitengrad ≈ 111 km
    let km = Double(zoomLevel)
    let delta = km / 111.0
    return MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
}

// Hilfsfunktion um aktuellen Zoom-Level aus Span zu berechnen
fileprivate func currentZoomLevelFromSpan(_ span: MKCoordinateSpan) -> Int {
    // Durchschnitt aus latitude und longitude delta
    let avgDelta = (span.latitudeDelta + span.longitudeDelta) / 2.0
    // Umrechnung zurück zu km: 1° ≈ 111 km
    let km = avgDelta * 111.0
    return Int(round(km))
}

// --- Maßstabsleiste (Scale Bar) ---
struct MapScaleBar: View {
    let region: MKCoordinateRegion
    let width: CGFloat

    var body: some View {
        let distance = distanceForWidth(region: region, width: width)
        let label = distanceLabel(for: distance)
        HStack(spacing: 4) {
            Rectangle()
                .frame(width: width, height: 4)
                .foregroundColor(.primary)
                .cornerRadius(2)
            Text(label)
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .padding(8)
        .background(.thinMaterial)
        .cornerRadius(8)
    }

    func distanceForWidth(region: MKCoordinateRegion, width: CGFloat) -> CLLocationDistance {
        // Berechne die Distanz, die 'width' Punkte auf der Karte abdecken
        let mapViewWidth = UIScreen.main.bounds.width
        let span = region.span
        let center = region.center
        let loc1 = CLLocation(latitude: center.latitude, longitude: center.longitude - span.longitudeDelta / 2 * Double(width / mapViewWidth))
        let loc2 = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta / 2 * Double(width / mapViewWidth))
        return loc1.distance(from: loc2)
    }

    func distanceLabel(for distance: CLLocationDistance) -> String {
        if distance > 1000 {
            return String(format: "%.0f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
}


