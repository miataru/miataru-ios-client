/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * AutomationEventIntents.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import AppIntents
import Foundation

extension MiataruAutomationEventKind: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_automation_event_kind_type_name", defaultValue: "Automation Event Kind", table: "AppIntents",
            comment: "Display name for automation event kind App Intent enum"
        )
    )

    static var caseDisplayRepresentations: [MiataruAutomationEventKind: DisplayRepresentation] = [
        .navigationStarted: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_navigation_started", defaultValue: "Navigation Started", table: "AutomationEvents", comment: "Display name for navigation started automation event")),
        .navigationEnded: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_navigation_ended", defaultValue: "Navigation Ended", table: "AutomationEvents", comment: "Display name for navigation ended automation event")),
        .frequentTrackingStarted: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_frequent_tracking_started", defaultValue: "Frequent Tracking Started", table: "AutomationEvents", comment: "Display name for frequent tracking started automation event")),
        .frequentTrackingStopped: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_frequent_tracking_stopped", defaultValue: "Frequent Tracking Stopped", table: "AutomationEvents", comment: "Display name for frequent tracking stopped automation event")),
        .frequentTrackingExpired: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_frequent_tracking_expired", defaultValue: "Frequent Tracking Expired", table: "AutomationEvents", comment: "Display name for frequent tracking expired automation event")),
        .trackingPaused: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_tracking_paused", defaultValue: "Server Updates Paused", table: "AutomationEvents", comment: "Display name for server update pause automation event")),
        .trackingResumed: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_tracking_resumed", defaultValue: "Server Updates Resumed", table: "AutomationEvents", comment: "Display name for server update resumed automation event")),
        .deviceLocationUpdated: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_device_location_updated", defaultValue: "Device Location Updated", table: "AutomationEvents", comment: "Display name for device location updated automation event")),
        .deviceEnteredPlace: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_device_entered_place", defaultValue: "Device Entered Place", table: "AutomationEvents", comment: "Display name for device entered place automation event")),
        .deviceLeftPlace: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_device_left_place", defaultValue: "Device Left Place", table: "AutomationEvents", comment: "Display name for device left place automation event")),
        .unknownVisitorDetected: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_unknown_visitor_detected", defaultValue: "Unknown Visitor Detected", table: "AutomationEvents", comment: "Display name for unknown visitor detected automation event")),
        .knownDeviceRequestedLocalPosition: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_known_device_requested_position", defaultValue: "Known Device Requested Location", table: "AutomationEvents", comment: "Display name for known device requested local position automation event")),
        .deviceKeyBlockedOperation: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_device_key_blocked_operation", defaultValue: "DeviceKey Blocked Operation", table: "AutomationEvents", comment: "Display name for DeviceKey blocked operation automation event")),
        .lowBatteryDisabledFrequentTracking: DisplayRepresentation(title: LocalizedStringResource("automation_event_kind_low_battery_disabled_frequent_tracking", defaultValue: "Low Battery Disabled Frequent Tracking", table: "AutomationEvents", comment: "Display name for low battery disabled frequent tracking automation event"))
    ]
}

struct GetLatestMiataruEventIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_get_latest_miataru_event_title", defaultValue: "Get Latest Miataru Event", table: "AppIntents",
        comment: "Title for the App Intent that returns the latest Miataru automation event"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_get_latest_miataru_event_description", defaultValue: "Returns the latest Miataru automation event as structured JSON.", table: "AppIntents",
            comment: "Description for the App Intent that returns the latest Miataru automation event"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_automation_event_kind_parameter", defaultValue: "Kind", table: "AppIntents",
            comment: "Parameter title for filtering automation events by kind"
        )
    )
    var kind: MiataruAutomationEventKind?

    static var parameterSummary: some ParameterSummary {
        Summary("Get latest Miataru event")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let filter = Self.filter(kind: kind)
        guard let record = await MiataruAutomationEventStore.shared.latest(matching: filter) else {
            return .result(
                value: MiataruAutomationEventFormatting.noEventJSON(),
                dialog: IntentDialog(LocalizedStringResource(stringLiteral: MiataruAutomationEventFormatting.spokenDialog(for: [])))
            )
        }
        return .result(
            value: MiataruAutomationEventFormatting.jsonString(for: record),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: MiataruAutomationEventFormatting.spokenDialog(for: [record])))
        )
    }

    private static func filter(kind: MiataruAutomationEventKind?) -> MiataruAutomationEventFilter {
        guard let kind else { return .all }
        return MiataruAutomationEventFilter(kinds: [kind])
    }
}

struct ListRecentMiataruEventsIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_list_recent_miataru_events_title", defaultValue: "List Recent Miataru Events", table: "AppIntents",
        comment: "Title for the App Intent that returns recent Miataru automation events"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_list_recent_miataru_events_description", defaultValue: "Returns recent Miataru automation events as structured JSON.", table: "AppIntents",
            comment: "Description for the App Intent that returns recent Miataru automation events"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_automation_event_kind_parameter", defaultValue: "Kind", table: "AppIntents",
            comment: "Parameter title for filtering automation events by kind"
        )
    )
    var kind: MiataruAutomationEventKind?

    @Parameter(
        title: LocalizedStringResource("intent_list_recent_miataru_events_parameter_since", defaultValue: "Since", table: "AppIntents",
            comment: "Parameter title for filtering automation events by minimum timestamp"
        )
    )
    var since: Date?

    @Parameter(
        title: LocalizedStringResource("intent_list_recent_miataru_events_parameter_limit", defaultValue: "Limit", table: "AppIntents",
            comment: "Parameter title for limiting the number of returned automation events"
        )
    )
    var limit: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("List recent Miataru events")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let records = await MiataruAutomationEventStore.shared.recent(
            matching: Self.filter(kind: kind),
            since: since,
            limit: Self.boundedLimit(limit)
        )
        return .result(
            value: MiataruAutomationEventFormatting.jsonString(for: records),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: MiataruAutomationEventFormatting.spokenDialog(for: records)))
        )
    }

    private static func filter(kind: MiataruAutomationEventKind?) -> MiataruAutomationEventFilter {
        guard let kind else { return .all }
        return MiataruAutomationEventFilter(kinds: [kind])
    }

    static func boundedLimit(_ limit: Int?) -> Int {
        max(1, min(limit ?? 10, 50))
    }
}

struct ClearMiataruEventsIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_clear_miataru_events_title", defaultValue: "Clear Miataru Events", table: "AppIntents",
        comment: "Title for the App Intent that clears Miataru automation events"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_clear_miataru_events_description", defaultValue: "Clears Miataru automation events, optionally only events older than a date.", table: "AppIntents",
            comment: "Description for the App Intent that clears Miataru automation events"
        )
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: LocalizedStringResource("intent_clear_miataru_events_parameter_older_than", defaultValue: "Older Than", table: "AppIntents",
            comment: "Parameter title for clearing automation events older than a date"
        )
    )
    var olderThan: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Clear Miataru events")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let removedCount = await MiataruAutomationEventStore.shared.clear(olderThan: olderThan)
        let format = NSLocalizedString("intent_clear_miataru_events_dialog_count_format", tableName: "AppIntents", comment: "Dialog after clearing automation events. Argument: removed event count.")
        return .result(
            value: removedCount,
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: String.localizedStringWithFormat(format, removedCount)))
        )
    }
}

struct ExportAutomationEventIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("intent_export_automation_event_title", defaultValue: "Export Miataru Events", table: "AppIntents",
        comment: "Title for the App Intent that exports Miataru automation events"
    )
    static var description = IntentDescription(
        LocalizedStringResource("intent_export_automation_event_description", defaultValue: "Exports Miataru automation events as structured JSON.", table: "AppIntents",
            comment: "Description for the App Intent that exports Miataru automation events"
        )
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Export Miataru events")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let export = await MiataruAutomationEventStore.shared.makeExport()
        let format = NSLocalizedString("intent_export_automation_event_dialog_count_format", tableName: "AppIntents", comment: "Dialog after exporting automation events. Argument: exported event count.")
        return .result(
            value: MiataruAutomationEventFormatting.jsonString(for: export),
            dialog: IntentDialog(LocalizedStringResource(stringLiteral: String.localizedStringWithFormat(format, export.recordCount)))
        )
    }
}
