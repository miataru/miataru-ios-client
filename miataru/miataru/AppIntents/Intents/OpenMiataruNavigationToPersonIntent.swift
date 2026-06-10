/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * OpenMiataruNavigationToPersonIntent.swift
 * miataru
 *
 * Created by Codex on 10.06.26.
 */

import AppIntents
import Foundation

struct OpenMiataruNavigationToPersonIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_open_miataru_navigation_to_person_title",
        defaultValue: "Navigation in Miataru",
        comment: "Title for the App Intent that opens Miataru's in-app navigation to a tracked person"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_miataru_navigation_to_person_description",
            defaultValue: "Opens Miataru navigation to the last known location of a person.",
            comment: "Description for the App Intent that opens Miataru's in-app navigation to a tracked person"
        )
    )
    static var openAppWhenRun: Bool = true

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
        Summary("Open Miataru navigation to \(\.$person)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: person)
        await Self.openMiataruNavigation(for: location)
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_miataru_navigation_to_person_dialog_format", comment: "Dialog format when opening Miataru navigation to a tracked person. Argument: display name."),
            location.displayName
        )

        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText)))
    }

    static func miataruNavigationURL(for location: IntentPersonLocation) -> URL {
        DeviceLinkResolver.navigationURL(for: location.personID)
    }

    static func miataruNavigationDestination(for location: IntentPersonLocation) -> DeviceLinkDestination? {
        DeviceLinkResolver.destination(from: miataruNavigationURL(for: location))
    }

    @MainActor
    static func openMiataruNavigation(
        for location: IntentPersonLocation,
        coordinator: AppNavigationCoordinator? = nil
    ) {
        guard let destination = miataruNavigationDestination(for: location) else { return }
        (coordinator ?? .shared).openDeviceLink(destination)
    }
}
