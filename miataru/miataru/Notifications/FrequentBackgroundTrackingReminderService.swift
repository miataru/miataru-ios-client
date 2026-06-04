/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * FrequentBackgroundTrackingReminderService.swift
 * miataru
 *
 * Created by Codex on 26.04.26.
 */

import Foundation
import UserNotifications

protocol FrequentBackgroundTrackingReminderNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func pendingNotificationRequests() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
}

struct LiveFrequentBackgroundTrackingReminderNotifier: FrequentBackgroundTrackingReminderNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

actor FrequentBackgroundTrackingReminderService {
    static let shared = FrequentBackgroundTrackingReminderService()

    static let notificationIdentifier = "frequent_background_tracking_reminder"
    static let notificationType = "frequent_background_tracking_reminder"
    static let expirationNotificationIdentifier = "frequent_background_tracking_expired"
    static let expirationNotificationType = "frequent_background_tracking_expired"
    static let batteryAutoDisableNotificationIdentifier = "frequent_background_tracking_battery_auto_disabled"
    static let batteryAutoDisableNotificationType = "frequent_background_tracking_battery_auto_disabled"
    static let smartFrequentActivatedNotificationIdentifier = "smart_frequent_background_tracking_activated"
    static let smartFrequentActivatedNotificationType = "smart_frequent_background_tracking_activated"
    static let smartFrequentDeactivatedNotificationIdentifier = "smart_frequent_background_tracking_deactivated"
    static let smartFrequentDeactivatedNotificationType = "smart_frequent_background_tracking_deactivated"
    static let notificationTypeUserInfoKey = UnknownVisitorAlertService.notificationTypeUserInfoKey
    static let reminderInterval: TimeInterval = 24 * 60 * 60

    private enum Keys {
        static let scheduledExpirationDate = "frequent_background_tracking_expiration_notification_date"
    }

    private let defaults: UserDefaults
    private let notifier: FrequentBackgroundTrackingReminderNotifying
    private let nowProvider: () -> Date

    init(defaults: UserDefaults = .standard,
         notifier: FrequentBackgroundTrackingReminderNotifying = LiveFrequentBackgroundTrackingReminderNotifier(),
         nowProvider: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.notifier = notifier
        self.nowProvider = nowProvider
    }

    func refresh(locationTrackingEnabled: Bool,
                 frequentBackgroundUpdatesEnabled: Bool,
                 durationMode: FrequentBackgroundLocationUpdateDuration,
                 expiresAt: Date?) async {
        if locationTrackingEnabled,
           frequentBackgroundUpdatesEnabled,
           durationMode == .unlimited {
            await scheduleReminderIfNeeded()
        } else {
            await cancelDailyReminder()
        }

        if locationTrackingEnabled,
           frequentBackgroundUpdatesEnabled,
           let expiresAt {
            await scheduleExpirationNotificationIfNeeded(expiresAt: expiresAt)
        } else {
            await cancelScheduledExpirationNotificationIfNeeded()
        }
    }

    func cancel() async {
        await cancelDailyReminder()
        await cancelScheduledExpirationNotificationIfNeeded()
    }

    func notifyBatteryAutoDisable(batteryPercent: Int, thresholdPercent: Int) async {
        await cancelForBatteryAutoDisable()

        guard await ensureAuthorization() else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "frequent_background_location_battery_auto_disabled_notification_title",
            tableName: nil,
            bundle: .main,
            value: "Background updates switched to standard",
            comment: "Notification title shown when low battery automatically disables frequent background tracking"
        )
        let bodyFormat = NSLocalizedString(
            "frequent_background_location_battery_auto_disabled_notification_body_format",
            tableName: nil,
            bundle: .main,
            value: "Battery is at %@ and reached the %@ limit. Miataru turned off more frequent background updates and is now using standard mode.",
            comment: "Notification body explaining that low battery disabled frequent background tracking"
        )
        content.body = String(
            format: bodyFormat,
            locale: Locale.current,
            Self.localizedPercentString(from: batteryPercent),
            Self.localizedPercentString(from: thresholdPercent)
        )
        content.sound = .default
        content.userInfo = [
            Self.notificationTypeUserInfoKey: Self.batteryAutoDisableNotificationType
        ]

        let request = UNNotificationRequest(
            identifier: Self.batteryAutoDisableNotificationIdentifier,
            content: content,
            trigger: nil
        )

        do {
            await notifier.removePendingNotificationRequests(withIdentifiers: [Self.batteryAutoDisableNotificationIdentifier])
            try await notifier.add(request)
        } catch {
            debugLog("[FrequentBackgroundTrackingReminderService] Failed scheduling battery auto-disable notification: \(error)")
        }
    }

    func notifySmartFrequentModeChange(isActive: Bool) async {
        guard await ensureAuthorization() else {
            return
        }

        let content = UNMutableNotificationContent()
        if isActive {
            content.title = NSLocalizedString(
                "smart_frequent_background_activated_notification_title",
                comment: "Notification title shown when smart frequent background tracking turns frequent updates on"
            )
            content.body = NSLocalizedString(
                "smart_frequent_background_activated_notification_body",
                comment: "Notification body explaining that movement activated smart frequent background tracking"
            )
            content.userInfo = [
                Self.notificationTypeUserInfoKey: Self.smartFrequentActivatedNotificationType
            ]
        } else {
            content.title = NSLocalizedString(
                "smart_frequent_background_deactivated_notification_title",
                comment: "Notification title shown when smart frequent background tracking returns to standard mode"
            )
            content.body = NSLocalizedString(
                "smart_frequent_background_deactivated_notification_body",
                comment: "Notification body explaining that inactivity stopped smart frequent background tracking"
            )
            content.userInfo = [
                Self.notificationTypeUserInfoKey: Self.smartFrequentDeactivatedNotificationType
            ]
        }
        content.sound = .default

        let identifier = isActive
            ? Self.smartFrequentActivatedNotificationIdentifier
            : Self.smartFrequentDeactivatedNotificationIdentifier
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        do {
            await notifier.removePendingNotificationRequests(withIdentifiers: [identifier])
            try await notifier.add(request)
        } catch {
            debugLog("[FrequentBackgroundTrackingReminderService] Failed scheduling smart frequent mode-change notification: \(error)")
        }
    }

    private static func localizedPercentString(from percent: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: Double(percent) / 100)) ?? "\(percent)%"
    }

    private func cancelForBatteryAutoDisable() async {
        await cancelDailyReminder()
        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationIdentifier])
        defaults.removeObject(forKey: Keys.scheduledExpirationDate)
    }

    private func cancelDailyReminder() async {
        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        await notifier.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    private func cancelScheduledExpirationNotificationIfNeeded() async {
        guard let scheduledExpirationDate = defaults.object(forKey: Keys.scheduledExpirationDate) as? Date else {
            return
        }

        if scheduledExpirationDate <= nowProvider() {
            defaults.removeObject(forKey: Keys.scheduledExpirationDate)
            return
        }

        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationIdentifier])
        defaults.removeObject(forKey: Keys.scheduledExpirationDate)
    }

    private func scheduleReminderIfNeeded() async {
        guard await ensureAuthorization() else {
            await cancelDailyReminder()
            return
        }

        let pendingRequests = await notifier.pendingNotificationRequests()
        if pendingRequests.contains(where: { $0.identifier == Self.notificationIdentifier }) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "frequent_background_location_reminder_notification_title",
            comment: "Notification title reminding the user that never-expiring frequent background tracking is still active"
        )
        content.body = NSLocalizedString(
            "frequent_background_location_reminder_notification_body",
            comment: "Notification body explaining that tapping opens Advanced Options to disable frequent background tracking"
        )
        content.sound = .default
        content.userInfo = [
            Self.notificationTypeUserInfoKey: Self.notificationType
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: Self.reminderInterval,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notifier.add(request)
        } catch {
            debugLog("[FrequentBackgroundTrackingReminderService] Failed scheduling reminder notification: \(error)")
        }
    }

    private func scheduleExpirationNotificationIfNeeded(expiresAt: Date) async {
        let interval = expiresAt.timeIntervalSince(nowProvider())
        guard interval > 0 else { return }

        guard await ensureAuthorization() else {
            await notifier.removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationIdentifier])
            defaults.removeObject(forKey: Keys.scheduledExpirationDate)
            return
        }

        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.expirationNotificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "frequent_background_location_expired_notification_title",
            comment: "Notification title shown when temporary frequent background tracking has automatically ended"
        )
        content.body = NSLocalizedString(
            "frequent_background_location_expired_notification_body",
            comment: "Notification body explaining that Miataru returned to standard background tracking"
        )
        content.sound = .default
        content.userInfo = [
            Self.notificationTypeUserInfoKey: Self.expirationNotificationType
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, interval),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.expirationNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notifier.add(request)
            defaults.set(expiresAt, forKey: Keys.scheduledExpirationDate)
        } catch {
            debugLog("[FrequentBackgroundTrackingReminderService] Failed scheduling expiration notification: \(error)")
        }
    }

    private func ensureAuthorization() async -> Bool {
        let status = await notifier.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await notifier.requestAuthorization(options: [.alert, .sound])
            } catch {
                debugLog("[FrequentBackgroundTrackingReminderService] Notification authorization request failed: \(error)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
