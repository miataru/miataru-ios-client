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
import MiataruAPIClient

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
        await buildEntry(configuration: configuration)
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceLocationEntry> {
        let entry = await buildEntry(configuration: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func buildEntry(configuration: DeviceSelectionIntent) async -> DeviceLocationEntry {
        let (payload, device) = await WidgetTimelineDataLoader.loadEntryData(configuration: configuration)
        return DeviceLocationEntry(
            date: Date(),
            configuration: configuration,
            device: device,
            ownDevice: payload.ownDevice
        )
    }
}

struct DeviceLocationTextWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeviceLocationEntry

    var body: some View {
        ZStack {
            if let device = entry.device {
                content(for: device)
                    .widgetURL(URL(string: "miataru://\(device.id)"))
            } else {
                placeholder
            }
        }
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(Color(.systemBackground))
        }
    }

    private func content(for device: WidgetDeviceData) -> some View {
        let distanceText = formattedDistance(to: device, from: entry.ownDevice)
        let locality = formattedLocality(for: device)
        let lastUpdate = formattedUpdateTimestamp(for: device.timestamp)

        let (nameFont, detailFont, distanceFont, updateFont, spacing, padding) = metrics(for: family)

        return VStack(alignment: .leading, spacing: spacing) {
            Text(device.name)
                .font(nameFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(locality)
                .font(detailFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if family != .accessoryRectangular {
                Text(distanceText)
                    .font(distanceFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(lastUpdate)
                    .font(updateFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text(distanceText)
                    .font(distanceFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(padding)
    }

    private func metrics(for family: WidgetFamily) -> (Font, Font, Font, Font, CGFloat, EdgeInsets) {
        switch family {
        case .systemSmall:
            return (
                .footnote.weight(.semibold),
                .caption2,
                .caption2,
                .caption2,
                2,
                EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            )
        case .systemMedium:
            return (
                .title3.weight(.semibold),
                .callout,
                .callout,
                .caption,
                6,
                EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
            )
        default:
            return (
                .headline,
                .subheadline,
                .caption,
                .caption2,
                4,
                EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
            )
        }
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

    private func formattedUpdateTimestamp(for date: Date) -> String {
        let label = NSLocalizedString("widget_last_update", comment: "Prefix for last update timestamp")
        let now = Date()
        let stamp: String
        if Calendar.current.isDate(date, inSameDayAs: now) {
            stamp = date.formatted(date: .omitted, time: .shortened)
        } else {
            stamp = date.formatted(date: .abbreviated, time: .shortened)
        }
        return "\(label) \(stamp)"
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
