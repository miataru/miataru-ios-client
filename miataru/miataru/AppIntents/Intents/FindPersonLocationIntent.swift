/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * FindPersonLocationIntent.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents
import Foundation

struct FindPersonLocationIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_find_person_title",
        defaultValue: "Find Person",
        comment: "Title for the App Intent that finds a tracked person's latest location"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_find_person_description",
            defaultValue: "Shows the last known location of a person.",
            comment: "Description for the App Intent that finds a tracked person's latest location"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource(
            "intent_find_person_parameter_person",
            defaultValue: "Person",
            comment: "Parameter title for selecting a tracked person"
        ),
        optionsProvider: TrackedPersonOptionsProvider()
    )
    var person: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show location of \(\.$person)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: person)
        let place = location.placeDescription ?? NSLocalizedString("intent_location_fallback_place", comment: "Fallback place description for the last known location")
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_find_person_dialog_format", comment: "Dialog format for a tracked person's latest location. Arguments: display name, age text, place description."),
            location.displayName,
            location.ageText,
            place
        )

        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText)))
    }
}
