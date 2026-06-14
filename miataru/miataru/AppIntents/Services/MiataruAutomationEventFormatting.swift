/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAutomationEventFormatting.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import Foundation

enum MiataruAutomationEventFormatting {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func output(for record: MiataruAutomationEventRecord) -> MiataruAutomationEventOutput {
        MiataruAutomationEventOutput(
            kind: record.kind.rawValue,
            timestamp: record.timestamp,
            summary: summary(for: record),
            privacyLevel: record.privacyLevel.rawValue,
            deviceDisplayName: record.deviceDisplayName,
            placeName: record.placeName,
            payload: record.payload
        )
    }

    static func jsonString(for record: MiataruAutomationEventRecord) -> String {
        jsonString(for: output(for: record))
    }

    static func jsonString(for records: [MiataruAutomationEventRecord]) -> String {
        jsonString(for: records.map(output))
    }

    static func jsonString(for export: MiataruAutomationEventExport) -> String {
        jsonStringForEncodable(export)
    }

    static func noEventJSON() -> String {
        "null"
    }

    static func summary(for record: MiataruAutomationEventRecord) -> String {
        switch record.kind {
        case .navigationStarted:
            if let name = safeDisplayName(record.deviceDisplayName) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("automation_event_summary_navigation_started_format", tableName: "AutomationEvents", comment: "Summary for a Miataru navigation started event. Argument: device display name."),
                    name
                )
            }
            return NSLocalizedString("automation_event_summary_navigation_started", tableName: "AutomationEvents", comment: "Summary for a Miataru navigation started event without a device name")
        case .navigationEnded:
            if let name = safeDisplayName(record.deviceDisplayName) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("automation_event_summary_navigation_ended_format", tableName: "AutomationEvents", comment: "Summary for a Miataru navigation ended event. Argument: device display name."),
                    name
                )
            }
            return NSLocalizedString("automation_event_summary_navigation_ended", tableName: "AutomationEvents", comment: "Summary for a Miataru navigation ended event without a device name")
        case .frequentTrackingStarted:
            return NSLocalizedString("automation_event_summary_frequent_tracking_started", tableName: "AutomationEvents", comment: "Summary for frequent background tracking started")
        case .frequentTrackingStopped:
            return NSLocalizedString("automation_event_summary_frequent_tracking_stopped", tableName: "AutomationEvents", comment: "Summary for frequent background tracking stopped")
        case .frequentTrackingExpired:
            return NSLocalizedString("automation_event_summary_frequent_tracking_expired", tableName: "AutomationEvents", comment: "Summary for frequent background tracking expiration")
        case .trackingPaused:
            return NSLocalizedString("automation_event_summary_tracking_paused", tableName: "AutomationEvents", comment: "Summary for tracking paused")
        case .trackingResumed:
            return NSLocalizedString("automation_event_summary_tracking_resumed", tableName: "AutomationEvents", comment: "Summary for tracking resumed")
        case .deviceLocationUpdated:
            if let name = safeDisplayName(record.deviceDisplayName) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("automation_event_summary_device_location_updated_format", tableName: "AutomationEvents", comment: "Summary for a device location update event. Argument: device display name."),
                    name
                )
            }
            return NSLocalizedString("automation_event_summary_device_location_updated", tableName: "AutomationEvents", comment: "Summary for a device location update event without a device name")
        case .deviceEnteredPlace:
            if let placeName = safeDisplayName(record.placeName) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("automation_event_summary_device_entered_place_format", tableName: "AutomationEvents", comment: "Summary for a device entered place event. Argument: place name."),
                    placeName
                )
            }
            return NSLocalizedString("automation_event_summary_device_entered_place", tableName: "AutomationEvents", comment: "Summary for a device entered place event without place name")
        case .deviceLeftPlace:
            if let placeName = safeDisplayName(record.placeName) {
                return String.localizedStringWithFormat(
                    NSLocalizedString("automation_event_summary_device_left_place_format", tableName: "AutomationEvents", comment: "Summary for a device left place event. Argument: place name."),
                    placeName
                )
            }
            return NSLocalizedString("automation_event_summary_device_left_place", tableName: "AutomationEvents", comment: "Summary for a device left place event without place name")
        case .unknownVisitorDetected:
            return NSLocalizedString("automation_event_summary_unknown_visitor_detected", tableName: "AutomationEvents", comment: "Summary for an unknown visitor alert event")
        case .deviceKeyBlockedOperation:
            return NSLocalizedString("automation_event_summary_device_key_blocked_operation", tableName: "AutomationEvents", comment: "Summary for an operation blocked by DeviceKey authentication")
        case .lowBatteryDisabledFrequentTracking:
            return NSLocalizedString("automation_event_summary_low_battery_disabled_frequent_tracking", tableName: "AutomationEvents", comment: "Summary for low battery disabling frequent background tracking")
        }
    }

    static func kindDisplayName(_ kind: MiataruAutomationEventKind) -> String {
        switch kind {
        case .navigationStarted:
            return NSLocalizedString("automation_event_kind_navigation_started", tableName: "AutomationEvents", comment: "Display name for navigation started automation event")
        case .navigationEnded:
            return NSLocalizedString("automation_event_kind_navigation_ended", tableName: "AutomationEvents", comment: "Display name for navigation ended automation event")
        case .frequentTrackingStarted:
            return NSLocalizedString("automation_event_kind_frequent_tracking_started", tableName: "AutomationEvents", comment: "Display name for frequent tracking started automation event")
        case .frequentTrackingStopped:
            return NSLocalizedString("automation_event_kind_frequent_tracking_stopped", tableName: "AutomationEvents", comment: "Display name for frequent tracking stopped automation event")
        case .frequentTrackingExpired:
            return NSLocalizedString("automation_event_kind_frequent_tracking_expired", tableName: "AutomationEvents", comment: "Display name for frequent tracking expired automation event")
        case .trackingPaused:
            return NSLocalizedString("automation_event_kind_tracking_paused", tableName: "AutomationEvents", comment: "Display name for tracking paused automation event")
        case .trackingResumed:
            return NSLocalizedString("automation_event_kind_tracking_resumed", tableName: "AutomationEvents", comment: "Display name for tracking resumed automation event")
        case .deviceLocationUpdated:
            return NSLocalizedString("automation_event_kind_device_location_updated", tableName: "AutomationEvents", comment: "Display name for device location updated automation event")
        case .deviceEnteredPlace:
            return NSLocalizedString("automation_event_kind_device_entered_place", tableName: "AutomationEvents", comment: "Display name for device entered place automation event")
        case .deviceLeftPlace:
            return NSLocalizedString("automation_event_kind_device_left_place", tableName: "AutomationEvents", comment: "Display name for device left place automation event")
        case .unknownVisitorDetected:
            return NSLocalizedString("automation_event_kind_unknown_visitor_detected", tableName: "AutomationEvents", comment: "Display name for unknown visitor detected automation event")
        case .deviceKeyBlockedOperation:
            return NSLocalizedString("automation_event_kind_device_key_blocked_operation", tableName: "AutomationEvents", comment: "Display name for DeviceKey blocked operation automation event")
        case .lowBatteryDisabledFrequentTracking:
            return NSLocalizedString("automation_event_kind_low_battery_disabled_frequent_tracking", tableName: "AutomationEvents", comment: "Display name for low battery disabled frequent tracking automation event")
        }
    }

    static func privacyDisplayName(_ privacyLevel: MiataruAutomationEventPrivacyLevel) -> String {
        switch privacyLevel {
        case .publicSummary:
            return NSLocalizedString("automation_event_privacy_public_summary", tableName: "AutomationEvents", comment: "Display name for public-summary event privacy")
        case .privateLocation:
            return NSLocalizedString("automation_event_privacy_private_location", tableName: "AutomationEvents", comment: "Display name for private-location event privacy")
        case .securitySensitive:
            return NSLocalizedString("automation_event_privacy_security_sensitive", tableName: "AutomationEvents", comment: "Display name for security-sensitive event privacy")
        }
    }

    static func spokenDialog(for records: [MiataruAutomationEventRecord]) -> String {
        if records.isEmpty {
            return NSLocalizedString("intent_automation_events_dialog_none", tableName: "AppIntents", comment: "Dialog when no automation events are available")
        }
        if records.count == 1, let record = records.first {
            return summary(for: record)
        }
        let format = NSLocalizedString("intent_automation_events_dialog_count_format", tableName: "AppIntents", comment: "Dialog when multiple automation events are returned. Argument: event count.")
        return String.localizedStringWithFormat(format, records.count)
    }

    private static func jsonString<T: Encodable>(for value: T) -> String {
        jsonStringForEncodable(value)
    }

    private static func jsonStringForEncodable<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func safeDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
