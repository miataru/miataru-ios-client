/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationTrackingHealthReminderService.swift
 * miataru
 *
 * Created by Codex on 14.06.26.
 */

import Foundation
import UserNotifications

actor LocationTrackingHealthReminderService {
    static let shared = LocationTrackingHealthReminderService()

    static let notificationIdentifier = "location_tracking_health_reminder"
    static let notificationType = "location_tracking_health_reminder"
    static let notificationTypeUserInfoKey = UnknownVisitorAlertService.notificationTypeUserInfoKey

    private enum Keys {
        static let lastConfirmedActivityDate = "location_tracking_health_reminder_last_confirmed_activity_date"
        static let scheduledFireDate = "location_tracking_health_reminder_scheduled_fire_date"
    }

    private let defaults: UserDefaults
    private let notifier: LocalNotificationNotifying
    private let nowProvider: () -> Date

    init(defaults: UserDefaults = .standard,
         notifier: LocalNotificationNotifying = LiveLocalNotificationNotifier(),
         nowProvider: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.notifier = notifier
        self.nowProvider = nowProvider
    }

    func recordConfirmedActivity(
        locationTrackingEnabled: Bool,
        interval: LocationTrackingHealthReminderInterval
    ) async {
        guard locationTrackingEnabled else {
            await cancel()
            return
        }

        let now = nowProvider()
        defaults.set(now, forKey: Keys.lastConfirmedActivityDate)
        await scheduleReminder(lastConfirmedActivityDate: now, interval: interval)
    }

    func refresh(
        locationTrackingEnabled: Bool,
        interval: LocationTrackingHealthReminderInterval
    ) async {
        guard locationTrackingEnabled else {
            await cancel()
            return
        }

        let lastConfirmedActivityDate: Date
        if let persistedDate = defaults.object(forKey: Keys.lastConfirmedActivityDate) as? Date {
            lastConfirmedActivityDate = persistedDate
        } else {
            lastConfirmedActivityDate = nowProvider()
            defaults.set(lastConfirmedActivityDate, forKey: Keys.lastConfirmedActivityDate)
        }

        await scheduleReminder(lastConfirmedActivityDate: lastConfirmedActivityDate, interval: interval)
    }

    func cancel() async {
        await cancelScheduledReminder()
    }

    private func scheduleReminder(
        lastConfirmedActivityDate: Date,
        interval: LocationTrackingHealthReminderInterval
    ) async {
        guard await ensureAuthorization() else {
            await cancelScheduledReminder()
            return
        }

        let now = nowProvider()
        let targetFireDate = lastConfirmedActivityDate.addingTimeInterval(interval.timeInterval)
        let fireDate = max(targetFireDate, now.addingTimeInterval(1))
        let pendingRequests = await notifier.pendingNotificationRequests()
        let hasPendingReminder = pendingRequests.contains { $0.identifier == Self.notificationIdentifier }
        if hasPendingReminder,
           let scheduledFireDate = defaults.object(forKey: Keys.scheduledFireDate) as? Date,
           scheduledFireDate == fireDate {
            return
        }

        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "location_tracking_health_reminder_notification_title",
            comment: "Notification title reminding the user to open Miataru to confirm location tracking is working"
        )
        content.body = NSLocalizedString(
            "location_tracking_health_reminder_notification_body",
            comment: "Notification body explaining that Miataru should be opened after a long quiet period"
        )
        content.sound = .default
        content.userInfo = [
            Self.notificationTypeUserInfoKey: Self.notificationType
        ]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDate.timeIntervalSince(now)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await notifier.add(request)
            defaults.set(fireDate, forKey: Keys.scheduledFireDate)
        } catch {
            debugLog("[LocationTrackingHealthReminderService] Failed scheduling reminder notification: \(error)")
        }
    }

    private func cancelScheduledReminder() async {
        await notifier.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
        await notifier.removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
        defaults.removeObject(forKey: Keys.scheduledFireDate)
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
                debugLog("[LocationTrackingHealthReminderService] Notification authorization request failed: \(error)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
