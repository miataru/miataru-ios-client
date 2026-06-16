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
                "Find a device in \(.applicationName)",
                "Show a Miataru location in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_find_device_shortcut_title", defaultValue: "Find Device", table: "AppIntents",
                comment: "Short title for the find device App Shortcut"
            ),
            systemImageName: "location"
        )

        AppShortcut(
            intent: OpenRouteToPersonIntent(),
            phrases: [
                "Open a Maps route in \(.applicationName)",
                "Route in Maps with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_open_route_to_device_shortcut_title", defaultValue: "Route in Maps", table: "AppIntents",
                comment: "Short title for the Maps route App Shortcut"
            ),
            systemImageName: "point.topleft.down.curvedto.point.bottomright.up"
        )

        AppShortcut(
            intent: OpenMiataruNavigationToPersonIntent(),
            phrases: [
                "Start Miataru navigation in \(.applicationName)",
                "Navigate in Miataru with \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_open_miataru_navigation_to_device_shortcut_title", defaultValue: "Navigation in Miataru", table: "AppIntents",
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
            shortTitle: LocalizedStringResource("intent_start_frequent_tracking_shortcut_title", defaultValue: "Start Frequent", table: "AppIntents",
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
            shortTitle: LocalizedStringResource("intent_stop_frequent_tracking_shortcut_title", defaultValue: "Stop Frequent", table: "AppIntents",
                comment: "Short title for the stop frequent tracking App Shortcut"
            ),
            systemImageName: "location.slash"
        )

        AppShortcut(
            intent: GetTrackingStatusIntent(),
            phrases: [
                "Check tracking status in \(.applicationName)",
                "Is Miataru tracking active in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_get_tracking_status_shortcut_title", defaultValue: "Tracking Status", table: "AppIntents",
                comment: "Short title for the tracking status App Shortcut"
            ),
            systemImageName: "location.circle"
        )

        AppShortcut(
            intent: GetFrequentTrackingStatusIntent(),
            phrases: [
                "Check frequent tracking in \(.applicationName)",
                "How long is frequent tracking active in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_get_frequent_tracking_status_shortcut_title", defaultValue: "Frequent Status", table: "AppIntents",
                comment: "Short title for the frequent tracking status App Shortcut"
            ),
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: GetDeviceStatusIntent(),
            phrases: [
                "Check a device status in \(.applicationName)",
                "How old is a Miataru location in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_get_device_status_shortcut_title", defaultValue: "Device Status", table: "AppIntents",
                comment: "Short title for the device status App Shortcut"
            ),
            systemImageName: "clock"
        )

        AppShortcut(
            intent: GetDistanceToDeviceIntent(),
            phrases: [
                "Check distance to a device in \(.applicationName)",
                "How far away is a Miataru device in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_get_distance_to_device_shortcut_title", defaultValue: "Device Distance", table: "AppIntents",
                comment: "Short title for the distance to device App Shortcut"
            ),
            systemImageName: "ruler"
        )

        AppShortcut(
            intent: GetLatestLocationRequestIntent(),
            phrases: [
                "When did a device last request my location in \(.applicationName)",
                "Check a location request in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("intent_get_latest_location_request_shortcut_title", defaultValue: "Latest Request", table: "AppIntents",
                comment: "Short title for the latest known-device location request App Shortcut"
            ),
            systemImageName: "location.viewfinder"
        )
    }
}
