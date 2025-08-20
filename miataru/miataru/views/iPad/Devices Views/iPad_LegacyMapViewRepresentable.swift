/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPad_LegacyMapViewRepresentable.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

import SwiftUI
import UIKit
import MapKit

struct iPad_LegacyMapViewRepresentable: UIViewRepresentable {
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
        // iPad-specific: Force animations to be enabled
        mapView.setRegion(region, animated: true)
        mapView.mapType = mapTypeFromSettings(mapType)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // iPad-specific: Always use animations for better user experience
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
        var parent: iPad_LegacyMapViewRepresentable
        
        init(_ parent: iPad_LegacyMapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let deviceColor = parent.device.DeviceColor ?? UIColor.blue
                renderer.fillColor = deviceColor.withAlphaComponent(0.2)
                renderer.strokeColor = deviceColor
                renderer.lineWidth = 1
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            
            let identifier = "DeviceAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            // iPad-specific: Enhanced marker appearance
            let deviceColor = parent.device.DeviceColor ?? UIColor.blue
            annotationView?.image = createDeviceMarkerImage(color: deviceColor)
            annotationView?.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
            
            return annotationView
        }
        
        private func createDeviceMarkerImage(color: UIColor) -> UIImage? {
            let size = CGSize(width: 30, height: 30)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            defer { UIGraphicsEndImageContext() }
            
            // Draw a custom marker shape
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 15, y: 0))
            path.addLine(to: CGPoint(x: 25, y: 20))
            path.addLine(to: CGPoint(x: 15, y: 25))
            path.addLine(to: CGPoint(x: 5, y: 20))
            path.close()
            
            color.setFill()
            path.fill()
            
            // Add a border
            UIColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
            
            return UIGraphicsGetImageFromCurrentImageContext()
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
