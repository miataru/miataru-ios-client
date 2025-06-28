import SwiftUI
import MapKit
import MiataruAPIClient
import Combine

struct iPhone_DeviceMapView: View {
    let device: KnownDevice
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco als Standard
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
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
    
    var body: some View {
        VStack {
            if #available(iOS 17.0, *) {
                Map(position: $cameraPosition) {
                    if let coordinate = deviceLocation {
                        Annotation(device.DeviceName, coordinate: coordinate) {
                            ZStack {
                                // Accuracy-Kreis (blau, halbtransparent)
                                if let accuracy = deviceAccuracy, accuracy > 0 {
                                    let diameter = min(CGFloat(accuracy / region.metersPerPoint()), 300)
                                    Circle()
                                        .fill(Color.blue.opacity(0.2))
                                        .frame(width: diameter, height: diameter)
                                }
                                // Pin-View
                                PinView(color: Color(device.DeviceColor ?? UIColor.blue))
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            } else {
                Map(coordinateRegion: $region, annotationItems: deviceLocation != nil ? [device] : []) { device in
                    MapAnnotation(coordinate: deviceLocation!) {
                        ZStack {
                            // Accuracy-Kreis (blau, halbtransparent)
                            if let accuracy = deviceAccuracy, accuracy > 0 {
                                let diameter = min(CGFloat(accuracy / region.metersPerPoint()), 300)
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: diameter, height: diameter)
                            }
                            // Pin-View
                            PinView(color: Color(device.DeviceColor ?? UIColor.blue))
                        }
                    }
                }
                .ignoresSafeArea()
            }
        }
        .navigationTitle(device.DeviceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isLoading ? "Lädt..." : "Aktualisieren") {
                    Task {
                        await fetchLocation()
                    }
                }
                .disabled(isLoading)
                //.foregroundColor(Color(device.DeviceColor ?? UIColor.blue))
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .alert("Fehler", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task { await fetchLocation() }
            startAutoUpdate()
        }
        .onDisappear {
            stopAutoUpdate()
        }
        .onChange(of: settings.mapUpdateInterval) { _ in
            restartAutoUpdate()
        }
    }
    
    private func fetchLocation() async {
        guard let url = URL(string: settings.miataruServerURL), !device.DeviceID.isEmpty else {
            errorMessage = "Ungültige Server-URL oder DeviceID."
            showError = true
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
                        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
                    } else {
                        region.center = coordinate
                    }
                }
            } else {
                errorMessage = "Keine Standortdaten gefunden."
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func startAutoUpdate() {
        stopAutoUpdate() // Falls schon ein Timer läuft
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task { await fetchLocation() }
            }
    }

    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func restartAutoUpdate() {
        startAutoUpdate()
    }
}


// MARK: - PinView
struct PinView: View {
    let color: Color
    var body: some View {
        VStack(spacing: 0) {
            // Kopf
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(radius: 3)
            // Nadel
            Rectangle()
                .fill(Color.gray)
                .frame(width: 4, height: 24)
                .cornerRadius(2)
                .offset(y: -2)
        }
    }
}

#Preview {
    let device = KnownDevice(name: "Demo", deviceID: "BF0160F5-4138-402C-A5F0-DEB1AA1F4216", color: .blue)
    iPhone_DeviceMapView(device: device)
}

// Hilfs-Extension für die Umrechnung Meter -> Punkt auf der Map
extension MKCoordinateRegion {
    func metersPerPoint() -> Double {
        // Annäherung: 1 Punkt = x Meter auf der aktuellen Zoomstufe
        // 1° Breitengrad = ca. 111.000 Meter
        let mapWidthInMeters = self.span.longitudeDelta * 111_000.0 * cos(self.center.latitude * .pi / 180)
        let mapWidthInPoints: Double =  UIScreen.main.bounds.width
        return mapWidthInMeters / mapWidthInPoints
    }
}
