/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * PlaceIntents.swift
 * miataru
 *
 * Created by Codex on 14.06.26.
 */

import AppIntents
import Foundation

struct SaveCurrentPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_save_current_place_title", defaultValue: "Save Current Place", table: "AppIntents",
        comment: "Title for the App Intent that saves the user's current location as a place"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_save_current_place_description", defaultValue: "Saves your current location as a named Miataru place.", table: "AppIntents",
            comment: "Description for the App Intent that saves the user's current location as a place"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_save_current_place_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting the tracked device that owns a saved place"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    @Parameter(
        title: LocalizedStringResource("intent_save_current_place_parameter_name", defaultValue: "Name", table: "AppIntents",
            comment: "Parameter title for the saved place name"
        )
    )
    var name: String

    @Parameter(
        title: LocalizedStringResource("intent_save_current_place_parameter_radius", defaultValue: "Radius in Meters", table: "AppIntents",
            comment: "Parameter title for the saved place radius in meters"
        )
    )
    var radiusMeters: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$name) as a Miataru place for \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let place = try await IntentLocationService.shared.saveCurrentPlace(
            deviceID: device,
            name: name,
            radiusMeters: radiusMeters
        )
        return .result(
            value: MiataruPlaceIntentFormatting.jsonString(for: place),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: place)))
        )
    }

    static func dialogText(for place: MiataruPlaceEntity) -> String {
        let format = NSLocalizedString("intent_save_current_place_dialog_format", tableName: "AppIntents", comment: "Dialog after saving a place. Arguments: place name, localized radius."
        )
        return String.localizedStringWithFormat(
            format,
            place.name,
            IntentStatusFormatting.localizedDistance(place.radiusMeters)
        )
    }
}

struct ListPlacesIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_list_places_title", defaultValue: "List Places", table: "AppIntents",
        comment: "Title for the App Intent that lists saved places"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_list_places_description", defaultValue: "Returns saved Miataru places without exposing their raw coordinates.", table: "AppIntents",
            comment: "Description for the App Intent that lists saved places"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_list_places_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting the tracked device whose places should be listed"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("List saved Miataru places for \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let places = try await IntentLocationService.shared.knownPlaces(forDeviceID: device)
        return .result(
            value: MiataruPlaceIntentFormatting.jsonString(for: places),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: places)))
        )
    }

    static func dialogText(for places: [MiataruPlaceEntity]) -> String {
        guard !places.isEmpty else {
            return NSLocalizedString("intent_list_places_dialog_empty", tableName: "AppIntents", comment: "Dialog when there are no saved places")
        }

        let format = NSLocalizedString("intent_list_places_dialog_count_format", tableName: "AppIntents", comment: "Dialog when listing saved places. Arguments: place count, localized list of place names."
        )
        let names = ListFormatter.localizedString(byJoining: places.map(\.name))
        return String.localizedStringWithFormat(format, places.count, names)
    }
}

struct IsDeviceNearPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_is_device_near_place_title", defaultValue: "Check Device Near Place", table: "AppIntents",
        comment: "Title for the App Intent that checks whether a device is near a saved place"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_is_device_near_place_description", defaultValue: "Checks whether a visible tracked device is inside a saved place radius.", table: "AppIntents",
            comment: "Description for the App Intent that checks whether a device is near a saved place"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_is_device_near_place_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for a place proximity check"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    @Parameter(
        title: LocalizedStringResource("intent_is_device_near_place_parameter_place", defaultValue: "Place", table: "AppIntents",
            comment: "Parameter title for selecting a saved place for a proximity check"
        )
    )
    var place: MiataruPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check whether \(\.$device) is near \(\.$place)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let status = try await IntentLocationService.shared.isDeviceNearPlace(
            deviceID: device,
            placeID: place.id
        )
        return .result(
            value: status.isNear,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: status)))
        )
    }

    static func dialogText(for status: IntentPlaceProximityStatus) -> String {
        let format: String
        if status.isNear {
            format = NSLocalizedString("intent_is_device_near_place_dialog_near_format", tableName: "AppIntents", comment: "Dialog when a device is near a saved place. Arguments: device display name, place name, distance, radius."
            )
        } else {
            format = NSLocalizedString("intent_is_device_near_place_dialog_not_near_format", tableName: "AppIntents", comment: "Dialog when a device is not near a saved place. Arguments: device display name, place name, distance, radius."
            )
        }
        return String.localizedStringWithFormat(
            format,
            IntentStatusFormatting.spokenDisplayName(displayName: status.displayName, deviceID: status.deviceID),
            status.placeName,
            IntentStatusFormatting.localizedDistance(status.distanceMeters),
            IntentStatusFormatting.localizedDistance(status.radiusMeters)
        )
    }
}

struct FindDevicesNearPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_find_devices_near_place_title", defaultValue: "Find Devices Near Place", table: "AppIntents",
        comment: "Title for the App Intent that finds devices near a saved place"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_find_devices_near_place_description", defaultValue: "Finds visible tracked devices inside a saved place radius.", table: "AppIntents",
            comment: "Description for the App Intent that finds devices near a saved place"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_find_devices_near_place_parameter_place", defaultValue: "Place", table: "AppIntents",
            comment: "Parameter title for selecting a saved place for finding nearby devices"
        )
    )
    var place: MiataruPlaceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Find devices near \(\.$place)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let statuses = try await IntentLocationService.shared.devicesNearPlace(placeID: place.id)
        return .result(
            value: MiataruPlaceIntentFormatting.jsonString(for: statuses),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: statuses, placeName: place.name)))
        )
    }

    static func dialogText(for statuses: [IntentPlaceProximityStatus], placeName: String) -> String {
        guard !statuses.isEmpty else {
            let format = NSLocalizedString("intent_find_devices_near_place_dialog_none_format", tableName: "AppIntents", comment: "Dialog when no devices are near a saved place. Argument: place name."
            )
            return String.localizedStringWithFormat(format, placeName)
        }

        let format = NSLocalizedString("intent_find_devices_near_place_dialog_found_format", tableName: "AppIntents", comment: "Dialog when devices are near a saved place. Arguments: localized device name list, place name."
        )
        let deviceNames = statuses.map {
            IntentStatusFormatting.spokenDisplayName(displayName: $0.displayName, deviceID: $0.deviceID)
        }
        return String.localizedStringWithFormat(
            format,
            ListFormatter.localizedString(byJoining: deviceNames),
            placeName
        )
    }
}

enum MiataruPlaceIntentFormatting {
    static func jsonString(for place: MiataruPlaceEntity) -> String {
        jsonString(for: PlaceOutput(from: place))
    }

    static func jsonString(for places: [MiataruPlaceEntity]) -> String {
        jsonString(for: places.map(PlaceOutput.init(from:)))
    }

    static func jsonString(for statuses: [IntentPlaceProximityStatus]) -> String {
        jsonString(for: statuses.map(DeviceProximityOutput.init(from:)))
    }

    private static func jsonString<T: Encodable>(for value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }

    private struct PlaceOutput: Encodable {
        let id: String
        let name: String
        let radiusMeters: Double

        init(from place: MiataruPlaceEntity) {
            id = place.id.uuidString
            name = place.name
            radiusMeters = place.radiusMeters
        }
    }

    private struct DeviceProximityOutput: Encodable {
        let displayName: String
        let distanceMeters: Double
        let horizontalAccuracy: Double?
        let isNear: Bool
        let placeName: String
        let radiusMeters: Double

        init(from status: IntentPlaceProximityStatus) {
            displayName = IntentStatusFormatting.spokenDisplayName(displayName: status.displayName, deviceID: status.deviceID)
            distanceMeters = status.distanceMeters
            horizontalAccuracy = status.horizontalAccuracy
            isNear = status.isNear
            placeName = status.placeName
            radiusMeters = status.radiusMeters
        }
    }
}
