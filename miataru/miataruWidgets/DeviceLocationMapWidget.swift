/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLocationMapWidget.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import WidgetKit
import SwiftUI
import CoreLocation
import MapKit
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceMapEntry: TimelineEntry {
    let date: Date
    let configuration: DeviceSelectionIntent
    let device: WidgetDeviceData?
    let ownDevice: WidgetDeviceData?
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceLocationMapProvider: AppIntentTimelineProvider {
    typealias Entry = DeviceMapEntry
    typealias Intent = DeviceSelectionIntent

    func placeholder(in context: Context) -> DeviceMapEntry {
        DeviceMapEntry(date: Date(), configuration: DeviceSelectionIntent(), device: nil, ownDevice: nil)
    }

    func snapshot(for configuration: DeviceSelectionIntent, in context: Context) async -> DeviceMapEntry {
        buildEntry(configuration: configuration)
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceMapEntry> {
        let entry = buildEntry(configuration: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func buildEntry(configuration: DeviceSelectionIntent) -> DeviceMapEntry {
        let payload = SharedWidgetDataManager.read()
        let targetID = configuration.device?.id ?? payload?.devices.first?.id
        let device = payload?.devices.first(where: { $0.id == targetID })
        return DeviceMapEntry(date: Date(), configuration: configuration, device: device, ownDevice: payload?.ownDevice)
    }
}

struct DeviceLocationMapWidgetEntryView: View {
    let entry: DeviceMapEntry

    var body: some View {
        Group {
            if let device = entry.device {
                ZStack(alignment: .bottomLeading) {
                    snapshotImage(for: device)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                    overlay(for: device)
                }
                .widgetURL(URL(string: "miataru://\(device.id)"))
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        Text(NSLocalizedString("widget_no_device_selected", comment: "Shown when no device is available for the widget"))
                            .font(.caption)
                            .padding(8),
                        alignment: .bottomLeading
                    )
            }
        }
    }

    private func snapshotImage(for device: WidgetDeviceData) -> Image {
        guard let url = SharedWidgetDataManager.mapSnapshotURL(for: device.id),
              let data = try? Data(contentsOf: url),
              let uiImage = UIImage(data: data) else {
            return Image(systemName: "map")
        }
        return Image(uiImage: uiImage)
    }

    private func overlay(for device: WidgetDeviceData) -> some View {
        let locality = formattedLocality(for: device)
        let distance = formattedDistance(to: device, from: entry.ownDevice)

        return VStack(alignment: .leading, spacing: 4) {
            Text(device.name)
                .font(.headline)
                .lineLimit(1)
                .shadow(radius: 2)
            Text(locality)
                .font(.subheadline)
                .lineLimit(1)
            Text(distance)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(10)
        .background(.ultraThinMaterial.opacity(0.4))
        .cornerRadius(10)
        .padding(8)
    }

    private func formattedLocality(for device: WidgetDeviceData) -> String {
        let locality = device.locality ?? ""
        let country = device.country ?? ""
        let combined = [locality, country].filter { !$0.isEmpty }.joined(separator: ", ")
        if combined.isEmpty {
            return NSLocalizedString("widget_location_unknown", comment: "Shown when no placemark is available for the widget")
        }
        return combined
    }

    private func formattedDistance(to device: WidgetDeviceData, from ownDevice: WidgetDeviceData?) -> String {
        guard let own = ownDevice else {
            return NSLocalizedString("widget_distance_unknown", comment: "Shown when distance cannot be calculated")
        }
        let deviceLocation = CLLocation(latitude: device.latitude, longitude: device.longitude)
        let ownLocation = CLLocation(latitude: own.latitude, longitude: own.longitude)
        let meters = deviceLocation.distance(from: ownLocation)
        return distanceFormatter.string(fromDistance: meters)
    }

    private var distanceFormatter: MKDistanceFormatter {
        let formatter = MKDistanceFormatter()
        formatter.units = .default
        formatter.unitStyle = .abbreviated
        return formatter
    }
}

struct DeviceLocationMapWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DeviceLocationMapWidget", intent: DeviceSelectionIntent.self, provider: DeviceLocationMapProvider()) { entry in
            DeviceLocationMapWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_map_display_name", comment: "Display name for the map widget"))
        .description(NSLocalizedString("widget_map_description", comment: "Description for the map widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

