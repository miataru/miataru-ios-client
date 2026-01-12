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
        title: LocalizedStringResource("widget_intent_device_title", defaultValue: "Device", comment: "Parameter title for selecting a device")
    )
    var device: DeviceEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$device)")
    }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceEntity: AppEntity {
    static var typeDisplayName: LocalizedStringResource = LocalizedStringResource("widget_intent_device_title", defaultValue: "Device", comment: "Device entity")
    static var defaultQuery = DeviceQuery()
    static var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource("widget_intent_device_title", defaultValue: "Device", comment: "Device entity"))
    }
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("widget_intent_device_title", defaultValue: "Device", comment: "Device entity"))
    }

    var id: String
    var displayName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
struct DeviceQuery: EntityQuery {
    func entities(for identifiers: [DeviceEntity.ID]) async throws -> [DeviceEntity] {
        guard let payload = SharedWidgetDataManager.read() else { return [] }
        let normalized = identifiers.map { $0.lowercased() }
        return payload.devices
            .filter { normalized.contains($0.id.lowercased()) }
            .map { DeviceEntity(id: $0.id, displayName: $0.name) }
    }

    func suggestedEntities() async throws -> [DeviceEntity] {
        guard let payload = SharedWidgetDataManager.read() else { return [] }
        return payload.devices.map { DeviceEntity(id: $0.id, displayName: $0.name) }
    }

    func entities(matching query: String) async throws -> [DeviceEntity] {
        guard let payload = SharedWidgetDataManager.read() else { return [] }
        let filtered = payload.devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.map { DeviceEntity(id: $0.id, displayName: $0.name) }
    }
}
