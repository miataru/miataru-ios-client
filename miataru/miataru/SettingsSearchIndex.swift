import Foundation

enum SettingsSearchPage: Equatable {
    case main
    case advanced
    case deviceKey
    case trackingPause
    case allowedDevices
    case trackingDetails
}

enum SettingsSearchRequirement: Equatable {
    case none
    case tracking
    case trackingEnabled
    case localHistory
    case smartFrequent
    case frequent
}

struct SettingsSearchEntry: Identifiable {
    let key: String
    let table: String
    let aliases: [String]
    let page: SettingsSearchPage
    let requirement: SettingsSearchRequirement
    let fallbackPage: SettingsSearchPage
    let fallbackAnchor: String

    var id: String { key }
    var title: String { String(localized: String.LocalizationValue(key), table: table) }
    var anchor: String { SettingsSearchIndex.anchor(key) }
    var fallback: String { fallbackAnchor }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = SettingsSearchIndex.normalize(query)
        guard !normalizedQuery.isEmpty else { return false }
        return ([title] + aliases).contains { SettingsSearchIndex.normalize($0).contains(normalizedQuery) }
    }
}

struct SettingsSearchTarget: Equatable {
    let page: SettingsSearchPage
    let anchor: String
    let isPrerequisite: Bool
}

enum SettingsSearchIndex {
    static func anchor(_ key: String) -> String { "settings.search.\(key)" }

    static func prerequisiteMessageKey(
        for entry: SettingsSearchEntry,
        trackingEnabled: Bool,
        trackingReady: Bool
    ) -> String {
        if !trackingEnabled && entry.requirement != .none {
            return "settings_search_requires_parent_setting"
        }
        if !trackingReady {
            return "settings_search_requires_tracking_permission"
        }
        return "settings_search_requires_parent_setting"
    }

    static func entries() -> [SettingsSearchEntry] {
        [
            main("location_track", "LocationTracking", ["tracking", "standort", "ortung"]),
            main("save_location_history_to_server", "LocationTracking", ["history", "verlauf", "speichern"], .tracking),
            main("unknown_visitor_alerts_toggle", "Devices", ["visitor", "besucher", "alert", "warnung"], .tracking),
            main("store_history_before_autoremove", "LocationTracking", ["retention", "aufbewahrung", "automatisch löschen"], .localHistory),
            button("manage_your_devicekey", "Devices", ["device key", "gerätekennung", "schlüssel", "qr key"], .deviceKey),
            button("tracking_pause_settings_title", "LocationTracking", ["pause tracking", "ortung pausieren", "updates pausieren"], .trackingPause, .trackingEnabled),
            main("allowed_device_list_section_title", "Devices", ["allowed devices", "erlaubte geräte", "access list", "zugriffsliste", "enable allowed device list", "geräteliste aktivieren", String(localized: "allowed_device_list_enable_button", table: "Devices")]),
            button("Location Tracking Details", "LocationTracking", ["tracking details", "ortungsdetails", "tracking status"], .trackingDetails),
            main("smart_frequent_background_location_updates_title", "LocationTracking", ["smart tracking", "intelligentes tracking", "background", "hintergrund"], .tracking),
            main("frequent_background_location_updates_title", "LocationTracking", ["frequent updates", "häufige updates", "manuell", "battery", "akku"], .smartFrequent),
            main("deactivate_device_lock", "Devices", ["autolock", "bildschirmsperre", "display sperre"]),
            main("prevent_screen_rotation", "LocationTracking", ["rotation", "ausrichtung", "drehen"]),
            main("map_type", "MapNavigationHistory", ["map", "karte", "satellite", "satellit"]),
            main("map_zoom_level", "MapNavigationHistory", ["zoom", "kartenmaßstab", "map range"]),
            main("transport_mode", "MapNavigationHistory", ["transport", "verkehrsmittel", "walking", "gehen", "car", "auto", "transit", "öpnv"]),
            main("server_url", "SettingsDiagnostics", ["server", "url", "endpoint"]),
            main("advanced_options", "SettingsDiagnostics", ["advanced", "erweitert", "tracking details", "tracking status"]),
            advanced("activity_type_tracking_accuracy_title", "LocationTracking", ["accuracy", "genauigkeit", "activity", "aktivität"], .tracking),
            advanced("location_sensitivity_title", "MapNavigationHistory", ["sensitivity", "empfindlichkeit", "gps interval"], .tracking),
            advanced("location_tracking_health_reminder_interval_title", "LocationTracking", ["reminder", "erinnerung", "health", "gesundheit"], .tracking),
            advanced("smart_frequent_background_speed_threshold_title", "LocationTracking", ["speed threshold", "geschwindigkeitsschwelle", "threshold", "schwelle"], .smartFrequent),
            advanced("smart_frequent_background_speed_detection_title", "LocationTracking", ["gps speed", "gps geschwindigkeit", "detection", "erkennung"], .smartFrequent),
            advanced("smart_frequent_background_inactivity_window_title", "LocationTracking", ["inactivity", "inaktivität", "pause"] , .smartFrequent),
            advanced("smart_frequent_background_exit_fence_radius_title", "LocationTracking", ["exit fence", "geofence", "radius"], .smartFrequent),
            advanced("smart_frequent_background_mode_change_notifications_title", "LocationTracking", ["mode notification", "modus benachrichtigung"], .smartFrequent),
            advanced("frequent_background_location_updates_duration_title", "LocationTracking", ["duration", "dauer", "zeitlimit"], .frequent),
            advanced("frequent_background_battery_auto_disable_level_title", "LocationTracking", ["battery level", "akkustand", "disable", "deaktivieren"], .tracking),
            advanced("background_location_distance_filter_title", "LocationTracking", ["distance filter", "entfernung", "meter filter"], .tracking),
            advanced("frequent_background_location_delivery_mode_title", "LocationTracking", ["delivery", "übertragung", "send interval", "intervall"], .tracking),
            advanced("frequent_background_visitor_check_interval_title", "LocationTracking", ["visitor check", "besucher prüfen"], .tracking),
            advanced("known_visitor_notification_cooldown_title", "LocationTracking", ["cooldown", "abklingzeit", "notification interval", "benachrichtigungsintervall"], .tracking),
            advanced("pulsating_map_markers", "LocationTracking", ["pulse", "pulsieren", "marker animation"]),
            advanced("indicate_location_accuracy", "LocationTracking", ["accuracy circle", "genauigkeitskreis"]),
            advanced("show_offscreen_arrows_for_other_devices", "MapNavigationHistory", ["offscreen", "außerhalb", "arrows", "pfeile"]),
            advanced("auto_refresh_device_list", "LocationTracking", ["refresh", "aktualisieren", "device list", "geräteliste"]),
            advanced("show_current_speed_on_map", "MapNavigationHistory", ["map speed", "kartengeschwindigkeit", "geschwindigkeit auf karte"]),
            advanced("location_update_outbox_retention_title", "LocationTracking", ["outbox retention", "warteschlange aufbewahrung"], .tracking),
            advanced("location_update_outbox_max_items_title", "LocationTracking", ["outbox size", "warteschlangengröße"], .tracking),
            advanced("map_update_interval", "MapNavigationHistory", ["map refresh", "kartenaktualisierung"]),
            advanced("outside_map_update_interval", "LocationTracking", ["background interval", "intervall außerhalb der karte"]),
            advanced("zoom_to_fit_for_groups", "LocationTracking", ["group zoom", "gruppen zoom"]),
            advanced("reverse_geocoding_threshold", "LocationTracking", ["reverse geocoding", "adresse", "geocoding"]),
            advanced("navigation_auto_route_update", "MapNavigationHistory", ["route refresh", "route aktualisieren"]),
            advanced("show_route_progress", "MapNavigationHistory", ["route progress", "routenfortschritt", "route completed", "erledigte route"]),
            advanced("navigation_hud_section", "MapNavigationHistory", ["hud", "head-up display", "speed", "geschwindigkeit", "live speed", "tempo", "mirror", "spiegel", "palette", "anweisung", "instruction"]),
            advanced("navigation_hud_palette", "MapNavigationHistory", ["hud color", "hud farbe", "palette", "red", "rot", "yellow", "gelb", "white", "weiß"]),
            advanced("navigation_hud_mirror", "MapNavigationHistory", ["mirror", "spiegel", "reflected", "gespiegelt"]),
        ]
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func target(
        for entry: SettingsSearchEntry,
        trackingReady: Bool,
        saveHistoryOnServer: Bool,
        smartFrequentEnabled: Bool,
        frequentEnabled: Bool,
        trackingEnabled: Bool = true
    ) -> SettingsSearchTarget {
        let available: Bool
        switch entry.requirement {
        case .none: available = true
        case .tracking: available = trackingReady
        case .trackingEnabled: available = trackingEnabled
        case .localHistory: available = trackingReady && !saveHistoryOnServer
        case .smartFrequent: available = trackingReady && smartFrequentEnabled
        case .frequent: available = trackingReady && frequentEnabled
        }
        if available { return SettingsSearchTarget(page: entry.page, anchor: entry.anchor, isPrerequisite: false) }
        if !trackingReady && entry.requirement != .trackingEnabled {
            return SettingsSearchTarget(page: .main, anchor: "settings.track-and-history", isPrerequisite: true)
        }
        switch entry.requirement {
        case .localHistory:
            return SettingsSearchTarget(page: .main, anchor: anchor("save_location_history_to_server"), isPrerequisite: true)
        case .smartFrequent:
            let page: SettingsSearchPage = entry.page == .main ? .main : .advanced
            return SettingsSearchTarget(page: page, anchor: anchor("smart_frequent_background_location_updates_title"), isPrerequisite: true)
        case .frequent:
            let key = smartFrequentEnabled
                ? "frequent_background_location_updates_title"
                : "smart_frequent_background_location_updates_title"
            return SettingsSearchTarget(page: .advanced, anchor: anchor(key), isPrerequisite: true)
        case .tracking:
            return SettingsSearchTarget(page: .main, anchor: anchor("location_track"), isPrerequisite: true)
        case .trackingEnabled:
            return SettingsSearchTarget(page: .main, anchor: anchor("location_track"), isPrerequisite: true)
        case .none:
            return SettingsSearchTarget(page: entry.fallbackPage, anchor: entry.fallbackAnchor, isPrerequisite: true)
        }
    }

    private static func main(_ key: String, _ table: String, _ aliases: [String], _ requirement: SettingsSearchRequirement = .none) -> SettingsSearchEntry {
        SettingsSearchEntry(key: key, table: table, aliases: aliases, page: .main, requirement: requirement, fallbackPage: .main, fallbackAnchor: "settings.track-and-history")
    }

    private static func button(_ key: String, _ table: String, _ aliases: [String], _ page: SettingsSearchPage, _ requirement: SettingsSearchRequirement = .none) -> SettingsSearchEntry {
        SettingsSearchEntry(key: key, table: table, aliases: aliases, page: page, requirement: requirement, fallbackPage: page, fallbackAnchor: "")
    }

    private static func advanced(_ key: String, _ table: String, _ aliases: [String], _ requirement: SettingsSearchRequirement = .none) -> SettingsSearchEntry {
        let fallback = requirement == .none ? SettingsSearchPage.advanced : SettingsSearchPage.main
        let anchor = requirement == .none ? "settings.navigation" : "settings.track-and-history"
        return SettingsSearchEntry(key: key, table: table, aliases: aliases, page: .advanced, requirement: requirement, fallbackPage: fallback, fallbackAnchor: anchor)
    }
}
