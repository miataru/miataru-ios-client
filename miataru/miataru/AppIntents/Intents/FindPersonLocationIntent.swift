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
        "intent_find_device_title",
        defaultValue: "Find Device",
        comment: "Title for the App Intent that finds a tracked device's latest location"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_find_device_description",
            defaultValue: "Shows the last known location of a device.",
            comment: "Description for the App Intent that finds a tracked device's latest location"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource(
            "intent_find_device_parameter_device",
            defaultValue: "Device",
            comment: "Parameter title for selecting a tracked device"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show location of \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: device)
        let place = location.placeDescription ?? NSLocalizedString("intent_location_fallback_place", comment: "Fallback place description for the last known location")
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_find_device_dialog_format", comment: "Dialog format for a tracked device's latest location. Arguments: display name, age text, place description."),
            location.displayName,
            location.ageText,
            place
        )

        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText)))
    }
}
