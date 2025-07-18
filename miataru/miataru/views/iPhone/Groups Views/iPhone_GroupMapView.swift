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
        .onChange(of: group.deviceIDs) { _, _ in
            // Entferne alle Locations, die nicht mehr zur Gruppe gehören
            let validIDs = Set(groupDeviceIDs)
            deviceLocations = deviceLocations.filter { validIDs.contains($0.key) }
            deviceAccuracies = deviceAccuracies.filter { validIDs.contains($0.key) }
            deviceTimestamps = deviceTimestamps.filter { validIDs.contains($0.key) }
            updateMapRegionToFitDevices()
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
                                MiataruMapMarker(
                                    color: Color(device.DeviceColor ?? UIColor.blue),
                                    pulsing: groupDeviceIDs.count <= 5
                                )
                                    .shadow(radius: 2)
                                ZStack {
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
        .ignoresSafeArea()
        .mapStyle(mapStyleFromSettings(settings.mapType))
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
        let validIDs = Set(groupDeviceIDs)
        let validCoordinates = deviceLocations.filter { validIDs.contains($0.key) }.values.filter { $0.latitude != 0 && $0.longitude != 0 }
        guard !validCoordinates.isEmpty else { return }
        if settings.groupsZoomToFit {
            let minDelta: CLLocationDegrees = 0.01 // wie bisher
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
                let paddedLatDelta = rawLatDelta * 1.01
                let avgLatRadians = centerLat * .pi / 180
                let cosLat = cos(avgLatRadians)
                let safeCosLat = abs(cosLat) < 0.00001 ? 0.00001 : cosLat
                let paddedLonDelta = (rawLonDelta * 1.01) / safeCosLat
                let latitudeDelta = max(paddedLatDelta, minDelta)
                let longitudeDelta = max(paddedLonDelta, minDelta)
                print("[Map] latitudeDelta: \(latitudeDelta), longitudeDelta: \(longitudeDelta)")
                if !latitudeDelta.isFinite || !longitudeDelta.isFinite || latitudeDelta < 0.0001 || longitudeDelta < 0.0001 {
                    print("[Map] Ungültige Region, setze Fallback")
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
        userHasRotatedMap = false
        let validCoordinates = deviceLocations.values.filter { coordinate in
            coordinate.latitude != 0 && coordinate.longitude != 0
        }
        guard !validCoordinates.isEmpty else { return }
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
            let rawLatDelta = maxLat - minLat
            let rawLonDelta = maxLon - minLon
            let paddedLatDelta = rawLatDelta * 1.01
            let paddedLonDelta = rawLonDelta * 1.01
            let avgLatRadians = centerLat * .pi / 180
            let cosLat = cos(avgLatRadians)
            let safeCosLat = abs(cosLat) < 0.00001 ? 0.00001 : cosLat
            let correctedLonDelta = paddedLonDelta / safeCosLat
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
