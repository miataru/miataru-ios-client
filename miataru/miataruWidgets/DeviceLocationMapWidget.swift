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
import MiataruAPIClient

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
        await buildEntry(configuration: configuration)
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceMapEntry> {
        let entry = await buildEntry(configuration: configuration)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func buildEntry(configuration: DeviceSelectionIntent) async -> DeviceMapEntry {
        let (payload, device) = await WidgetTimelineDataLoader.loadEntryData(configuration: configuration)
        return DeviceMapEntry(date: Date(), configuration: configuration, device: device, ownDevice: payload.ownDevice)
    }
}

struct DeviceLocationMapWidgetEntryView: View {
    let entry: DeviceMapEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let device = entry.device {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        snapshotLayer(for: device)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                        if family != .accessoryRectangular {
                            topFadeOverlay
                            overlay(for: device, family: family)
                                .padding(.top, overlayTopPadding)
                                .frame(maxWidth: geo.size.width * overlayWidthFactor, alignment: .topLeading)
                                .padding(.horizontal, overlayHorizontalPadding)
                        }
                    }
                    .ignoresSafeArea() // fill widget content area
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

    private func snapshotLayer(for device: WidgetDeviceData) -> some View {
        let preferredURL: URL? = {
            switch colorScheme {
            case .dark:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .dark)
            default:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .light)
            }
        }()
        let fallbackURL = SharedWidgetDataManager.mapSnapshotURL(for: device.id)

        if let url = preferredURL ?? fallbackURL,
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            return AnyView(
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            )
        }

        // Visible fallback for missing snapshot, especially on small size
        return AnyView(
            ZStack {
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.2),
                        Color.gray.opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Image(systemName: "map")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray.opacity(0.6))
            }
        )
    }

    private var overlayTopPadding: CGFloat {
        switch family {
        case .systemMedium: return 4
        case .systemLarge: return 6
        default: return 4
        }
    }

    private var overlayHorizontalPadding: CGFloat {
        switch family {
        case .systemMedium: return 6
        case .systemLarge: return 8
        default: return 6
        }
    }

    private var overlayTopFadeHeight: CGFloat {
        switch family {
        case .systemMedium: return 50
        case .systemLarge: return 72
        default: return 60
        }
    }

    private var topFadeOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(colorScheme == .dark ? 0.45 : 0.25),
                Color.black.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: overlayTopFadeHeight)
        .edgesIgnoringSafeArea(.all)
        .allowsHitTesting(false)
    }

    private func overlay(for device: WidgetDeviceData, family: WidgetFamily) -> some View {
        let locality = formattedLocality(for: device)
        let distance = formattedDistance(to: device, from: entry.ownDevice)

        let (nameFont, detailFont, spacing, padding) = overlayMetrics(for: family)

        return VStack(alignment: .leading, spacing: spacing) {
            Text(device.name)
                .font(nameFont)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .shadow(radius: 2)
            Text(locality)
                .font(detailFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(distance)
                .font(detailFont)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(.primary)
        .padding(.vertical, padding)
        .padding(.horizontal, padding + 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(family == .systemMedium ? 0.7 : 0.4))
        )
    }

    private func overlayMetrics(for family: WidgetFamily) -> (Font, Font, CGFloat, CGFloat) {
        switch family {
        case .systemMedium:
            return (.subheadline.weight(.semibold), .caption2, 3, 7)
        case .systemLarge:
            return (.headline, .subheadline, 4, 12)
        default:
            return (.subheadline.weight(.semibold), .caption, 3, 8)
        }
    }

    private var overlayWidthFactor: CGFloat {
        switch family {
        case .systemMedium: return 0.9
        case .systemLarge: return 0.92
        default: return 0.9
        }
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
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

