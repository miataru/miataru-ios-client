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
    static var title: LocalizedStringResource = LocalizedStringResource("intent_open_miataru_navigation_to_device_title", defaultValue: "Navigation in Miataru", table: "AppIntents",
        comment: "Title for the App Intent that opens Miataru's in-app navigation to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_open_miataru_navigation_to_device_description", defaultValue: "Opens Miataru navigation to the last known location of a device.", table: "AppIntents",
            comment: "Description for the App Intent that opens Miataru's in-app navigation to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = true

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
        title: LocalizedStringResource("intent_open_miataru_navigation_to_device_parameter_presentation", defaultValue: "Presentation", table: "AppIntents",
            comment: "Parameter title for choosing Miataru navigation presentation"
        )
    )
    var presentation: IntentNavigationPresentation?

    @Parameter(
        title: LocalizedStringResource("intent_navigation_parameter_transport_mode", defaultValue: "Transport Mode", table: "AppIntents",
            comment: "Parameter title for choosing route transport mode"
        )
    )
    var transportMode: IntentTransportMode?

    static var parameterSummary: some ParameterSummary {
        Summary("Open Miataru navigation to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let location = try await IntentLocationService.shared.latestLocation(for: device)
        await Self.openMiataruNavigation(
            for: location,
            direction: direction ?? .userToDevice,
            presentation: presentation ?? .focused,
            transportMode: transportMode
        )
        let dialogText = String.localizedStringWithFormat(
            NSLocalizedString("intent_open_miataru_navigation_to_device_dialog_format", tableName: "AppIntents", comment: "Dialog format when opening Miataru navigation to a tracked device. Argument: display name."),
            location.displayName
        )

        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText)))
    }

    static func miataruNavigationURL(
        for location: IntentDeviceLocation,
        direction: IntentNavigationDirection = .userToDevice,
        presentation: IntentNavigationPresentation = .focused,
        transportMode: IntentTransportMode? = nil
    ) -> URL {
        DeviceLinkResolver.navigationURL(
            for: location.deviceID,
            options: DeviceNavigationLaunchOptions(
                direction: direction.launchDirection,
                presentation: presentation.launchPresentation,
                transportMode: transportMode
            )
        )
    }

    static func miataruNavigationDestination(
        for location: IntentDeviceLocation,
        direction: IntentNavigationDirection = .userToDevice,
        presentation: IntentNavigationPresentation = .focused,
        transportMode: IntentTransportMode? = nil
    ) -> DeviceLinkDestination? {
        DeviceLinkResolver.destination(
            from: miataruNavigationURL(
                for: location,
                direction: direction,
                presentation: presentation,
                transportMode: transportMode
            )
        )
    }

    @MainActor
    static func openMiataruNavigation(
        for location: IntentDeviceLocation,
        direction: IntentNavigationDirection = .userToDevice,
        presentation: IntentNavigationPresentation = .focused,
        transportMode: IntentTransportMode? = nil,
        coordinator: AppNavigationCoordinator? = nil
    ) {
        guard let destination = miataruNavigationDestination(
            for: location,
            direction: direction,
            presentation: presentation,
            transportMode: transportMode
        ) else { return }
        (coordinator ?? .shared).openDeviceLink(destination)
    }
}
