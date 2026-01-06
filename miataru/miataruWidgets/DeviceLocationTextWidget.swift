/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLocationTextWidget.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import WidgetKit
import SwiftUI
import CoreLocation
import MapKit

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceLocationEntry: TimelineEntry {
    let date: Date
    let configuration: DeviceSelectionIntent
    let device: WidgetDeviceData?
    let ownDevice: WidgetDeviceData?
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceLocationTextProvider: AppIntentTimelineProvider {
    typealias Entry = DeviceLocationEntry
    typealias Intent = DeviceSelectionIntent

    func placeholder(in context: Context) -> DeviceLocationEntry {
        DeviceLocationEntry(date: Date(), configuration: DeviceSelectionIntent(), device: nil, ownDevice: nil)
    }

    func snapshot(for configuration: DeviceSelectionIntent, in context: Context) async -> DeviceLocationEntry {
        buildEntry(configuration: configuration)
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceLocationEntry> {
        let entry = buildEntry(configuration: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func buildEntry(configuration: DeviceSelectionIntent) -> DeviceLocationEntry {
        let payload = SharedWidgetDataManager.read()
        let targetID = configuration.device?.id ?? payload?.devices.first?.id
        let device = payload?.devices.first(where: { $0.id == targetID })
        return DeviceLocationEntry(
            date: Date(),
            configuration: configuration,
            device: device,
            ownDevice: payload?.ownDevice
        )
    }
}

struct DeviceLocationTextWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeviceLocationEntry

    var body: some View {
        Group {
            if let device = entry.device {
                content(for: device)
                    .widgetURL(URL(string: "miataru://\(device.id)"))
            } else {
                placeholder
            }
        }
    }

    private func content(for device: WidgetDeviceData) -> some View {
        let distanceText = formattedDistance(to: device, from: entry.ownDevice)
        let locality = formattedLocality(for: device)
        let lastUpdate = formattedRelativeTimestamp(for: device.timestamp)

        return VStack(alignment: .leading, spacing: 4) {
            Text(device.name)
                .font(.headline)
                .lineLimit(1)
            Text(locality)
                .font(.subheadline)
                .lineLimit(1)
            if family != .accessoryRectangular {
                Text(distanceText)
                    .font(.caption)
                    .lineLimit(1)
                Text(lastUpdate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(distanceText)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Device")
                .font(.headline)
            Text("Location loading…")
                .font(.subheadline)
            Text("—")
                .font(.caption)
        }
        .padding()
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

    private func formattedRelativeTimestamp(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let base = formatter.localizedString(for: date, relativeTo: Date())
        let label = NSLocalizedString("widget_last_update", comment: "Prefix for last update timestamp")
        return "\(label) \(base)"
    }

    private var distanceFormatter: MKDistanceFormatter {
        let formatter = MKDistanceFormatter()
        formatter.units = .default
        formatter.unitStyle = .abbreviated
        return formatter
    }
}

struct DeviceLocationTextWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DeviceLocationTextWidget", intent: DeviceSelectionIntent.self, provider: DeviceLocationTextProvider()) { entry in
            DeviceLocationTextWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_text_display_name", comment: "Display name for the text location widget"))
        .description(NSLocalizedString("widget_text_description", comment: "Description for the text location widget"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

