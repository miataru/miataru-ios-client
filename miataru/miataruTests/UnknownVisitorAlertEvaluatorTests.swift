/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * UnknownVisitorAlertEvaluatorTests.swift
 * miataruTests
 *
 * Created by Codex on 09.03.26.
 */

import Testing
import Foundation
import UserNotifications
import MiataruAPIClient
@testable import miataru

struct UnknownVisitorAlertEvaluatorTests {
    @Test("Unknown visitor with new timestamp is selected")
    func unknownVisitorWithNewTimestampIsSelected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visitor = MiataruVisitor(
            DeviceID: "UNKNOWN_DEVICE",
            TimeStamp: msString(now)
        )

        let result = UnknownVisitorAlertEvaluator.evaluate(
            visitors: [visitor],
            lastProcessedTimestampMs: 0,
            ownDeviceID: "OWN_DEVICE",
            knownDeviceIDs: [],
            ignoredDeviceIDs: [],
            lastNotifiedAtByDeviceID: [:]
        )

        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.deviceID == "UNKNOWN_DEVICE")
        #expect(result.newWatermarkMs == Int64(msString(now))!)
    }

    @Test("Cooldown suppresses repeated notifications within 24h")
    func cooldownSuppressesRepeatedNotifications() {
        let notificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let visitDate = notificationDate.addingTimeInterval(60 * 60) // +1h
        let visitor = MiataruVisitor(
            DeviceID: "UNKNOWN_DEVICE",
            TimeStamp: msString(visitDate)
        )

        let result = UnknownVisitorAlertEvaluator.evaluate(
            visitors: [visitor],
            lastProcessedTimestampMs: 0,
            ownDeviceID: "OWN_DEVICE",
            knownDeviceIDs: [],
            ignoredDeviceIDs: [],
            lastNotifiedAtByDeviceID: ["UNKNOWN_DEVICE": notificationDate]
        )

        #expect(result.candidates.isEmpty)
    }

    @Test("Visitor is re-notified after 24h cooldown")
    func visitorRenotifiesAfterCooldown() {
        let notificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let visitDate = notificationDate.addingTimeInterval(25 * 60 * 60) // +25h
        let visitor = MiataruVisitor(
            DeviceID: "UNKNOWN_DEVICE",
            TimeStamp: msString(visitDate)
        )

        let result = UnknownVisitorAlertEvaluator.evaluate(
            visitors: [visitor],
            lastProcessedTimestampMs: 0,
            ownDeviceID: "OWN_DEVICE",
            knownDeviceIDs: [],
            ignoredDeviceIDs: [],
            lastNotifiedAtByDeviceID: ["UNKNOWN_DEVICE": notificationDate]
        )

        #expect(result.candidates.count == 1)
    }

    @Test("Known, ignored, and own device IDs are excluded")
    func knownIgnoredAndOwnIDsAreExcluded() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visitors = [
            MiataruVisitor(DeviceID: "OWN_DEVICE", TimeStamp: msString(now)),
            MiataruVisitor(DeviceID: "KNOWN_DEVICE", TimeStamp: msString(now.addingTimeInterval(5))),
            MiataruVisitor(DeviceID: "IGNORED_DEVICE", TimeStamp: msString(now.addingTimeInterval(10))),
            MiataruVisitor(DeviceID: "UNKNOWN_DEVICE", TimeStamp: msString(now.addingTimeInterval(15)))
        ]

        let result = UnknownVisitorAlertEvaluator.evaluate(
            visitors: visitors,
            lastProcessedTimestampMs: 0,
            ownDeviceID: "OWN_DEVICE",
            knownDeviceIDs: ["KNOWN_DEVICE"],
            ignoredDeviceIDs: ["IGNORED_DEVICE"],
            lastNotifiedAtByDeviceID: [:]
        )

        #expect(result.candidates.count == 1)
        #expect(result.candidates.first?.deviceID == "UNKNOWN_DEVICE")
    }

    @Test("Permission request enables feature when authorization is granted")
    func permissionRequestEnablesFeatureWhenGranted() async throws {
        let suiteName = "UnknownVisitorAlertTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let notifier = MockUnknownVisitorAlertNotifier(
            initialStatus: .notDetermined,
            requestAuthorizationResult: .success(true)
        )
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_500)
        let service = UnknownVisitorAlertService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { fixedNow }
        )

        let result = await service.setFeatureEnabled(true)
        #expect(result == .enabled)
        #expect(await notifier.didRequestAuthorization == true)
    }

    @Test("Denied authorization disables feature activation")
    func deniedAuthorizationDisablesFeatureActivation() async throws {
        let suiteName = "UnknownVisitorAlertTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let notifier = MockUnknownVisitorAlertNotifier(
            initialStatus: .denied,
            requestAuthorizationResult: .success(false)
        )
        let service = UnknownVisitorAlertService(defaults: defaults, notifier: notifier)

        let result = await service.setFeatureEnabled(true)
        #expect(result == .denied)
        #expect(await notifier.didRequestAuthorization == false)
    }

    @Test("Background visitor check throttle respects configured minimum interval")
    func backgroundVisitorCheckThrottleRespectsMinimumInterval() {
        let now = Date(timeIntervalSince1970: 2_000)

        #expect(BackgroundVisitorCheckThrottle.shouldRun(
            lastCheckAt: nil,
            now: now,
            minimumInterval: 600
        ))
        #expect(!BackgroundVisitorCheckThrottle.shouldRun(
            lastCheckAt: now.addingTimeInterval(-599),
            now: now,
            minimumInterval: 600
        ))
        #expect(BackgroundVisitorCheckThrottle.shouldRun(
            lastCheckAt: now.addingTimeInterval(-600),
            now: now,
            minimumInterval: 600
        ))
        #expect(BackgroundVisitorCheckThrottle.shouldRun(
            lastCheckAt: now,
            now: now,
            minimumInterval: nil
        ))
    }

    private func msString(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000.0).rounded()))
    }
}

actor MockUnknownVisitorAlertNotifier: UnknownVisitorAlertNotifying {
    private let status: UNAuthorizationStatus
    private let requestAuthorizationResult: Result<Bool, Error>
    private(set) var didRequestAuthorization: Bool = false

    init(initialStatus: UNAuthorizationStatus,
         requestAuthorizationResult: Result<Bool, Error>) {
        self.status = initialStatus
        self.requestAuthorizationResult = requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        _ = options
        didRequestAuthorization = true
        switch requestAuthorizationResult {
        case .success(let granted):
            return granted
        case .failure(let error):
            throw error
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        _ = request
    }
}

struct FrequentBackgroundTrackingReminderServiceTests {
    @Test("Never-expiring frequent background mode schedules a repeating 24h reminder")
    func neverExpiringFrequentBackgroundModeSchedulesReminder() async throws {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: true,
            durationMode: .unlimited,
            expiresAt: nil
        )

        let addedRequests = await notifier.addedRequests
        let request = try #require(addedRequests.first)
        #expect(request.identifier == FrequentBackgroundTrackingReminderService.notificationIdentifier)
        #expect(request.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.notificationType)

        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == FrequentBackgroundTrackingReminderService.reminderInterval)
        #expect(trigger.repeats)
    }

    @Test("Existing reminder is kept so the 24h timer is not reset repeatedly")
    func existingReminderIsKeptWithoutRescheduling() async {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .authorized,
            pendingRequests: [Self.existingReminderRequest()]
        )
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: true,
            durationMode: .unlimited,
            expiresAt: nil
        )

        #expect(await notifier.addedRequests.isEmpty)
        #expect(await notifier.removedPendingIdentifiers.isEmpty)
    }

    @Test("Finite or inactive frequent background mode removes the reminder")
    func inactiveModeRemovesReminder() async {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: true,
            durationMode: .fourHours,
            expiresAt: nil
        )

        #expect(await notifier.addedRequests.isEmpty)
        #expect(await notifier.removedPendingIdentifiers.contains(FrequentBackgroundTrackingReminderService.notificationIdentifier))
        #expect(await notifier.removedDeliveredIdentifiers.contains(FrequentBackgroundTrackingReminderService.notificationIdentifier))
    }

    @Test("Undetermined notification permission is requested before scheduling")
    func undeterminedPermissionIsRequestedBeforeScheduling() async throws {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .notDetermined,
            requestAuthorizationResult: .success(true)
        )
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: true,
            durationMode: .unlimited,
            expiresAt: nil
        )

        #expect(await notifier.didRequestAuthorization)
        #expect(await notifier.addedRequests.count == 1)
    }

    @Test("Finite frequent background mode schedules one expiration notification")
    func finiteFrequentBackgroundModeSchedulesExpirationNotification() async throws {
        let suiteName = "FrequentBackgroundTrackingReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 2_000)
        let expiresAt = now.addingTimeInterval(600)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = FrequentBackgroundTrackingReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: true,
            durationMode: .fourHours,
            expiresAt: expiresAt
        )

        let addedRequests = await notifier.addedRequests
        let request = try #require(addedRequests.first)
        #expect(request.identifier == FrequentBackgroundTrackingReminderService.expirationNotificationIdentifier)
        #expect(request.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.expirationNotificationType)

        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 600)
        #expect(!trigger.repeats)
        #expect(defaults.object(forKey: "frequent_background_tracking_expiration_notification_date") as? Date == expiresAt)
    }

    @Test("Manual finite mode disable cancels future expiration notification")
    func manualFiniteModeDisableCancelsFutureExpirationNotification() async throws {
        let suiteName = "FrequentBackgroundTrackingReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 2_000)
        defaults.set(now.addingTimeInterval(600), forKey: "frequent_background_tracking_expiration_notification_date")
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .authorized,
            pendingRequests: [Self.existingExpirationRequest()]
        )
        let service = FrequentBackgroundTrackingReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: false,
            durationMode: .fourHours,
            expiresAt: nil
        )

        #expect(await notifier.removedPendingIdentifiers.contains(FrequentBackgroundTrackingReminderService.expirationNotificationIdentifier))
        #expect(defaults.object(forKey: "frequent_background_tracking_expiration_notification_date") == nil)
    }

    @Test("Automatic finite mode expiry does not cancel due expiration notification")
    func automaticFiniteModeExpiryDoesNotCancelDueExpirationNotification() async throws {
        let suiteName = "FrequentBackgroundTrackingReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 2_000)
        defaults.set(now, forKey: "frequent_background_tracking_expiration_notification_date")
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .authorized,
            pendingRequests: [Self.existingExpirationRequest()]
        )
        let service = FrequentBackgroundTrackingReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.refresh(
            locationTrackingEnabled: true,
            frequentBackgroundUpdatesEnabled: false,
            durationMode: .fourHours,
            expiresAt: nil
        )

        #expect(!(await notifier.removedPendingIdentifiers.contains(FrequentBackgroundTrackingReminderService.expirationNotificationIdentifier)))
        #expect(defaults.object(forKey: "frequent_background_tracking_expiration_notification_date") == nil)
    }

    @Test("Low battery auto-disable cancels timers and sends explanatory notification")
    func lowBatteryAutoDisableCancelsTimersAndSendsNotification() async throws {
        let suiteName = "FrequentBackgroundTrackingReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 2_000)
        defaults.set(now.addingTimeInterval(600), forKey: "frequent_background_tracking_expiration_notification_date")
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .authorized,
            pendingRequests: [
                Self.existingReminderRequest(),
                Self.existingExpirationRequest()
            ]
        )
        let service = FrequentBackgroundTrackingReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.notifyBatteryAutoDisable(batteryPercent: 29, thresholdPercent: 30)

        #expect(await notifier.removedPendingIdentifiers.contains(FrequentBackgroundTrackingReminderService.notificationIdentifier))
        #expect(await notifier.removedDeliveredIdentifiers.contains(FrequentBackgroundTrackingReminderService.notificationIdentifier))
        #expect(await notifier.removedPendingIdentifiers.contains(FrequentBackgroundTrackingReminderService.expirationNotificationIdentifier))
        #expect(defaults.object(forKey: "frequent_background_tracking_expiration_notification_date") == nil)

        let request = try #require(await notifier.addedRequests.last)
        #expect(request.identifier == FrequentBackgroundTrackingReminderService.batteryAutoDisableNotificationIdentifier)
        #expect(request.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.batteryAutoDisableNotificationType)
        #expect(request.trigger == nil)
        #expect(request.content.body.contains("29"))
        #expect(request.content.body.contains("30"))
    }

    private static func existingReminderRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey: FrequentBackgroundTrackingReminderService.notificationType
        ]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: FrequentBackgroundTrackingReminderService.reminderInterval,
            repeats: true
        )
        return UNNotificationRequest(
            identifier: FrequentBackgroundTrackingReminderService.notificationIdentifier,
            content: content,
            trigger: trigger
        )
    }

    private static func existingExpirationRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey: FrequentBackgroundTrackingReminderService.expirationNotificationType
        ]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 600,
            repeats: false
        )
        return UNNotificationRequest(
            identifier: FrequentBackgroundTrackingReminderService.expirationNotificationIdentifier,
            content: content,
            trigger: trigger
        )
    }
}

actor MockFrequentBackgroundTrackingReminderNotifier: FrequentBackgroundTrackingReminderNotifying {
    private var status: UNAuthorizationStatus
    private let requestAuthorizationResult: Result<Bool, Error>
    private(set) var didRequestAuthorization: Bool = false
    private(set) var pendingRequests: [UNNotificationRequest]
    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedPendingIdentifiers: [String] = []
    private(set) var removedDeliveredIdentifiers: [String] = []

    init(initialStatus: UNAuthorizationStatus,
         pendingRequests: [UNNotificationRequest] = [],
         requestAuthorizationResult: Result<Bool, Error> = .success(false)) {
        self.status = initialStatus
        self.pendingRequests = pendingRequests
        self.requestAuthorizationResult = requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        _ = options
        didRequestAuthorization = true
        switch requestAuthorizationResult {
        case .success(let granted):
            status = granted ? .authorized : .denied
            return granted
        case .failure(let error):
            throw error
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingRequests
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
        pendingRequests.removeAll { $0.identifier == request.identifier }
        pendingRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        removedPendingIdentifiers.append(contentsOf: identifiers)
        pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        removedDeliveredIdentifiers.append(contentsOf: identifiers)
    }
}
