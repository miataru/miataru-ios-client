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
        "intent_open_route_to_person_title",
        defaultValue: "Open Route to Person",
        comment: "Title for the App Intent that opens a route to a tracked person"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_route_to_person_description",
            defaultValue: "Opens Apple Maps with directions to the last known location of a person.",
            comment: "Description for the App Intent that opens a route to a tracked person"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource(
            "intent_open_route_to_person_parameter_person",
            defaultValue: "Person",
            comment: "Parameter title for selecting a tracked person for route opening"
        ),
        optionsProvider: TrackedPersonOptionsProvider()
    )
    var person: String

    static var parameterSummary: some ParameterSummary {
        Summary("Open route to \(\.$person)")
    }

    func perform() async throws -> some IntentResult & OpensIntent & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: person)
        let url = Self.appleMapsURL(for: location)
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_route_to_person_dialog_format", comment: "Dialog format when opening a route to a tracked person. Argument: display name."),
            location.displayName
        )

        return .result(
            opensIntent: OpenURLIntent(url),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
        )
    }

    static func appleMapsURL(for location: IntentPersonLocation) -> URL {
        var components = URLComponents(string: "http://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(location.latitude),\(location.longitude)")
        ]
        return components.url!
    }
}
