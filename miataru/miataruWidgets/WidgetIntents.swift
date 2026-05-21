/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetIntents.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import AppIntents

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("widget_intent_title", defaultValue: "Select device", comment: "Title for widget device selection intent")
    static var description = IntentDescription(LocalizedStringResource("widget_intent_description", defaultValue: "Choose which device the widget should display.", comment: "Description for widget device selection intent"))
    static var isDiscoverable: Bool = false

    @Parameter(
        title: LocalizedStringResource("widget_intent_device_title", defaultValue: "Device", comment: "Parameter title for selecting a device"),
        optionsProvider: DeviceOptionsProvider()
    )
    var device: String?

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$device
        }
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceOptionsProvider: DynamicOptionsProvider {
    typealias Result = IntentItemCollection<String>
    typealias DefaultValue = String

    func results() async throws -> IntentItemCollection<String> {
        let items = Self.selectionData().map { selection in
            IntentItem(
                selection.id,
                title: LocalizedStringResource(stringLiteral: selection.name)
            )
        }
        guard !items.isEmpty else { return .empty }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    func defaultResult() async -> String? {
        Self.selectionData().first?.id
    }

    private static func selectionData() -> [WidgetDeviceSelectionData] {
        var selectionData: [WidgetDeviceSelectionData] = []

        if let payload = SharedWidgetDataManager.read() {
            if let deviceSelections = payload.deviceSelections, !deviceSelections.isEmpty {
                selectionData.append(contentsOf: deviceSelections)
            } else {
                selectionData.append(contentsOf: payload.devices.map {
                    WidgetDeviceSelectionData(id: $0.id, name: $0.name, color: $0.color)
                })
            }
        }

        if let config = SharedWidgetConfigManager.read() {
            for id in config.deviceIDs {
                selectionData.append(WidgetDeviceSelectionData(id: id, name: id, color: nil))
            }
        }

        var seenIDs = Set<String>()
        var orderedSelections: [WidgetDeviceSelectionData] = []
        for selection in selectionData {
            let normalizedID = normalizedDeviceID(selection.id)
            guard !normalizedID.isEmpty, seenIDs.insert(normalizedID).inserted else { continue }
            orderedSelections.append(selection)
        }
        return orderedSelections
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
