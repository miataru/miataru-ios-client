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
import Foundation
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
        // Default refresh cadence. The system may still throttle this.
        var next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)

        // If the map snapshot file is missing or older than the data we’re displaying,
        // ask WidgetKit to give us another chance soon. This helps the widget recover
        // from slow snapshot rendering without "freezing" for long periods.
        if let device = entry.device, needsSnapshotRefresh(for: device) {
            next = Calendar.current.date(byAdding: .minute, value: 2, to: Date()) ?? Date().addingTimeInterval(120)
        }

        return Timeline(entries: [entry], policy: .after(next))
    }

    private func buildEntry(configuration: DeviceSelectionIntent) async -> DeviceMapEntry {
        let (payload, device) = await WidgetTimelineDataLoader.loadEntryData(configuration: configuration, generateMapSnapshots: true)
        return DeviceMapEntry(date: Date(), configuration: configuration, device: device, ownDevice: payload.ownDevice)
    }

    private func needsSnapshotRefresh(for device: WidgetDeviceData) -> Bool {
        #if canImport(UIKit)
        let styles: [UIUserInterfaceStyle] = [.light, .dark]
        #else
        let styles: [Any] = []
        #endif

        // Defensive: don't treat far-future timestamps as "always stale"
        // (clock skew can otherwise cause endless snapshot regeneration attempts).
        let referenceTimestamp = min(device.timestamp, Date())

        #if canImport(UIKit)
        for style in styles {
            guard let url = SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: style) else { return true }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return true
            }
            if modDate < referenceTimestamp {
                return true
            }
        }
        #endif

        // If we can't evaluate snapshots (non-UIKit platforms), don't force refresh.
        return false
    }
}

struct DeviceLocationMapWidgetEntryView: View {
    let entry: DeviceMapEntry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ZStack {
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
        .containerBackground(for: .widget) {
            ContainerRelativeShape()
                .fill(Color(.systemBackground))
        }
    }

    private func snapshotLayer(for device: WidgetDeviceData) -> some View {
        let referenceTimestamp = min(device.timestamp, Date())

        let preferredURL: URL? = {
            switch colorScheme {
            case .dark:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .dark)
            default:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .light)
            }
        }()

        let fallbackURL: URL? = {
            switch colorScheme {
            case .dark:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .light)
            default:
                return SharedWidgetDataManager.mapSnapshotURL(for: device.id, style: .dark)
            }
        }()

        func isFreshEnough(_ url: URL) -> Bool {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date else {
                return false
            }
            return modDate >= referenceTimestamp
        }

        // Never show a stale snapshot for a newer text payload. If the file is stale/missing,
        // show the placeholder until the new snapshot render finishes and WidgetCenter reloads.
        //
        // Prefer showing the current appearance style, but if only the *other* style is
        // available and still fresh for this payload, show it instead of a placeholder.
        // This avoids “stuck placeholder” scenarios when WidgetKit budget delays the
        // secondary snapshot generation, especially with multiple widgets on screen.
        let candidateURL: URL? = {
            if let preferredURL, isFreshEnough(preferredURL) { return preferredURL }
            if let fallbackURL, isFreshEnough(fallbackURL) { return fallbackURL }
            return nil
        }()

        if let url = candidateURL,
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
        let lastUpdate = formattedUpdateTimestamp(for: device.timestamp)

        let primaryComponents = [device.name, locality, distance].filter { !$0.isEmpty }
        let primaryLine = primaryComponents.joined(separator: " • ")
        let (primaryFont, secondaryFont, spacing, padding) = overlayMetrics(for: family)

        return VStack(alignment: .leading, spacing: spacing) {
            Text(primaryLine)
                .font(primaryFont)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(radius: 2)
            Text(lastUpdate)
                .font(secondaryFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
            return (.subheadline.weight(.semibold), .caption2, 2, 7)
        case .systemLarge:
            return (.headline, .subheadline, 3, 12)
        default:
            return (.subheadline.weight(.semibold), .caption, 2, 8)
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
