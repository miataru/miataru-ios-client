/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * StatusIntents.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import AppIntents
import Foundation

struct GetTrackingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_tracking_status_title", defaultValue: "Get Tracking Status", table: "AppIntents",
        comment: "Title for the App Intent that reports Miataru tracking status"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_tracking_status_description", defaultValue: "Reports whether Miataru location tracking is active.", table: "AppIntents",
            comment: "Description for the App Intent that reports Miataru tracking status"
        )
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get Miataru tracking status")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let status = await IntentFrequentTrackingService.shared.trackingStatus()
        return .result(
            value: Self.isTrackingActive(status),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: status)))
        )
    }

    static func isTrackingActive(_ status: IntentTrackingStatus) -> Bool {
        status.effectiveMode != .stopped && status.effectiveMode != .blocked
    }

    static func dialogText(for status: IntentTrackingStatus) -> String {
        switch status.effectiveMode {
        case .stopped:
            return NSLocalizedString("intent_get_tracking_status_dialog_stopped", tableName: "AppIntents", comment: "Dialog when Miataru tracking is stopped"
            )
        case .blocked:
            if status.deviceKeyAuthBlocked {
                return NSLocalizedString("intent_get_tracking_status_dialog_device_key_blocked", tableName: "AppIntents", comment: "Dialog when Miataru tracking is blocked by DeviceKey authentication"
                )
            }
            return NSLocalizedString("intent_get_tracking_status_dialog_blocked", tableName: "AppIntents", comment: "Dialog when Miataru tracking is blocked"
            )
        default:
            let format = NSLocalizedString("intent_get_tracking_status_dialog_active_format", tableName: "AppIntents", comment: "Dialog when Miataru tracking is active. Argument: localized tracking mode."
            )
            return String.localizedStringWithFormat(format, IntentStatusFormatting.localizedTrackingMode(status.effectiveMode))
        }
    }
}

struct GetFrequentTrackingStatusIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_frequent_tracking_status_title", defaultValue: "Get Frequent Tracking Status", table: "AppIntents",
        comment: "Title for the App Intent that reports frequent tracking status"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_frequent_tracking_status_description", defaultValue: "Reports whether Miataru's more precise background tracking is active.", table: "AppIntents",
            comment: "Description for the App Intent that reports frequent tracking status"
        )
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Get frequent tracking status")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let status = await IntentFrequentTrackingService.shared.frequentTrackingStatus()
        return .result(
            value: status.active,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: status)))
        )
    }

    static func dialogText(for status: IntentFrequentTrackingStatus) -> String {
        if status.active {
            if status.manualEnabled {
                if let expiresAt = status.expiresAt {
                    let format = NSLocalizedString("intent_get_frequent_tracking_status_dialog_active_until_format", tableName: "AppIntents", comment: "Dialog for active frequent tracking with expiration. Arguments: expiration date, remaining duration."
                    )
                    return String.localizedStringWithFormat(
                        format,
                        IntentStatusFormatting.localizedDateTime(expiresAt),
                        IntentStatusFormatting.localizedDuration(status.remainingSeconds ?? 0)
                    )
                }
                return NSLocalizedString("intent_get_frequent_tracking_status_dialog_active_unlimited", tableName: "AppIntents", comment: "Dialog for active frequent tracking with unlimited duration"
                )
            }

            return NSLocalizedString("intent_get_frequent_tracking_status_dialog_smart_active", tableName: "AppIntents", comment: "Dialog for active smart frequent tracking"
            )
        }

        if let blockingReason = status.blockingReason {
            let format = NSLocalizedString("intent_get_frequent_tracking_status_dialog_blocked_format", tableName: "AppIntents", comment: "Dialog for inactive frequent tracking with a blocking reason. Argument: localized blocking reason."
            )
            return String.localizedStringWithFormat(format, IntentStatusFormatting.localizedBlockingReason(blockingReason))
        }

        return NSLocalizedString("intent_get_frequent_tracking_status_dialog_inactive", tableName: "AppIntents", comment: "Dialog for inactive frequent tracking"
        )
    }
}

struct GetDeviceStatusIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_device_status_title", defaultValue: "Get Device Status", table: "AppIntents",
        comment: "Title for the App Intent that reports a tracked device's status"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_device_status_description", defaultValue: "Reports the age and coarse place of a tracked device's latest location.", table: "AppIntents",
            comment: "Description for the App Intent that reports a tracked device's status"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_get_device_status_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for status"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get status for \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let status = try await IntentLocationService.shared.deviceStatus(for: device)
        let dialogText = Self.dialogText(for: status)
        return .result(
            value: dialogText,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
        )
    }

    static func dialogText(for status: IntentDeviceStatus) -> String {
        IntentStatusFormatting.deviceStatusDialogText(for: status, includeDistance: status.distanceMeters != nil)
    }
}

struct GetDistanceToDeviceIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_distance_to_device_title", defaultValue: "Get Distance to Device", table: "AppIntents",
        comment: "Title for the App Intent that reports distance to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_distance_to_device_description", defaultValue: "Reports the distance from your current location to a tracked device.", table: "AppIntents",
            comment: "Description for the App Intent that reports distance to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_get_distance_to_device_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for distance"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get distance to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let status = try await IntentLocationService.shared.distanceStatus(for: device)
        return .result(
            value: status.distanceMeters ?? 0,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: status)))
        )
    }

    static func dialogText(for status: IntentDeviceStatus) -> String {
        let format = NSLocalizedString("intent_get_distance_to_device_dialog_format", tableName: "AppIntents", comment: "Dialog for distance to a tracked device. Arguments: display name, distance, bearing."
        )
        return String.localizedStringWithFormat(
            format,
            IntentStatusFormatting.spokenDisplayName(displayName: status.displayName, deviceID: status.deviceID),
            IntentStatusFormatting.localizedDistance(status.distanceMeters ?? 0),
            IntentStatusFormatting.localizedBearing(status.bearingDegrees)
        )
    }
}

struct GetLatestLocationRequestIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_latest_location_request_title", defaultValue: "Get Latest Location Request", table: "AppIntents",
        comment: "Title for the App Intent that reports when a known device last requested the user's location"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_latest_location_request_description", defaultValue: "Reports when a known device last requested your location through Visitor History.", table: "AppIntents",
            comment: "Description for the App Intent that reports the latest known-device VisitorHistory access"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_get_latest_location_request_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for latest location request"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get latest location request from \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let selectedDevice = try await IntentLocationService.shared.device(for: device) else {
            throw IntentLocationError.deviceUnavailable
        }

        let displayName = IntentStatusFormatting.spokenDisplayName(
            displayName: selectedDevice.name,
            deviceID: selectedDevice.id
        )

        guard let access = await KnownVisitorAccessHistory.latestAccess(for: selectedDevice.id) else {
            let dialogText = String.localizedStringWithFormat(
                NSLocalizedString("intent_get_latest_location_request_dialog_none_format", tableName: "AppIntents", comment: "Dialog when a device has no recorded location request. Argument: device display name."),
                displayName
            )
            return .result(
                value: dialogText,
                dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
            )
        }

        let dialogText = Self.dialogText(for: access, displayName: displayName)
        return .result(
            value: dialogText,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialogText))
        )
    }

    static func dialogText(for access: KnownVisitorAccessHistoryEntry, displayName: String) -> String {
        let dateText = IntentStatusFormatting.localizedDateTime(access.timestamp)
        if let place = KnownVisitorAccessHistory.locationDescription(for: access) {
            return String.localizedStringWithFormat(
                NSLocalizedString("intent_get_latest_location_request_dialog_place_format", tableName: "AppIntents", comment: "Dialog when a device has a recorded location request with requester place. Arguments: device display name, date and time, place."),
                displayName,
                dateText,
                place
            )
        }

        return String.localizedStringWithFormat(
            NSLocalizedString("intent_get_latest_location_request_dialog_format", tableName: "AppIntents", comment: "Dialog when a device has a recorded location request. Arguments: device display name, date and time."),
            displayName,
            dateText
        )
    }
}

struct GetETAForDeviceIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_eta_for_device_title", defaultValue: "Get ETA to Device", table: "AppIntents",
        comment: "Title for the App Intent that reports ETA to a tracked device"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_eta_for_device_description", defaultValue: "Estimates travel time from your current location to a tracked device.", table: "AppIntents",
            comment: "Description for the App Intent that reports ETA to a tracked device"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_get_eta_for_device_parameter_device", defaultValue: "Device", table: "AppIntents",
            comment: "Parameter title for selecting a tracked device for ETA"
        ),
        optionsProvider: TrackedDeviceOptionsProvider()
    )
    var device: String

    static var parameterSummary: some ParameterSummary {
        Summary("Get ETA to \(\.$device)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let status = try await IntentLocationService.shared.etaStatus(for: device)
        return .result(
            value: status.expectedTravelTimeSeconds,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: Self.dialogText(for: status)))
        )
    }

    static func dialogText(for status: IntentETAStatus) -> String {
        let format = NSLocalizedString("intent_get_eta_for_device_dialog_format", tableName: "AppIntents", comment: "Dialog for ETA to a tracked device. Arguments: display name, distance, transport mode, duration."
        )
        return String.localizedStringWithFormat(
            format,
            IntentStatusFormatting.spokenDisplayName(displayName: status.deviceStatus.displayName, deviceID: status.deviceStatus.deviceID),
            IntentStatusFormatting.localizedDistance(status.distanceMeters),
            IntentStatusFormatting.localizedTransportMode(status.transportMode),
            IntentStatusFormatting.localizedDuration(status.expectedTravelTimeSeconds)
        )
    }
}

enum IntentStatusFormatting {
    static func deviceStatusDialogText(for status: IntentDeviceStatus, includeDistance: Bool) -> String {
        let place = status.coarsePlaceDescription ?? NSLocalizedString("intent_location_fallback_place", tableName: "AppIntents", comment: "Fallback place description for the last known location"
        )
        let baseFormat = NSLocalizedString("intent_get_device_status_dialog_format", tableName: "AppIntents", comment: "Dialog for tracked device status. Arguments: display name, age text, coarse place."
        )
        var parts = [
            String.localizedStringWithFormat(
                baseFormat,
                spokenDisplayName(displayName: status.displayName, deviceID: status.deviceID),
                status.ageText,
                place
            )
        ]

        if let horizontalAccuracy = status.horizontalAccuracy {
            let accuracyFormat = NSLocalizedString("intent_get_device_status_accuracy_format", tableName: "AppIntents", comment: "Dialog sentence for location accuracy. Argument: localized accuracy distance."
            )
            parts.append(String.localizedStringWithFormat(accuracyFormat, localizedDistance(horizontalAccuracy)))
        }

        if includeDistance, let distanceMeters = status.distanceMeters {
            let distanceFormat = NSLocalizedString("intent_get_device_status_distance_format", tableName: "AppIntents", comment: "Dialog sentence for optional device distance. Arguments: localized distance, localized bearing."
            )
            parts.append(String.localizedStringWithFormat(distanceFormat, localizedDistance(distanceMeters), localizedBearing(status.bearingDegrees)))
        }

        return parts.joined(separator: " ")
    }

    static func spokenDisplayName(displayName: String, deviceID: String) -> String {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = TrackedDeviceIntentMetadata.normalizedDeviceID(trimmedDisplayName)
        let normalizedDeviceID = TrackedDeviceIntentMetadata.normalizedDeviceID(deviceID)
        guard !trimmedDisplayName.isEmpty,
              normalizedDisplayName != normalizedDeviceID else {
            return NSLocalizedString("intent_selected_device_spoken_name", tableName: "AppIntents", comment: "Privacy-safe spoken fallback name for a selected tracked device"
            )
        }
        return trimmedDisplayName
    }

    static func localizedTrackingMode(_ mode: IntentTrackingMode) -> String {
        switch mode {
        case .stopped:
            return NSLocalizedString("intent_tracking_mode_stopped", tableName: "AppIntents", comment: "Localized tracking mode: stopped")
        case .foregroundHighAccuracy:
            return NSLocalizedString("intent_tracking_mode_foreground_high_accuracy", tableName: "AppIntents", comment: "Localized tracking mode: foreground high accuracy")
        case .backgroundSignificantChange:
            return NSLocalizedString("intent_tracking_mode_background_significant_change", tableName: "AppIntents", comment: "Localized tracking mode: background significant-change")
        case .smartWaiting:
            return NSLocalizedString("intent_tracking_mode_smart_waiting", tableName: "AppIntents", comment: "Localized tracking mode: smart waiting")
        case .smartFrequentActive:
            return NSLocalizedString("intent_tracking_mode_smart_frequent_active", tableName: "AppIntents", comment: "Localized tracking mode: smart frequent active")
        case .manualFrequentActive:
            return NSLocalizedString("intent_tracking_mode_manual_frequent_active", tableName: "AppIntents", comment: "Localized tracking mode: manual frequent active")
        case .blocked:
            return NSLocalizedString("intent_tracking_mode_blocked", tableName: "AppIntents", comment: "Localized tracking mode: blocked")
        }
    }

    static func localizedBlockingReason(_ reason: IntentFrequentTrackingBlockingReason) -> String {
        switch reason {
        case .trackingDisabled:
            return NSLocalizedString("intent_frequent_tracking_blocking_reason_tracking_disabled", tableName: "AppIntents", comment: "Frequent tracking blocking reason: tracking disabled")
        case .deviceKeyBlocked:
            return NSLocalizedString("intent_frequent_tracking_blocking_reason_device_key_blocked", tableName: "AppIntents", comment: "Frequent tracking blocking reason: DeviceKey blocked")
        case .alwaysAuthorizationRequired:
            return NSLocalizedString("intent_frequent_tracking_blocking_reason_always_authorization_required", tableName: "AppIntents", comment: "Frequent tracking blocking reason: Always location authorization required")
        case .lowBatteryDisabled:
            return NSLocalizedString("intent_frequent_tracking_blocking_reason_low_battery_disabled", tableName: "AppIntents", comment: "Frequent tracking blocking reason: low battery disabled frequent mode")
        }
    }

    static func localizedBearing(_ bearingDegrees: Double?) -> String {
        guard let bearingDegrees, bearingDegrees.isFinite else {
            return NSLocalizedString("intent_bearing_unknown", tableName: "AppIntents", comment: "Bearing text when direction is unknown")
        }

        let index = Int(((bearingDegrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        switch index {
        case 0:
            return NSLocalizedString("intent_bearing_north", tableName: "AppIntents", comment: "Localized cardinal bearing: north")
        case 1:
            return NSLocalizedString("intent_bearing_northeast", tableName: "AppIntents", comment: "Localized cardinal bearing: northeast")
        case 2:
            return NSLocalizedString("intent_bearing_east", tableName: "AppIntents", comment: "Localized cardinal bearing: east")
        case 3:
            return NSLocalizedString("intent_bearing_southeast", tableName: "AppIntents", comment: "Localized cardinal bearing: southeast")
        case 4:
            return NSLocalizedString("intent_bearing_south", tableName: "AppIntents", comment: "Localized cardinal bearing: south")
        case 5:
            return NSLocalizedString("intent_bearing_southwest", tableName: "AppIntents", comment: "Localized cardinal bearing: southwest")
        case 6:
            return NSLocalizedString("intent_bearing_west", tableName: "AppIntents", comment: "Localized cardinal bearing: west")
        default:
            return NSLocalizedString("intent_bearing_northwest", tableName: "AppIntents", comment: "Localized cardinal bearing: northwest")
        }
    }

    static func localizedTransportMode(_ mode: IntentTransportMode) -> String {
        switch mode {
        case .walking:
            return NSLocalizedString("intent_transport_mode_walking", tableName: "AppIntents", comment: "Localized transport mode: walking")
        case .automobile:
            return NSLocalizedString("intent_transport_mode_automobile", tableName: "AppIntents", comment: "Localized transport mode: automobile")
        case .transit:
            return NSLocalizedString("intent_transport_mode_transit", tableName: "AppIntents", comment: "Localized transport mode: transit")
        }
    }

    static func localizedDistance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.unitStyle = .medium
        formatter.numberFormatter.maximumFractionDigits = meters >= 1_000 ? 1 : 0
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
    }

    static func localizedDuration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else {
            return NSLocalizedString("intent_duration_less_than_minute", tableName: "AppIntents", comment: "Duration text for less than one minute")
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full
        return formatter.string(from: seconds) ?? NSLocalizedString("intent_duration_unknown", tableName: "AppIntents", comment: "Fallback duration text")
    }

    static func localizedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
