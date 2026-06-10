/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * StartFrequentTrackingIntent.swift
 * miataru
 *
 * Created by Codex on 10.06.26.
 */

import AppIntents
import Foundation

struct StartFrequentTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource(
        "intent_start_frequent_tracking_title",
        defaultValue: "Start Frequent Tracking",
        comment: "Title for the App Intent that starts manual frequent background tracking"
    )
    static var description = IntentDescription(
        LocalizedStringResource(
            "intent_start_frequent_tracking_description",
            defaultValue: "Starts Miataru's more frequent background tracking using the current duration setting.",
            comment: "Description for the App Intent that starts manual frequent background tracking"
        )
    )
    static var openAppWhenRun: Bool = false

    static var parameterSummary: some ParameterSummary {
        Summary("Start frequent tracking")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await IntentFrequentTrackingService.shared.startFrequentTracking()
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: result.dialogText)))
    }
}
