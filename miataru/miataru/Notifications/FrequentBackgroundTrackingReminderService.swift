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
