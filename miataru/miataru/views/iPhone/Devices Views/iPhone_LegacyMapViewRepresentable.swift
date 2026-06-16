/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * iPhone_LegacyMapViewRepresentable.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 20.06.25.
 */

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
        context.coordinator.parent = self
        uiView.setRegion(region, animated: true)
        uiView.mapType = mapTypeFromSettings(mapType)
        context.coordinator.updateDeviceAnnotation(on: uiView, coordinate: deviceLocation, title: device.DeviceName)
        uiView.removeOverlays(uiView.overlays)
        if let coordinate = deviceLocation {
            // Genauigkeitskreis
            if settings.indicateAccuracyOnMap, let accuracy = deviceAccuracy, accuracy > 0 {
                let circle = MKCircle(center: coordinate, radius: accuracy)
                uiView.addOverlay(circle)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: iPhone_LegacyMapViewRepresentable
        private var deviceAnnotation: MKPointAnnotation?

        init(_ parent: iPhone_LegacyMapViewRepresentable) {
            self.parent = parent
        }

        func updateDeviceAnnotation(on mapView: MKMapView, coordinate: CLLocationCoordinate2D?, title: String) {
            guard let coordinate = coordinate else {
                if let deviceAnnotation {
                    mapView.removeAnnotation(deviceAnnotation)
                    self.deviceAnnotation = nil
                }
                return
            }

            if let deviceAnnotation {
                deviceAnnotation.title = title
                UIView.animate(withDuration: 0.25) {
                    deviceAnnotation.coordinate = coordinate
                }
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = coordinate
                annotation.title = title
                deviceAnnotation = annotation
                mapView.addAnnotation(annotation)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                let color = parent.device.DeviceColor ?? UIColor.blue
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
