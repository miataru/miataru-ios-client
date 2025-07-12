import SwiftUI
import UIKit
import MapKit

struct iPhone_LegacyMapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let device: KnownDevice
    let deviceLocation: CLLocationCoordinate2D?
    let deviceAccuracy: Double?
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
        if let coordinate = deviceLocation {
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            annotation.title = device.DeviceName
            uiView.addAnnotation(annotation)
            // Genauigkeitskreis
            uiView.removeOverlays(uiView.overlays)
            if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracy, accuracy > 0 {
                let circle = MKCircle(center: coordinate, radius: accuracy)
                uiView.addOverlay(circle)
            }
        } else {
            uiView.removeOverlays(uiView.overlays)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: iPhone_LegacyMapViewRepresentable
        init(_ parent: iPhone_LegacyMapViewRepresentable) {
            self.parent = parent
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let color = device.DeviceColor ?? UIColor.blue
                renderer.fillColor = color.withAlphaComponent(0.2)
                renderer.strokeColor = color.withAlphaComponent(0.4)
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
