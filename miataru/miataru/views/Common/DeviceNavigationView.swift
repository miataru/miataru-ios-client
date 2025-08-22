/*
 * DeviceNavigationView.swift
 * miataru
 *
 * Displays route between the user's device and a selected device.
 */

import SwiftUI
import MapKit

struct DeviceNavigationView: View {
    var device: KnownDevice

    @ObservedObject private var cache = DeviceLocationCacheStore.shared
    @ObservedObject private var locationManager = LocationManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    @Namespace private var mapScope
    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var deviceCoordinate: CLLocationCoordinate2D?
    @State private var animatedUserCoordinate: CLLocationCoordinate2D?
    @State private var animatedDeviceCoordinate: CLLocationCoordinate2D?
    @State private var route: MKRoute?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var travelTime: String?
    @State private var currentRegion: MKCoordinateRegion?
    @State private var hasSetInitialRegion = false
    @State private var userHasInteractedWithMap = false

    var body: some View {
        VStack {
            Map(position: $mapPosition, scope: mapScope) {
                if let coord = animatedUserCoordinate {
                    Annotation("me", coordinate: coord) {
                        MiataruMapMarker(color: .blue)
                    }
                }
                if let coord = animatedDeviceCoordinate {
                    Annotation(device.DeviceName, coordinate: coord) {
                        MiataruMapMarker(color: Color(device.DeviceColor ?? .red))
                    }
                }
                if let polyline = route?.polyline {
                    MapPolyline(polyline)
                        .stroke(.blue, lineWidth: 4)
                }
            }
            .ignoresSafeArea()
            .onMapCameraChange { context in
                currentRegion = context.region
                if context.reason == .userInteraction {
                    userHasInteractedWithMap = true
                }
            }
            .onAppear {
                updateCoordinates(recenter: true)
                calculateRoute()
            }
            .onReceive(locationManager.$currentLocation) { _ in
                updateCoordinates()
            }
            .onReceive(cache.$locations) { _ in
                updateCoordinates()
            }
            .overlay(alignment: .top) {
                if let travelTime {
                    Text(travelTime)
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }

            HStack {
                Button(action: {
                    updateCoordinates(recenter: true)
                    calculateRoute()
                }) {
                    Label("reload_route", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button(action: openInAppleMaps) {
                    Label("open_in_apple_maps", systemImage: "arrow.up.right.square")
                }
            }
            .padding()
        }
    }

    private func updateCoordinates(recenter: Bool = false) {
        if let loc = locationManager.currentLocation {
            let coord = loc.coordinate
            let changed = userCoordinate?.latitude != coord.latitude || userCoordinate?.longitude != coord.longitude
            userCoordinate = coord
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
           (!hasSetInitialRegion || recenter || !userHasInteractedWithMap) {
            let region = regionThatFits(user: user, dest: dest)
            withAnimation {
                mapPosition = .region(region)
            }
            hasSetInitialRegion = true
        }
    }

    private func regionThatFits(user: CLLocationCoordinate2D, dest: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let center = CLLocationCoordinate2D(latitude: (user.latitude + dest.latitude) / 2,
                                            longitude: (user.longitude + dest.longitude) / 2)
        let span = MKCoordinateSpan(latitudeDelta: abs(user.latitude - dest.latitude) * 2.5,
                                    longitudeDelta: abs(user.longitude - dest.longitude) * 2.5)
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
                }
            } catch {
                debugLog("Route calculation failed: \(error)")
            }
        }
    }

    private func openInAppleMaps() {
        guard let user = userCoordinate, let dest = deviceCoordinate else { return }
        let source = MKMapItem(placemark: MKPlacemark(coordinate: user))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
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
}

