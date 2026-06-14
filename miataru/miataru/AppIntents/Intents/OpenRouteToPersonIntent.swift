/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * OpenRouteToPersonIntent.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents
import Foundation

struct OpenRouteToPersonIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_open_route_to_device_title", defaultValue: "Route in Maps", table: "AppIntents",
        comment: "Title for the App Intent that opens a Maps route to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_open_route_to_device_description", defaultValue: "Opens Maps with directions to the last known location of a device.", table: "AppIntents",
            comment: "Description for the App Intent that opens a Maps route to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_open_route_to_device_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for route opening"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    @Parameter(
        title: LocalizedStringResource("intent_navigation_parameter_direction", defaultValue: "Direction", table: "AppIntents",
            comment: "Parameter title for choosing route direction"
        )
    )
    var direction: IntentNavigationDirection?

    @Parameter(
        title: LocalizedStringResource("intent_navigation_parameter_transport_mode", defaultValue: "Transport Mode", table: "AppIntents",
            comment: "Parameter title for choosing route transport mode"
        )
    )
    var transportMode: IntentTransportMode?

    static var parameterSummary: some ParameterSummary {
        Summary("Open Maps route to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: device)
        let url = Self.appleMapsURL(
            for: location,
            direction: direction ?? .userToDevice,
            transportMode: transportMode
        )
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_route_to_device_dialog_format", tableName: "AppIntents", comment: "Dialog format when opening a route to a tracked device. Argument: display name."),
            location.displayName
        )

        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
        )
    }

    static func appleMapsURL(
        for location: IntentDeviceLocation,
        direction: IntentNavigationDirection = .userToDevice,
        transportMode: IntentTransportMode? = nil
    ) -> URL {
        var components = URLComponents(string: "http://maps.apple.com/")!
        let coordinateValue = "\(location.latitude),\(location.longitude)"
        var queryItems: [URLQueryItem]
        switch direction {
        case .userToDevice:
            queryItems = [
                URLQueryItem(name: "daddr", value: coordinateValue)
            ]
        case .deviceToUser:
            queryItems = [
                URLQueryItem(name: "saddr", value: coordinateValue),
                URLQueryItem(name: "daddr", value: "Current Location")
            ]
        }
        if let transportMode {
            queryItems.append(URLQueryItem(name: "dirflg", value: transportMode.appleMapsDirectionsFlag))
        }
        components.queryItems = queryItems
        return components.url!
    }
}
