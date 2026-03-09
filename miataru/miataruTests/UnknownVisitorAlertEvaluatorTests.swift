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
