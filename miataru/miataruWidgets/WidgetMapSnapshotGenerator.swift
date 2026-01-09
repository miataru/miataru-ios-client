/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetMapSnapshotGenerator.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-08.
 */

import Foundation
import MapKit

#if canImport(UIKit)
import UIKit
#endif

/// Generates pre-rendered map images (with a simple device marker) and writes them into
/// the shared App Group container for WidgetKit consumption.
///
/// Why this exists in the widget extension:
/// The widget timeline can fetch fresh location data, but without regenerating the snapshot
/// image the map can remain stale while text updates (e.g. "updated … ago").
@available(iOS 17.0, *)
enum WidgetMapSnapshotGenerator {
    #if canImport(UIKit)
    static func ensureSnapshotsUpToDate(for device: WidgetDeviceData,
                                        size: CGSize = CGSize(width: 600, height: 600)) async {
        let ts = device.timestamp
        let coord = CLLocationCoordinate2D(latitude: device.latitude, longitude: device.longitude)

        // If either style is missing or older than the device timestamp, regenerate it.
        let needsLight = needsRegeneration(deviceID: device.id, style: .light, deviceTimestamp: ts)
        let needsDark = needsRegeneration(deviceID: device.id, style: .dark, deviceTimestamp: ts)
        guard needsLight || needsDark else { return }

        if needsLight {
            await renderSnapshot(for: device, coordinate: coord, size: size, style: .light)
        }
        if needsDark {
            await renderSnapshot(for: device, coordinate: coord, size: size, style: .dark)
        }
    }

    private static func needsRegeneration(deviceID: String, style: UIUserInterfaceStyle, deviceTimestamp: Date) -> Bool {
        guard let url = SharedWidgetDataManager.mapSnapshotURL(for: deviceID, style: style) else { return true }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return true
        }
        // Regenerate if the snapshot predates the data we’re about to show.
        // Clamp to "now" to avoid endless regeneration when server timestamps are in the future.
        let referenceTimestamp = min(deviceTimestamp, Date())
        return modDate < referenceTimestamp
    }

    @MainActor
    private static func renderSnapshot(for device: WidgetDeviceData,
                                       coordinate: CLLocationCoordinate2D,
                                       size: CGSize,
                                       style: UIUserInterfaceStyle) async {
        guard let url = SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: style) else { return }

        let options = MKMapSnapshotter.Options()
        options.size = size
        options.scale = UIScreen.main.scale
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.showsBuildings = false
        options.region = region(for: coordinate, accuracy: device.accuracy)
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let marker = markerImage(for: device, style: style)
            let image = render(snapshot: snapshot, coordinate: coordinate, size: size, markerImage: marker)
            if let data = image.pngData() {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            #if DEBUG
            print("[Widget] Failed to generate map snapshot (\(style == .dark ? "dark" : "light")) for \(device.id): \(error)")
            #endif
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

    private static func render(snapshot: MKMapSnapshotter.Snapshot,
                               coordinate: CLLocationCoordinate2D,
                               size: CGSize,
                               markerImage: UIImage) -> UIImage {
        let point = snapshot.point(for: coordinate)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))

            let markerSize = markerImage.size
            let markerOrigin = CGPoint(
                x: point.x - markerSize.width / 2,
                y: point.y - markerSize.height
            )
            markerImage.draw(in: CGRect(origin: markerOrigin, size: markerSize))
        }
    }

    private static func markerImage(for device: WidgetDeviceData, style: UIUserInterfaceStyle) -> UIImage {
        let color = uiColor(from: device.color) ?? UIColor.systemBlue
        let symbol = UIImage(systemName: "mappin.circle.fill") ?? UIImage()
        let tinted = symbol.withTintColor(color, renderingMode: .alwaysOriginal)

        let target = CGSize(width: 44, height: 44)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: target)
            tinted.draw(in: rect.insetBy(dx: 2, dy: 2))
        }
    }

    private static func uiColor(from color: WidgetColor?) -> UIColor? {
        guard let color else { return nil }
        return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
    #else
    static func ensureSnapshotsUpToDate(for device: WidgetDeviceData, size: CGSize = .zero) async { }
    #endif
}


