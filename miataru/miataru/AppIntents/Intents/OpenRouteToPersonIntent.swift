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
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_open_route_to_device_title",
        defaultValue: "Route in Apple Maps",
        comment: "Title for the App Intent that opens an Apple Maps route to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_route_to_device_description",
            defaultValue: "Opens Apple Maps with directions to the last known location of a device.",
            comment: "Description for the App Intent that opens an Apple Maps route to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource(
            "intent_open_route_to_device_parameter_device",
            defaultValue: "Device",
            comment: "Parameter title for selecting a tracked device for route opening"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open Apple Maps route to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: device)
        let url = Self.appleMapsURL(for: location)
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_route_to_device_dialog_format", comment: "Dialog format when opening a route to a tracked device. Argument: display name."),
            location.displayName
        )

        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
        )
    }

    static func appleMapsURL(for location: IntentDeviceLocation) -> URL {
        var components = URLComponents(string: "http://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(location.latitude),\(location.longitude)")
        ]
        return components.url!
    }
}
