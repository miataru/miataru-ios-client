/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * UnknownVisitorAlertLocalizationTests.swift
 * miataruTests
 *
 * Created by Codex on 09.03.26.
 */

import Testing
import Foundation

struct UnknownVisitorAlertLocalizationTests {
    @Test("Unknown visitor alert localization keys exist for all app locales")
    func unknownVisitorAlertLocalizationKeysExistForAllLocales() throws {
        let expectedLocales: Set<String> = ["da", "de", "en", "es", "fi", "fr", "it", "ja", "nl", "zh-Hans"]
        let requiredKeys = [
            "unknown_visitor_alerts_toggle",
            "explanation_unknown_visitor_alerts_toggle",
            "unknown_visitor_alerts_permission_denied_message",
            "unknown_visitor_alerts_open_settings_button",
            "onboarding_unknown_visitor_alerts_title",
            "onboarding_unknown_visitor_alerts_intro_text",
            "onboarding_unknown_visitor_alerts_example_title",
            "onboarding_unknown_visitor_alerts_example_message",
            "unknown_visitor_alert_notification_title",
            "unknown_visitor_alert_notification_body_with_details",
            "unknown_visitor_alert_notification_body_fallback",
            "known_visitor_alerts_section_title",
            "known_visitor_alerts_toggle",
            "known_visitor_alerts_explanation",
            "known_visitor_alerts_permission_denied_message",
            "known_visitor_alert_notification_title",
            "known_visitor_alert_notification_body_format",
            "known_visitor_notification_cooldown_title",
            "known_visitor_notification_cooldown_1m_explanation",
            "known_visitor_notification_cooldown_5m_explanation",
            "known_visitor_notification_cooldown_15m_explanation",
            "known_visitor_notification_cooldown_30m_explanation",
            "known_visitor_notification_cooldown_60m_explanation",
            "unknown_device_actions_title",
            "unknown_device_actions_message_acl_enabled",
            "unknown_device_actions_message_acl_disabled"
        ]

        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // miataruTests
            .deletingLastPathComponent() // project root folder in repo
        let localizationFolderURL = repoRoot
            .appendingPathComponent("miataru/Assets/Localization")
        let catalogNames = [
            "AppIntents",
            "AppShortcuts",
            "AutomationEvents",
            "Common",
            "Devices",
            "Groups",
            "Localizable",
            "LocationTracking",
            "MapNavigationHistory",
            "OnboardingQR",
            "SettingsDiagnostics"
        ]
        var strings: [String: Any] = [:]
        for catalogName in catalogNames {
            let data = try Data(contentsOf: localizationFolderURL.appendingPathComponent("\(catalogName).xcstrings"))
            let jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let catalogStrings = try #require(jsonObject["strings"] as? [String: Any])
            for (key, value) in catalogStrings {
                #expect(strings[key] == nil, "Duplicate localization key across string catalogs: \(key)")
                strings[key] = value
            }
        }

        for key in requiredKeys {
            let keyEntry = try #require(strings[key] as? [String: Any], "Missing localization key: \(key)")
            let localizations = try #require(keyEntry["localizations"] as? [String: Any], "Missing localizations block for key: \(key)")

            let localeSet = Set(localizations.keys)
            #expect(localeSet == expectedLocales, "Locales mismatch for key \(key): \(localeSet)")

            for locale in expectedLocales {
                let localeEntry = try #require(localizations[locale] as? [String: Any], "Missing locale \(locale) for key \(key)")
                let stringUnit = try #require(localeEntry["stringUnit"] as? [String: Any], "Missing stringUnit for key \(key), locale \(locale)")
                let value = try #require(stringUnit["value"] as? String, "Missing value for key \(key), locale \(locale)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty value for key \(key), locale \(locale)")
            }
        }
    }
}
