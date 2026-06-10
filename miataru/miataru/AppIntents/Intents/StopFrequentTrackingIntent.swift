/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * StopFrequentTrackingIntent.swift
 * miataru
 *
 * Created by Codex on 10.06.26.
 */

import AppIntents
import Foundation

struct StopFrequentTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_stop_frequent_tracking_title",
        defaultValue: "Stop Frequent Tracking",
        comment: "Title for the App Intent that stops manual frequent background tracking"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_stop_frequent_tracking_description",
            defaultValue: "Stops Miataru's more frequent background tracking and keeps standard tracking unchanged.",
            comment: "Description for the App Intent that stops manual frequent background tracking"
        )
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Stop frequent tracking")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = await IntentFrequentTrackingService.shared.stopFrequentTracking()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: result.dialogText)))
    }
}
