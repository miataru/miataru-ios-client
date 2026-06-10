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
                "Open an Apple Maps route in \(.applicationName)",
                "Route in Apple Maps with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_open_route_to_person_shortcut_title",
                defaultValue: "Route in Apple Maps",
                comment: "Short title for the Apple Maps route App Shortcut"
            ),
            systemImageName: "point.topleft.down.curvedto.point.bottomright.up"
        )

        AppShortcut(
            intent: OpenMiataruNavigationToPersonIntent(),
            phrases: [
                "Start Miataru navigation in \(.applicationName)",
                "Navigate in Miataru with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource(
                "intent_open_miataru_navigation_to_person_shortcut_title",
                defaultValue: "Navigation in Miataru",
                comment: "Short title for the Miataru in-app navigation App Shortcut"
            ),
            systemImageName: "location.north.line"
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
