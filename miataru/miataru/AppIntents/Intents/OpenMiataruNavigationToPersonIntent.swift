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
        "intent_open_miataru_navigation_to_device_title",
        defaultValue: "Navigation in Miataru",
        comment: "Title for the App Intent that opens Miataru's in-app navigation to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_open_miataru_navigation_to_device_description",
            defaultValue: "Opens Miataru navigation to the last known location of a device.",
            comment: "Description for the App Intent that opens Miataru's in-app navigation to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = true

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
        Summary("Open Miataru navigation to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: device)
        await Self.openMiataruNavigation(for: location)
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_miataru_navigation_to_device_dialog_format", comment: "Dialog format when opening Miataru navigation to a tracked device. Argument: display name."),
            location.displayName
        )

        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText)))
    }

    static func miataruNavigationURL(for location: IntentDeviceLocation) -> URL {
        DeviceLinkResolver.navigationURL(for: location.deviceID)
    }

    static func miataruNavigationDestination(for location: IntentDeviceLocation) -> DeviceLinkDestination? {
        DeviceLinkResolver.destination(from: miataruNavigationURL(for: location))
    }

    @MainActor
    static func openMiataruNavigation(
        for location: IntentDeviceLocation,
        coordinator: AppNavigationCoordinator? = nil
    ) {
        guard let destination = miataruNavigationDestination(for: location) else { return }
        (coordinator ?? .shared).openDeviceLink(destination)
    }
}
