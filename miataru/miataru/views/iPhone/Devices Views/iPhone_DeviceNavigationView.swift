/*
 * iPhone_DeviceNavigationView.swift
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 *
 * Created by Daniel Kirstenpfad on 25.08.25.
 * Displays route between the user's device and a selected device.
 */

import SwiftUI
import MapKit
import Combine
import MiataruAPIClient

struct iPhone_DeviceNavigationView: View {
    var device: KnownDevice

    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var deviceStore = KnownDeviceStore.shared

    @Namespace private var mapScope
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var deviceCoordinate: CLLocationCoordinate2D?
    @State private var animatedUserCoordinate: CLLocationCoordinate2D?
    @State private var animatedDeviceCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var travelTime: String?
    @State private var distanceText: String?
    @State private var currentRegion: MKCoordinateRegion?
    @State private var hasSetInitialRegion = false
    @State private var userHasInteractedWithMap = false
    @State private var isUpdating = false
    @State private var currentMapCamera: MapCamera? = nil
    @State private var userHasRotatedMap = false
    @State private var isProgrammaticCameraChange = false
    @State private var isAutoCenteringEnabled = true
    @State private var timerCancellable: AnyCancellable? = nil
    @State private var deviceTimestamp: Date? = nil
    @State private var userTimestamp: Date? = nil
    @State private var isLoading: Bool = false
    @State private var now = Date()
    private let timeUpdateTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var isAutoRouteUpdateLocked: Bool = false
    @StateObject private var errorOverlayManager = ErrorOverlayManager()
    // Fit configuration: reduce padding around both markers when auto-centering
    private let fitPaddingMultiplier: Double = 1.6
    private let fitMinimumSpan = MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)

    var body: some View {
        VStack {
            Map(position: $mapPosition, scope: mapScope) {
                if let coord = animatedUserCoordinate {
                    Annotation("", coordinate: coord, anchor: .bottom) {
                        ZStack {
                            VStack(spacing: 0) {
                                if let ts = userTimestamp {
                                    Text(relativeTimeString(from: ts, to: now))
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
                                let myDevice = deviceStore.devices.first { $0.DeviceID == thisDeviceIDManager.shared.deviceID }
                                MiataruMapMarker(color: Color(myDevice?.DeviceColor ?? UIColor.systemBlue))
                                    .shadow(radius: 2)
                                ZStack {
                                    ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                                        ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                                            if x != 0 || y != 0 {
                                                Text(myDevice?.DeviceName.isEmpty == false ? (myDevice?.DeviceName ?? "") : thisDeviceIDManager.shared.deviceID)
                                                    .font(.callout)
                                                    .foregroundColor(Color(UIColor.systemBackground))
                                                    .padding(.top, 2)
                                                    .offset(x: CGFloat(x), y: CGFloat(y))
                                            }
                                        }
                                    }
                                    Text(myDevice?.DeviceName.isEmpty == false ? (myDevice?.DeviceName ?? "") : thisDeviceIDManager.shared.deviceID)
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
                        }
                        .offset(y: 10)
                    }
                }
                if let coord = animatedDeviceCoordinate {
                    Annotation("", coordinate: coord, anchor: .bottom) {
                        ZStack {
                            VStack(spacing: 0) {
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
                                        .zIndex(2)
                                }
                                MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                                    .shadow(radius: 2)
                                ZStack {
                                    ForEach([-2, -1, 0, 1, 2], id: \.self) { x in
                                        ForEach([-2, -1, 0, 1, 2], id: \.self) { y in
                                            if x != 0 || y != 0 {
                                                Text(device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName)
                                                    .font(.callout)
                                                    .foregroundColor(Color(UIColor.systemBackground))
                                                    .padding(.top, 2)
                                                    .offset(x: CGFloat(x), y: CGFloat(y))
                                            }
                                        }
                                    }
                                    Text(device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName)
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
                        }
                        .offset(y: 10)
                    }
                }
                if let polyline = route?.polyline {
                    MapPolyline(polyline)
                        .stroke(.blue, lineWidth: 4)
                }
            }
            .mapControls {
                MapCompass(heading: 1, size: 10)
                    .mapControlVisibility(.hidden)
            }
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in markUserInteraction() }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { _ in markUserInteraction() }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { _ in markUserInteraction() }
            )
            .onAppear {
                isAutoCenteringEnabled = true
                updateCoordinates(recenter: true)
                calculateRoute() // initial load only
                Task { await fetchTargetDeviceLocation(resetAndRecenter: false) }
                startAutoUpdate()
            }
            .onReceive(locationManager.$currentLocation) { _ in
                updateCoordinates()
            }
            .onReceive(cache.$locations) { _ in
                updateCoordinates()
            }
            .onReceive(timeUpdateTimer) { input in
                now = input
            }
            .onDisappear {
                stopAutoUpdate()
            }
            .onChange(of: settings.mapUpdateInterval) {
                restartAutoUpdate()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                let headingChanged = abs((currentMapCamera?.heading ?? 0) - context.camera.heading) > 0.1
                if isProgrammaticCameraChange {
                    // Ignore user interaction detection for programmatic updates
                    isProgrammaticCameraChange = false
                } else {
                    // User interaction is detected via gestures; here we only deduce rotation state
                    if abs(context.camera.heading) < 0.1 {
                        userHasRotatedMap = false
                    } else if headingChanged {
                        userHasRotatedMap = true
                    }
                }
                currentMapCamera = context.camera
                currentRegion = context.region
            }
            .overlay(alignment: .top) {
                if travelTime != nil || distanceText != nil {
                    if #available(iOS 26.0, *) {
                        HStack(spacing: 8) {
                            if let travelTime {
                                Image(systemName: "clock")
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                                Text(travelTime)
                            }
                            if travelTime != nil && distanceText != nil {
                                Image(systemName: transportSymbolName())
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                            }
                            if let distanceText { Text(distanceText) }
                        }
                        .font(.callout.monospacedDigit())
                        .padding(8)
                        .glassEffect(in: .rect(cornerRadius: 8))
                        .padding()
                    } else {
                        HStack(spacing: 8) {
                            if let travelTime {
                                Image(systemName: "clock")
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                                Text(travelTime)
                            }
                            if travelTime != nil && distanceText != nil {
                                Image(systemName: transportSymbolName())
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                            }
                            if let distanceText { Text(distanceText) }
                        }
                        .font(.callout.monospacedDigit())
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                scaleBarView()
            }
            .overlay(alignment: .topTrailing) {
                compassView()
            }

        }
        .overlay(
            ErrorOverlay(message: errorOverlayManager.message, visible: errorOverlayManager.visible)
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                reloadToolbarButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: openInAppleMaps) {
                    Image(systemName: "map")
                }
                .buttonStyle(.plain)
            }
        }
        .id(device.DeviceID)
        .onChange(of: device.DeviceID) {
            // Reset all device-related state when a new device is injected
            userCoordinate = nil
            deviceCoordinate = nil
            animatedUserCoordinate = nil
            animatedDeviceCoordinate = nil
            route = nil
            travelTime = nil
            distanceText = nil
            currentRegion = nil
            hasSetInitialRegion = false
            userHasInteractedWithMap = false
            currentMapCamera = nil
            userHasRotatedMap = false
            isProgrammaticCameraChange = false
            isAutoCenteringEnabled = true
            deviceTimestamp = nil
            isLoading = false
            // Fetch and recenter for the new device
            Task { await fetchTargetDeviceLocation(resetAndRecenter: true) }
        }
    }

    @ViewBuilder
    private func reloadToolbarButton() -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(isAutoRouteUpdateLocked ? Color.green : Color.primary)
                .symbolEffect(.rotate.clockwise.byLayer, options: .nonRepeating, isActive: isUpdating)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { isUpdating = true }
                    Task {
                        await fetchTargetDeviceLocation(resetAndRecenter: true)
                        withAnimation { isUpdating = false }
                    }
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    isAutoRouteUpdateLocked.toggle()
                    if isAutoRouteUpdateLocked {
                        Haptic.notifySuccess()
                        calculateRoute()
                    } else {
                        Haptic.notifyWarning()
                    }
                }
                .accessibilityLabel(Text(NSLocalizedString("reload", comment: "Reload target device location")))
                .accessibilityHint(Text(NSLocalizedString("reload_longpress_hint", comment: "Long-press to toggle automatic route updates.")))
        }
        .animation(.easeInOut(duration: 0.2), value: isAutoRouteUpdateLocked)
        .accessibilityAddTraits(.isButton)
    }

    private func updateCoordinates(recenter: Bool = false) {
        if let loc = locationManager.currentLocation {
            let coord = loc.coordinate
            let changed = userCoordinate?.latitude != coord.latitude || userCoordinate?.longitude != coord.longitude
            userCoordinate = coord
            userTimestamp = loc.timestamp
            if changed || animatedUserCoordinate == nil {
                withAnimation { animatedUserCoordinate = coord }
            }
        }
        if let cached = cache.getLocation(for: device.DeviceID) {
            let coord = CLLocationCoordinate2D(latitude: cached.latitude, longitude: cached.longitude)
            let changed = deviceCoordinate?.latitude != coord.latitude || deviceCoordinate?.longitude != coord.longitude
            deviceCoordinate = coord
            if changed || animatedDeviceCoordinate == nil {
                withAnimation { animatedDeviceCoordinate = coord }
            }
        }
        if let user = userCoordinate, let dest = deviceCoordinate,
           (!hasSetInitialRegion || recenter || isAutoCenteringEnabled) {
            let region = regionThatFits(user: user, dest: dest)
            isProgrammaticCameraChange = true
            withAnimation {
                mapPosition = .region(region)
            }
            hasSetInitialRegion = true
        }
    }

    private func regionThatFits(user: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: (user.latitude + dest.latitude) / 2,
                                            longitude: (user.longitude + dest.longitude) / 2)
        let baseLat = abs(user.latitude - dest.latitude)
        let baseLon = abs(user.longitude - dest.longitude)
        let paddedLat = max(baseLat * fitPaddingMultiplier, fitMinimumSpan.latitudeDelta)
        let paddedLon = max(baseLon * fitPaddingMultiplier, fitMinimumSpan.longitudeDelta)
        let span = MKCoordinateSpan(latitudeDelta: paddedLat, longitudeDelta: paddedLon)
        return MKCoordinateRegion(center: center, span: span)
    }

    private func calculateRoute() {
        guard let user = userCoordinate, let dest = deviceCoordinate else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: user))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        request.transportType = transportTypeFromSetting(settings.navigationTransportType)
        Task {
            do {
                let response = try await MKDirections(request: request).calculate()
                if let first = response.routes.first {
                    route = first
                    let formatter = DateComponentsFormatter()
                    formatter.unitsStyle = .short
                    travelTime = formatter.string(from: first.expectedTravelTime)
                    distanceText = formattedDistance(first.distance)
                } else {
                    route = nil
                    travelTime = nil
                    distanceText = nil
                    showErrorOverlay(
                        "No route found",
                        NSLocalizedString("route_not_found", comment: "Could not generate a route between the locations.")
                    )
                }
            } catch {
                route = nil
                travelTime = nil
                distanceText = nil
                showErrorOverlay(
                    "Route calculation failed: \(error.localizedDescription)",
                    NSLocalizedString("route_generation_failed", comment: "Route calculation failed. Please try again.")
                )
            }
        }
    }

    private func openInAppleMaps() {
        guard let dest = deviceCoordinate else { return }
        let source = MKMapItem.forCurrentLocation()
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        destination.name = device.DeviceName.isEmpty ? device.DeviceID : device.DeviceName
        var options: [String: Any] = [:]
        switch settings.navigationTransportType {
        case 0: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeWalking
        case 1: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDefault
        case 3: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeTransit
        default: options[MKLaunchOptionsDirectionsModeKey] = MKLaunchOptionsDirectionsModeDriving
        }
        MKMapItem.openMaps(with: [source, destination], launchOptions: options)
    }

    private func transportTypeFromSetting(_ value: Int) -> MKDirectionsTransportType {
        switch value {
        case 0: return .walking
        case 1: return .any
        case 3: return .transit
        default: return .automobile
        }
    }

    private func showErrorOverlay(_ debugMessage: String, _ userMessage: String) {
        debugLog("Error: \(debugMessage)")
        errorOverlayManager.show(message: userMessage)
    }

    // MARK: - Remote updates for the selected device only

    private func fetchTargetDeviceLocation(resetAndRecenter: Bool) async {
        guard let url = URL(string: settings.miataruServerURL) else { return }
        do {
            isLoading = true
            defer { isLoading = false }
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: url,
                forDeviceIDs: [device.DeviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID
            )
            if let loc = locations.first {
                let coordinate = CLLocationCoordinate2D(latitude: loc.Latitude, longitude: loc.Longitude)
                let changed = deviceCoordinate?.latitude != coordinate.latitude || deviceCoordinate?.longitude != coordinate.longitude
                // Update cache first to keep consistency with the rest of the app
                DeviceLocationCacheStore.shared.setLocation(
                    for: device.DeviceID,
                    latitude: loc.Latitude,
                    longitude: loc.Longitude,
                    accuracy: loc.HorizontalAccuracy,
                    timestamp: loc.TimestampDate
                )
                deviceCoordinate = coordinate
                deviceTimestamp = loc.TimestampDate
                if changed || animatedDeviceCoordinate == nil {
                    withAnimation { animatedDeviceCoordinate = coordinate }
                }
                // Always update coordinates to allow auto-centering when enabled
                updateCoordinates(recenter: resetAndRecenter)
                // Recalculate route only on explicit reload (or initial load elsewhere) 
                if resetAndRecenter {
                    calculateRoute()
                }
            } else {
                DeviceLocationCacheStore.shared.removeLocation(for: device.DeviceID)
            }
        } catch {
            debugLog("[iPhone_DeviceNavigationView] fetchTargetDeviceLocation error: \(error)")
        }
    }

    private func startAutoUpdate() {
        stopAutoUpdate()
        let interval = Double(settings.mapUpdateInterval)
        guard interval > 0 else { return }
        timerCancellable = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    await fetchTargetDeviceLocation(resetAndRecenter: false)
                    if isAutoRouteUpdateLocked {
                        calculateRoute()
                    }
                }
            }
    }

    private func stopAutoUpdate() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func restartAutoUpdate() {
        startAutoUpdate()
    }

    // MARK: - Map UI Helpers (Scale bar and Compass)

    private func markUserInteraction() {
        userHasInteractedWithMap = true
        isAutoCenteringEnabled = false
    }

    @ViewBuilder
    private func scaleBarView() -> some View {
        Group {
            if let region = currentRegion {
                Button(action: {
                    isAutoCenteringEnabled = true
                    resetZoomToFitBoth()
                }) {
                    MapScaleBar(region: region, width: 50)
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
            if userHasRotatedMap {
                let heading = currentMapCamera?.heading ?? 0
                Button(action: {
                    isAutoCenteringEnabled = true
                    alignMapToNorth()
                }) {
                    MapCompass(heading: heading, size: 40)
                }
                .padding([.top, .trailing], 10)
                .zIndex(3)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userHasRotatedMap)
    }

    private func alignMapToNorth() {
        guard let currentCamera = currentMapCamera else { return }
        let newCamera = MapCamera(
            centerCoordinate: currentCamera.centerCoordinate,
            distance: currentCamera.distance,
            heading: 0,
            pitch: currentCamera.pitch
        )
        isProgrammaticCameraChange = true
        withAnimation {
            mapPosition = .camera(newCamera)
            userHasRotatedMap = false
        }
    }

    private func resetZoomToFitBoth() {
        if let user = userCoordinate, let dest = deviceCoordinate {
            let region = regionThatFits(user: user, dest: dest)
            isProgrammaticCameraChange = true
            withAnimation(.easeInOut(duration: 0.5)) {
                mapPosition = .region(region)
            }
        }
    }
}

// MARK: - Distance Formatting
extension iPhone_DeviceNavigationView {
    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let usesMetric: Bool
        if #available(iOS 16.0, *) {
            usesMetric = Locale.current.measurementSystem == .metric
        } else {
            usesMetric = Locale.current.usesMetricSystem
        }
        let value: Double
        let unit: UnitLength
        if usesMetric {
            value = meters / 1000.0
            unit = .kilometers
        } else {
            value = meters / 1609.344
            unit = .miles
        }
        let measurement = Measurement(value: value, unit: unit)
        let formatter = MeasurementFormatter()
        formatter.locale = .current
        formatter.unitStyle = .short
        formatter.unitOptions = .providedUnit
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = 0
        numberFormatter.minimumFractionDigits = 0
        formatter.numberFormatter = numberFormatter
        return formatter.string(from: measurement)
    }

    private func transportSymbolName() -> String {
        switch settings.navigationTransportType {
        case 0: return "figure.walk"
        case 1: return "bicycle"
        case 2: return "car"
        case 3: return "tram"
        default: return "car"
        }
    }
}

