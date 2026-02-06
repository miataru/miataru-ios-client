//
//  ContentView.swift
//  AnimatedMapPolyline
//
//  Created by Daniel Kirstenpfad on 06.02.26.
//

import SwiftUI
import MapKit
import Combine
import CoreLocation
import AnimatedPolylineKit

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    
    var body: some View {
        ZStack {
            MapView(
                region: $viewModel.region,
                markers: viewModel.markers,
                animatedOverlay: viewModel.animatedOverlay
            )
            .ignoresSafeArea(.all)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        viewModel.generateRandomRoute()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(radius: 5)
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            viewModel.generateRandomRoute()
        }
    }
}

struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let markers: [MapMarker]
    let animatedOverlay: AnimatedPolylineOverlay?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        context.coordinator.markers = markers
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)
        context.coordinator.markers = markers

        // Update annotations
        mapView.removeAnnotations(mapView.annotations)
        for marker in markers {
            let annotation = MKPointAnnotation()
            annotation.coordinate = marker.coordinate
            mapView.addAnnotation(annotation)
        }

        // Update overlays: use animated polyline overlay when provided
        mapView.removeOverlays(mapView.overlays)
        if let overlay = animatedOverlay {
            mapView.addOverlay(overlay)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var markers: [MapMarker] = []
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pointAnnotation = annotation as? MKPointAnnotation else {
                return nil
            }
            
            // Find the corresponding marker to get its color
            if let marker = markers.first(where: { 
                abs($0.coordinate.latitude - pointAnnotation.coordinate.latitude) < 0.0001 &&
                abs($0.coordinate.longitude - pointAnnotation.coordinate.longitude) < 0.0001
            }) {
                let identifier = "Marker"
                var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                
                if annotationView == nil {
                    annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    annotationView?.annotation = annotation
                }
                
                if let markerView = annotationView as? MKMarkerAnnotationView {
                    markerView.markerTintColor = UIColor(marker.color)
                }
                
                return annotationView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let animatedOverlay = overlay as? AnimatedPolylineOverlay {
                return AnimatedPolylineRenderer(overlay: animatedOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

class MapViewModel: ObservableObject {
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @Published var markers: [MapMarker] = []
    @Published var routePolyline: MKPolyline?
    @Published var animatedOverlay: AnimatedPolylineOverlay?

    private var animationDriver: AnimatedPolylineAnimationDriver?
    private var progressCancellable: AnyCancellable?
    // All colors, gradients, speed, and animation settings are defined by the app.
    private let animationConfiguration = AnimatedPolylineConfiguration(
        underlyingColor: .blue,
        patchLength: 0.1,
        patchWhiteBandFraction: 0.55,
        patchHighlightBlend: 0.7,
        direction: .startToEnd,
        duration: 2.5,
        startEasing: .easeIn,
        endEasing: .easeOut,
        lineWidth: 10.0,
        lineCap: .round,
        lineJoin: .round
    )
    
    // Sample locations to choose from
    private let sampleLocations: [(name: String, coordinate: CLLocationCoordinate2D)] = [
        ("San Francisco", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        ("New York", CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)),
        ("Los Angeles", CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)),
        ("Chicago", CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)),
        ("Miami", CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)),
        ("Seattle", CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)),
        ("Boston", CLLocationCoordinate2D(latitude: 42.3601, longitude: -71.0589)),
        ("Austin", CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431)),
        ("Denver", CLLocationCoordinate2D(latitude: 39.7392, longitude: -104.9903)),
        ("Portland", CLLocationCoordinate2D(latitude: 45.5152, longitude: -122.6784))
    ]
    
    func generateRandomRoute() {
        guard sampleLocations.count >= 2 else { return }
        
        // Randomly select a starting location
        let startIndex = Int.random(in: 0..<sampleLocations.count)
        let startLocation = sampleLocations[startIndex]
        let startCLLocation = CLLocation(
            latitude: startLocation.coordinate.latitude,
            longitude: startLocation.coordinate.longitude
        )
        
        // Find locations within 50km of the starting location
        let maxDistance: CLLocationDistance = 50000 // 50km in meters
        let nearbyLocations = sampleLocations.enumerated().compactMap { index, location -> (Int, (name: String, coordinate: CLLocationCoordinate2D))? in
            guard index != startIndex else { return nil }
            let locationCLLocation = CLLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            let distance = startCLLocation.distance(from: locationCLLocation)
            if distance <= maxDistance {
                return (index, location)
            }
            return nil
        }
        
        // Select end location from nearby locations, or generate a random point within 50km
        let endLocation: (name: String, coordinate: CLLocationCoordinate2D)
        if let randomNearby = nearbyLocations.randomElement() {
            endLocation = randomNearby.1
        } else {
            // If no predefined locations within 50km, generate a random point within 50km
            let randomDistance = Double.random(in: 1000...50000) // Between 1km and 50km
            let randomBearing = Double.random(in: 0...(2 * .pi)) // Random direction
            
            let endCoordinate = calculateDestination(
                from: startLocation.coordinate,
                distance: randomDistance,
                bearing: randomBearing
            )
            endLocation = ("Random Point", endCoordinate)
        }
        
        // Create markers
        markers = [
            MapMarker(coordinate: startLocation.coordinate, color: .green),
            MapMarker(coordinate: endLocation.coordinate, color: .red)
        ]
        
        // Clear previous animated overlay and stop animation before calculating new route
        animationDriver?.stop()
        progressCancellable = nil
        animatedOverlay = nil
        routePolyline = nil

        // Calculate route
        calculateRoute(from: startLocation.coordinate, to: endLocation.coordinate)

        // Update region to show both markers (route callback will reframe to fit actual route when it arrives)
        let minLat = min(startLocation.coordinate.latitude, endLocation.coordinate.latitude)
        let maxLat = max(startLocation.coordinate.latitude, endLocation.coordinate.latitude)
        let minLon = min(startLocation.coordinate.longitude, endLocation.coordinate.longitude)
        let maxLon = max(startLocation.coordinate.longitude, endLocation.coordinate.longitude)
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = max(maxLat - minLat, 0.1) * 1.5
        let lonDelta = max(maxLon - minLon, 0.1) * 1.5
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
    
    private func calculateDestination(from start: CLLocationCoordinate2D, distance: CLLocationDistance, bearing: Double) -> CLLocationCoordinate2D {
        let earthRadius: Double = 6371000 // Earth radius in meters
        let lat1 = start.latitude * .pi / 180.0
        let lon1 = start.longitude * .pi / 180.0
        
        let angularDistance = distance / earthRadius
        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(
            latitude: lat2 * 180.0 / .pi,
            longitude: lon2 * 180.0 / .pi
        )
    }
    
    private func calculateRoute(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) {
        let request = MKDirections.Request()
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        request.source = MKMapItem(location: startLocation, address: nil)
        request.destination = MKMapItem(location: endLocation, address: nil)
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Route calculation error: \(error.localizedDescription)")
                return
            }
            
            guard let route = response?.routes.first, route.polyline.pointCount >= 2 else {
                print("No route found")
                return
            }

            let polyline = route.polyline
            DispatchQueue.main.async {
                self.routePolyline = polyline
                self.setupAnimatedOverlay(polyline: polyline)
                // Reframe region to fit the actual route (handles detours and ensures full route is visible)
                let rect = polyline.boundingMapRect
                let padding = 1.2
                let padded = MKMapRect(
                    x: rect.origin.x - rect.size.width * (padding - 1) / 2,
                    y: rect.origin.y - rect.size.height * (padding - 1) / 2,
                    width: rect.size.width * padding,
                    height: rect.size.height * padding
                )
                let topLeft = MKMapPoint(x: padded.minX, y: padded.minY).coordinate
                let bottomRight = MKMapPoint(x: padded.maxX, y: padded.maxY).coordinate
                let centerLat = (topLeft.latitude + bottomRight.latitude) / 2
                let centerLon = (topLeft.longitude + bottomRight.longitude) / 2
                let latDelta = abs(bottomRight.latitude - topLeft.latitude)
                let lonDelta = abs(bottomRight.longitude - topLeft.longitude)
                self.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: max(latDelta, 0.01), longitudeDelta: max(lonDelta, 0.01))
                )
            }
        }
    }

    private func setupAnimatedOverlay(polyline: MKPolyline) {
        let overlay = AnimatedPolylineOverlay(polyline: polyline, configuration: animationConfiguration)
        let driver = AnimatedPolylineAnimationDriver(configuration: animationConfiguration, loop: true)
        progressCancellable = driver.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak overlay] value in
                overlay?.progress = value
            }
        driver.start()
        animatedOverlay = overlay
        animationDriver = driver
    }
}

struct MapMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

#Preview {
    ContentView()
}
