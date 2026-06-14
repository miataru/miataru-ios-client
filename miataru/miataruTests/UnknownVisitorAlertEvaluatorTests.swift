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

@Suite(.serialized)
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
            MiataruVisitor(DeviceID: " own_device ", TimeStamp: msString(now)),
            MiataruVisitor(DeviceID: " known_device ", TimeStamp: msString(now.addingTimeInterval(5))),
            MiataruVisitor(DeviceID: " ignored_device ", TimeStamp: msString(now.addingTimeInterval(10))),
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

    @Test("Unknown visitor filter excludes known ignored and own IDs")
    func unknownVisitorFilterExcludesKnownIgnoredAndOwnIDs() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let unknownID = "unknown_device"
        let visitors = [
            MiataruVisitor(DeviceID: "known_device", TimeStamp: msString(now.addingTimeInterval(10))),
            MiataruVisitor(DeviceID: "ignored_device", TimeStamp: msString(now.addingTimeInterval(20))),
            MiataruVisitor(DeviceID: "own_device", TimeStamp: msString(now.addingTimeInterval(30))),
            MiataruVisitor(DeviceID: " \(unknownID) ", TimeStamp: msString(now.addingTimeInterval(40))),
            MiataruVisitor(DeviceID: unknownID.uppercased(), TimeStamp: msString(now.addingTimeInterval(50)))
        ]

        let filteredVisitors = UnknownVisitorFilter.visitors(
            from: visitors,
            knownDeviceIDs: [" KNOWN_DEVICE "],
            ignoredDeviceIDs: ["IGNORED_DEVICE"],
            ownDeviceID: "OWN_DEVICE"
        )

        #expect(filteredVisitors.count == 1)
        #expect(filteredVisitors.first?.DeviceID == "UNKNOWN_DEVICE")
        #expect(filteredVisitors.first?.TimeStamp == msString(now.addingTimeInterval(50)))
    }

    @Test("Alert enrichment requests locations only for unknown candidates")
    func alertEnrichmentRequestsLocationsOnlyForUnknownCandidates() async throws {
        let suiteName = "UnknownVisitorAlertTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let knownID = "KNOWN_ALLOWED_DEVICE_\(UUID().uuidString)"
        let unknownID = "UNKNOWN_DEVICE_\(UUID().uuidString)"
        let dataProvider = MockUnknownVisitorAlertDataProvider(visitors: [
            MiataruVisitor(DeviceID: knownID.lowercased(), TimeStamp: msString(now.addingTimeInterval(1))),
            MiataruVisitor(DeviceID: " \(unknownID.lowercased()) ", TimeStamp: msString(now.addingTimeInterval(2)))
        ])
        let notifier = MockUnknownVisitorAlertNotifier(
            initialStatus: .authorized,
            requestAuthorizationResult: .success(true)
        )
        let recorder = MockAutomationEventRecorder()
        let service = UnknownVisitorAlertService(
            defaults: defaults,
            notifier: notifier,
            dataProvider: dataProvider,
            eventRecorder: recorder,
            nowProvider: { now }
        )
        await service.processVisitorHistory(
            [
                MiataruVisitor(DeviceID: knownID.lowercased(), TimeStamp: msString(now.addingTimeInterval(1))),
                MiataruVisitor(DeviceID: " \(unknownID.lowercased()) ", TimeStamp: msString(now.addingTimeInterval(2)))
            ],
            serverURL: URL(string: "https://example.org")!,
            runtime: UnknownVisitorAlertRuntime(
                ownDeviceID: "OWN_DEVICE",
                deviceKey: "test-device-key",
                knownDeviceIDs: [knownID],
                ignoredDeviceIDs: []
            )
        )

        let locationRequests = await dataProvider.locationRequests
        let addedRequests = await notifier.addedRequests
        #expect(locationRequests == [[UnknownVisitorAlertEvaluator.normalizeDeviceID(unknownID)]])
        #expect(addedRequests.count == 1)
        #expect(addedRequests.first?.content.userInfo[UnknownVisitorAlertService.notificationDeviceIDUserInfoKey] as? String == UnknownVisitorAlertEvaluator.normalizeDeviceID(unknownID))
        #expect(addedRequests.first?.content.sound == MiataruNotificationSounds.unknownVisitor)
        let events = await recorder.recordedEvents()
        #expect(events.map(\.kind) == [.unknownVisitorDetected])
        #expect(events.first?.privacyLevel == .securitySensitive)
        #expect(events.first?.deviceID == UnknownVisitorAlertEvaluator.normalizeDeviceID(unknownID))
        #expect(events.first?.payload["visitorDeviceID"] == UnknownVisitorAlertEvaluator.normalizeDeviceID(unknownID))
    }

    @Test("Unknown visitor event is emitted only after notification scheduling succeeds")
    func unknownVisitorEventIsEmittedOnlyAfterNotificationSchedulingSucceeds() async throws {
        let suiteName = "UnknownVisitorAlertTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let unknownID = "UNKNOWN_DEVICE_\(UUID().uuidString)"
        let dataProvider = MockUnknownVisitorAlertDataProvider(visitors: [])
        let notifier = MockUnknownVisitorAlertNotifier(
            initialStatus: .authorized,
            requestAuthorizationResult: .success(true),
            addError: TestNotificationError.addFailed
        )
        let recorder = MockAutomationEventRecorder()
        let service = UnknownVisitorAlertService(
            defaults: defaults,
            notifier: notifier,
            dataProvider: dataProvider,
            eventRecorder: recorder,
            nowProvider: { now }
        )

        await service.processVisitorHistory(
            [
                MiataruVisitor(DeviceID: " \(unknownID.lowercased()) ", TimeStamp: msString(now.addingTimeInterval(2)))
            ],
            serverURL: URL(string: "https://example.org")!,
            runtime: UnknownVisitorAlertRuntime(
                ownDeviceID: "OWN_DEVICE",
                deviceKey: "test-device-key",
                knownDeviceIDs: [],
                ignoredDeviceIDs: []
            )
        )

        let addedRequests = await notifier.addedRequests
        let events = await recorder.recordedEvents()
        #expect(addedRequests.isEmpty)
        #expect(events.isEmpty)
    }

    @Test("Known visitors do not trigger alert enrichment")
    func knownVisitorsDoNotTriggerAlertEnrichment() async throws {
        let suiteName = "UnknownVisitorAlertTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let knownID = "KNOWN_ONLY_DEVICE_\(UUID().uuidString)"
        let dataProvider = MockUnknownVisitorAlertDataProvider(visitors: [
            MiataruVisitor(DeviceID: " \(knownID.lowercased()) ", TimeStamp: msString(now.addingTimeInterval(1)))
        ])
        let notifier = MockUnknownVisitorAlertNotifier(
            initialStatus: .authorized,
            requestAuthorizationResult: .success(true)
        )
        let service = UnknownVisitorAlertService(
            defaults: defaults,
            notifier: notifier,
            dataProvider: dataProvider,
            eventRecorder: NoOpMiataruAutomationEventRecorder(),
            nowProvider: { now }
        )
        await service.processVisitorHistory(
            [
                MiataruVisitor(DeviceID: " \(knownID.lowercased()) ", TimeStamp: msString(now.addingTimeInterval(1)))
            ],
            serverURL: URL(string: "https://example.org")!,
            runtime: UnknownVisitorAlertRuntime(
                ownDeviceID: "OWN_DEVICE",
                deviceKey: "test-device-key",
                knownDeviceIDs: [knownID],
                ignoredDeviceIDs: []
            )
        )

        let locationRequests = await dataProvider.locationRequests
        let addedRequests = await notifier.addedRequests
        #expect(locationRequests.isEmpty)
        #expect(addedRequests.isEmpty)
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

private enum TestNotificationError: Error {
    case addFailed
}

private actor MockAutomationEventRecorder: MiataruAutomationEventRecording {
    private var events: [MiataruAutomationEventRecord] = []

    func record(_ event: MiataruAutomationEventRecord) async {
        events.append(event)
    }

    func record(
        kind: MiataruAutomationEventKind,
        privacyLevel: MiataruAutomationEventPrivacyLevel,
        deviceID: String?,
        deviceDisplayName: String?,
        placeID: String?,
        placeName: String?,
        payload: [String: String]
    ) async {
        events.append(MiataruAutomationEventRecord(
            kind: kind,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            privacyLevel: privacyLevel,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            placeID: placeID,
            placeName: placeName,
            payload: payload
        ))
    }

    func recordedEvents() -> [MiataruAutomationEventRecord] {
        events
    }
}

actor MockUnknownVisitorAlertNotifier: UnknownVisitorAlertNotifying {
    private let status: UNAuthorizationStatus
    private let requestAuthorizationResult: Result<Bool, Error>
    private let addError: Error?
    private(set) var didRequestAuthorization: Bool = false
    private(set) var addedRequests: [UNNotificationRequest] = []

    init(initialStatus: UNAuthorizationStatus,
         requestAuthorizationResult: Result<Bool, Error>,
         addError: Error? = nil) {
        self.status = initialStatus
        self.requestAuthorizationResult = requestAuthorizationResult
        self.addError = addError
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
        if let addError {
            throw addError
        }
        addedRequests.append(request)
    }
}

actor MockUnknownVisitorAlertDataProvider: UnknownVisitorAlertDataProviding {
    private let visitors: [MiataruVisitor]
    private(set) var locationRequests: [[String]] = []

    init(visitors: [MiataruVisitor]) {
        self.visitors = visitors
    }

    func getVisitorHistory(serverURL: URL,
                           forDeviceID deviceID: String,
                           deviceKey: String,
                           amount: Int) async throws -> [MiataruVisitor] {
        _ = serverURL
        _ = deviceID
        _ = deviceKey
        _ = amount
        return visitors
    }

    func getLocation(serverURL: URL,
                     forDeviceIDs deviceIDs: [String],
                     requestingDeviceID: String,
                     requestingDeviceKey: String) async throws -> [MiataruLocationData] {
        _ = serverURL
        _ = requestingDeviceID
        _ = requestingDeviceKey
        locationRequests.append(deviceIDs)
        return []
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

    @Test("Smart frequent mode-change notifications are immediate and typed")
    func smartFrequentModeChangeNotificationsAreImmediateAndTyped() async throws {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.notifySmartFrequentModeChange(isActive: true)
        await service.notifySmartFrequentModeChange(isActive: false)

        let addedRequests = await notifier.addedRequests
        #expect(addedRequests.count == 2)

        let activatedRequest = try #require(addedRequests.first)
        #expect(activatedRequest.identifier == FrequentBackgroundTrackingReminderService.smartFrequentActivatedNotificationIdentifier)
        #expect(activatedRequest.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.smartFrequentActivatedNotificationType)
        #expect(activatedRequest.trigger == nil)
        #expect(activatedRequest.content.sound == MiataruNotificationSounds.smartFrequentActivated)
        #expect(!activatedRequest.content.title.isEmpty)
        #expect(!activatedRequest.content.body.isEmpty)

        let deactivatedRequest = try #require(addedRequests.last)
        #expect(deactivatedRequest.identifier == FrequentBackgroundTrackingReminderService.smartFrequentDeactivatedNotificationIdentifier)
        #expect(deactivatedRequest.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.smartFrequentDeactivatedNotificationType)
        #expect(deactivatedRequest.trigger == nil)
        #expect(deactivatedRequest.content.sound == MiataruNotificationSounds.smartFrequentDeactivated)
        #expect(!deactivatedRequest.content.title.isEmpty)
        #expect(!deactivatedRequest.content.body.isEmpty)
    }

    @Test("Smart frequent restart recovery deactivation notification uses restart-specific body")
    func smartFrequentRestartRecoveryDeactivationNotificationUsesRestartSpecificBody() async throws {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.notifySmartFrequentModeChange(isActive: false)
        await service.notifySmartFrequentModeChange(
            isActive: false,
            deactivationReason: .restartRecovery
        )

        let addedRequests = await notifier.addedRequests
        #expect(addedRequests.count == 2)

        let inactivityRequest = try #require(addedRequests.first)
        let restartRequest = try #require(addedRequests.last)
        #expect(restartRequest.identifier == FrequentBackgroundTrackingReminderService.smartFrequentDeactivatedNotificationIdentifier)
        #expect(restartRequest.content.userInfo[FrequentBackgroundTrackingReminderService.notificationTypeUserInfoKey] as? String == FrequentBackgroundTrackingReminderService.smartFrequentDeactivatedNotificationType)
        #expect(restartRequest.trigger == nil)
        #expect(restartRequest.content.sound == MiataruNotificationSounds.smartFrequentDeactivated)
        #expect(!restartRequest.content.body.isEmpty)
        #expect(restartRequest.content.body != inactivityRequest.content.body)
    }

    @Test("Smart frequent mode-change notifications respect denied authorization")
    func smartFrequentModeChangeNotificationsRespectDeniedAuthorization() async {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .denied)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        await service.notifySmartFrequentModeChange(isActive: true)

        #expect(await notifier.addedRequests.isEmpty)
    }

    @Test("Smart frequent mode-change notification permission is requested before enabling")
    func smartFrequentModeChangeNotificationPermissionIsRequestedBeforeEnabling() async {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .notDetermined,
            requestAuthorizationResult: .success(true)
        )
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        let granted = await service.requestSmartFrequentModeChangeNotificationAuthorization()

        #expect(granted)
        #expect(await notifier.didRequestAuthorization)
    }

    @Test("Smart frequent mode-change notification permission denial is reported")
    func smartFrequentModeChangeNotificationPermissionDenialIsReported() async {
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .denied)
        let service = FrequentBackgroundTrackingReminderService(notifier: notifier)

        let granted = await service.requestSmartFrequentModeChangeNotificationAuthorization()

        #expect(!granted)
        #expect(!(await notifier.didRequestAuthorization))
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

struct LocationTrackingHealthReminderServiceTests {
    private static let lastConfirmedActivityDateKey = "location_tracking_health_reminder_last_confirmed_activity_date"
    private static let scheduledFireDateKey = "location_tracking_health_reminder_scheduled_fire_date"

    @Test("Tracking health reminder schedules one-shot default five-day notification")
    func trackingHealthReminderSchedulesDefaultFiveDayNotification() async throws {
        let suiteName = "LocationTrackingHealthReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 20_000)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .notDetermined,
            requestAuthorizationResult: .success(true)
        )
        let service = LocationTrackingHealthReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.refresh(locationTrackingEnabled: true, interval: .fiveDays)

        #expect(await notifier.didRequestAuthorization)
        let request = try #require(await notifier.addedRequests.first)
        #expect(request.identifier == LocationTrackingHealthReminderService.notificationIdentifier)
        #expect(request.content.userInfo[LocationTrackingHealthReminderService.notificationTypeUserInfoKey] as? String == LocationTrackingHealthReminderService.notificationType)

        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == LocationTrackingHealthReminderInterval.fiveDays.timeInterval)
        #expect(!trigger.repeats)
        #expect(defaults.object(forKey: Self.lastConfirmedActivityDateKey) as? Date == now)
        #expect(defaults.object(forKey: Self.scheduledFireDateKey) as? Date == now.addingTimeInterval(LocationTrackingHealthReminderInterval.fiveDays.timeInterval))
    }

    @Test("Confirmed health activity reschedules from the newest activity date")
    func confirmedHealthActivityReschedulesFromNewestActivityDate() async throws {
        let suiteName = "LocationTrackingHealthReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var now = Date(timeIntervalSince1970: 20_000)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = LocationTrackingHealthReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.recordConfirmedActivity(locationTrackingEnabled: true, interval: .sevenDays)
        now = now.addingTimeInterval(3_600)
        await service.recordConfirmedActivity(locationTrackingEnabled: true, interval: .sevenDays)

        let addedRequests = await notifier.addedRequests
        #expect(addedRequests.count == 2)
        #expect(await notifier.removedPendingIdentifiers.contains(LocationTrackingHealthReminderService.notificationIdentifier))

        let request = try #require(addedRequests.last)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == LocationTrackingHealthReminderInterval.sevenDays.timeInterval)
        #expect(defaults.object(forKey: Self.lastConfirmedActivityDateKey) as? Date == now)
        #expect(defaults.object(forKey: Self.scheduledFireDateKey) as? Date == now.addingTimeInterval(LocationTrackingHealthReminderInterval.sevenDays.timeInterval))
    }

    @Test("Health reminder refresh preserves the previous confirmed activity date")
    func healthReminderRefreshPreservesPreviousConfirmedActivityDate() async throws {
        let suiteName = "LocationTrackingHealthReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 100_000)
        let lastConfirmedActivity = now.addingTimeInterval(-86_400)
        defaults.set(lastConfirmedActivity, forKey: Self.lastConfirmedActivityDateKey)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(initialStatus: .authorized)
        let service = LocationTrackingHealthReminderService(
            defaults: defaults,
            notifier: notifier,
            nowProvider: { now }
        )

        await service.refresh(locationTrackingEnabled: true, interval: .sevenDays)

        let request = try #require(await notifier.addedRequests.first)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == TimeInterval(6 * 24 * 60 * 60))
        #expect(defaults.object(forKey: Self.lastConfirmedActivityDateKey) as? Date == lastConfirmedActivity)
        #expect(defaults.object(forKey: Self.scheduledFireDateKey) as? Date == lastConfirmedActivity.addingTimeInterval(LocationTrackingHealthReminderInterval.sevenDays.timeInterval))
    }

    @Test("Disabled tracking cancels health reminder notifications")
    func disabledTrackingCancelsHealthReminderNotifications() async throws {
        let suiteName = "LocationTrackingHealthReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Date(timeIntervalSince1970: 100_000), forKey: Self.scheduledFireDateKey)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .notDetermined,
            pendingRequests: [Self.existingHealthReminderRequest()]
        )
        let service = LocationTrackingHealthReminderService(defaults: defaults, notifier: notifier)

        await service.refresh(locationTrackingEnabled: false, interval: .fiveDays)

        #expect(await notifier.didRequestAuthorization == false)
        #expect(await notifier.addedRequests.isEmpty)
        #expect(await notifier.removedPendingIdentifiers.contains(LocationTrackingHealthReminderService.notificationIdentifier))
        #expect(await notifier.removedDeliveredIdentifiers.contains(LocationTrackingHealthReminderService.notificationIdentifier))
        #expect(defaults.object(forKey: Self.scheduledFireDateKey) == nil)
    }

    @Test("Denied notification authorization cancels health reminder notifications")
    func deniedNotificationAuthorizationCancelsHealthReminderNotifications() async throws {
        let suiteName = "LocationTrackingHealthReminderTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Date(timeIntervalSince1970: 100_000), forKey: Self.scheduledFireDateKey)
        let notifier = MockFrequentBackgroundTrackingReminderNotifier(
            initialStatus: .denied,
            pendingRequests: [Self.existingHealthReminderRequest()]
        )
        let service = LocationTrackingHealthReminderService(defaults: defaults, notifier: notifier)

        await service.refresh(locationTrackingEnabled: true, interval: .fiveDays)

        #expect(await notifier.addedRequests.isEmpty)
        #expect(await notifier.removedPendingIdentifiers.contains(LocationTrackingHealthReminderService.notificationIdentifier))
        #expect(await notifier.removedDeliveredIdentifiers.contains(LocationTrackingHealthReminderService.notificationIdentifier))
        #expect(defaults.object(forKey: Self.scheduledFireDateKey) == nil)
    }

    private static func existingHealthReminderRequest() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.userInfo = [
            LocationTrackingHealthReminderService.notificationTypeUserInfoKey: LocationTrackingHealthReminderService.notificationType
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        return UNNotificationRequest(
            identifier: LocationTrackingHealthReminderService.notificationIdentifier,
            content: content,
            trigger: trigger
        )
    }
}

actor MockFrequentBackgroundTrackingReminderNotifier: LocalNotificationNotifying {
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
