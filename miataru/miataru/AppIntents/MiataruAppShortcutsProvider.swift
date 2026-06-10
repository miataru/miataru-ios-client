/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAppShortcutsProvider.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents

struct MiataruAppShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindPersonLocationIntent(),
            phrases: [
                "Find a person in \(.applicationName)",
                "Show a Miataru location in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_find_person_shortcut_title",
                defaultValue: "Find Person",
                comment: "Short title for the find person App Shortcut"
            ),
            systemImageName: "location"
        )

        AppShortcut(
            intent: OpenRouteToPersonIntent(),
            phrases: [
                "Open a route in \(.applicationName)",
                "Navigate with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_open_route_to_person_shortcut_title",
                defaultValue: "Route to Person",
                comment: "Short title for the route to person App Shortcut"
            ),
            systemImageName: "point.topleft.down.curvedto.point.bottomright.up"
        )

        AppShortcut(
            intent: StartFrequentTrackingIntent(),
            phrases: [
                "Start frequent tracking in \(.applicationName)",
                "Enable frequent tracking in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_start_frequent_tracking_shortcut_title",
                defaultValue: "Start Frequent",
                comment: "Short title for the start frequent tracking App Shortcut"
            ),
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: StopFrequentTrackingIntent(),
            phrases: [
                "Stop frequent tracking in \(.applicationName)",
                "Disable frequent tracking in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_stop_frequent_tracking_shortcut_title",
                defaultValue: "Stop Frequent",
                comment: "Short title for the stop frequent tracking App Shortcut"
            ),
            systemImageName: "location.slash"
        )
    }
}
