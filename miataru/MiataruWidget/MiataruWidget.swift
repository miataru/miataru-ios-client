import WidgetKit
import SwiftUI
import CoreLocation
import AppIntents

struct DeviceWidgetEntry: TimelineEntry {
    let date: Date
    let device: KnownDevice
    let distance: Measurement<UnitLength>?
}

struct DeviceTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = DeviceWidgetEntry
    typealias Intent = DeviceSelectionIntent

    func placeholder(in context: Context) -> DeviceWidgetEntry {
        DeviceWidgetEntry(
            date: Date(),
            device: KnownDevice(name: "Example", deviceID: "sample", color: .systemBlue),
            distance: nil
        )
    }

    func snapshot(for configuration: DeviceSelectionIntent, in context: Context) async -> DeviceWidgetEntry {
        await timelineEntry(for: configuration)
    }

    func timeline(for configuration: DeviceSelectionIntent, in context: Context) async -> Timeline<DeviceWidgetEntry> {
        let entry = await timelineEntry(for: configuration)
        let nextRefresh = Date().addingTimeInterval(60 * 15)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func timelineEntry(for configuration: DeviceSelectionIntent) async -> DeviceWidgetEntry {
        let deviceID = configuration.device?.id ?? KnownDeviceStore.shared.devices.first?.DeviceID
        let store = KnownDeviceStore.shared
        guard let deviceID = deviceID, let device = store.devices.first(where: { $0.DeviceID == deviceID }) else {
            return placeholder(in: .init())
        }
        let cache = DeviceLocationCacheStore.shared
        let location = cache.getLocation(for: device.DeviceID)
        var distance: Measurement<UnitLength>? = nil
        if let location = location, let current = LocationManager.shared.currentLocation {
            let deviceLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            let meters = current.distance(from: deviceLocation)
            distance = Measurement(value: meters, unit: UnitLength.meters)
        }
        return DeviceWidgetEntry(date: Date(), device: device, distance: distance)
    }
}

struct DeviceWidgetView: View {
    var entry: DeviceTimelineProvider.Entry
    var body: some View {
        let tintColor = entry.device.DeviceColor.map { Color($0) } ?? Color.accentColor
        VStack(alignment: .leading) {
            Text(entry.device.DeviceName)
                .font(.headline)
            if let distance = entry.distance {
                Text(String(format: "%.1f km", distance.converted(to: .kilometers).value))
                    .font(.caption)
            } else {
                Text("No distance")
                    .font(.caption)
            }
        }
        .padding()
        .foregroundStyle(tintColor)
        .tint(tintColor)
    }
}

struct MiataruWidget: Widget {
    let kind: String = "MiataruWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: DeviceSelectionIntent.self, provider: DeviceTimelineProvider()) { entry in
            DeviceWidgetView(entry: entry)
        }
        .configurationDisplayName("Device Tracker")
        .description("Shows the distance to a device.")
    }
}

#Preview(as: .systemSmall) {
    MiataruWidget()
} timeline: {
    DeviceWidgetEntry(
        date: .now,
        device: KnownDevice(name: "Preview", deviceID: "preview", color: .systemBlue),
        distance: Measurement(value: 0, unit: .meters)
    )
}
