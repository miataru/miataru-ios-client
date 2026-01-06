/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetMapSnapshotGenerator.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation
import MapKit
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Generates pre-rendered map images (with a device marker and location text)
/// and writes them into the shared App Group container for WidgetKit consumption.
enum WidgetMapSnapshotGenerator {
    static func generateSnapshot(for device: KnownDevice, location: CachedDeviceLocation, size: CGSize = CGSize(width: 400, height: 400)) {
        Task.detached(priority: .utility) {
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)

            // Render both light and dark variants so widgets can pick based on appearance.
            await renderSnapshot(for: device, location: location, coordinate: coordinate, size: size, style: .light)
            await renderSnapshot(for: device, location: location, coordinate: coordinate, size: size, style: .dark)
        }
    }

    @MainActor
    private static func renderSnapshot(for device: KnownDevice, location: CachedDeviceLocation, coordinate: CLLocationCoordinate2D, size: CGSize, style: UIUserInterfaceStyle) async {
        guard let url = SharedWidgetDataManager.mapSnapshotURL(for: device.DeviceID, style: style) else { return }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.region = region(for: coordinate, accuracy: location.accuracy)
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let markerImage = await markerImage(for: device)
            let image = render(snapshot: snapshot, coordinate: coordinate, device: device, location: location, size: size, markerImage: markerImage)
            if let data = image.pngData() {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            debugLog("Failed to generate widget map snapshot (\(style == .dark ? "dark" : "light")): \(error)")
        }
    }

    private static func region(for coordinate: CLLocationCoordinate2D, accuracy: Double?) -> MKCoordinateRegion {
        let baseMeters: CLLocationDistance = 4000
        let extra = max(accuracy ?? 0, 0)
        let radius = max(baseMeters, extra * 4)
        return MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )
    }

    private static func render(snapshot: MKMapSnapshotter.Snapshot, coordinate: CLLocationCoordinate2D, device: KnownDevice, location: CachedDeviceLocation, size: CGSize, markerImage: UIImage) -> UIImage {
        let point = snapshot.point(for: coordinate)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))

            // Draw marker
            let markerSize = markerImage.size
            let markerOrigin = CGPoint(
                x: point.x - markerSize.width / 2,
                y: point.y - markerSize.height
            )
            markerImage.draw(in: CGRect(origin: markerOrigin, size: markerSize))

            // Location text overlay (locality / country + last update)
            let overlayText = overlayString(for: location)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .shadow: textShadow()
            ]
            let textRect = CGRect(
                x: 8,
                y: size.height - 40,
                width: size.width - 16,
                height: 32
            )
            overlayText.draw(in: textRect, withAttributes: attrs)
        }
    }

    private static func overlayString(for location: CachedDeviceLocation) -> String {
        var components: [String] = []
        if let locality = location.locality { components.append(locality) }
        if let country = location.country { components.append(country) }
        let place = components.joined(separator: ", ")

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: location.timestamp, relativeTo: Date())

        if place.isEmpty {
            return NSLocalizedString("widget_overlay_last_seen", comment: "Fallback overlay text when no placemark is available").replacingOccurrences(of: "%@", with: relative)
        } else {
            return "\(place) • \(relative)"
        }
    }

    private static func textShadow() -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 2
        return shadow
    }

    private static func markerImage(for device: KnownDevice) async -> UIImage {
        await MainActor.run {
            let marker = MiataruMapMarker(
                color: Color(device.DeviceColor ?? UIColor.systemBlue),
                height: 44,
                cacheEnabled: false,
                renderPadding: 10
            )
            let renderer = ImageRenderer(content: marker)
            renderer.scale = UIScreen.main.scale
            renderer.isOpaque = false
            return renderer.uiImage ?? UIImage(systemName: "mappin.circle.fill") ?? UIImage()
        }
    }
}

