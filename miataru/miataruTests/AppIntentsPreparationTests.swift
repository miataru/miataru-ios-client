/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * AppIntentsPreparationTests.swift
 * miataruTests
 *
 * Created by Codex on 09.06.26.
 */

import CoreLocation
import Foundation
import MiataruAPIClient
import Testing
import UIKit
@testable import miataru

@Suite("App Intents preparation")
struct AppIntentsPreparationTests {
    @Test("KnownDevice maps to tracked person entity")
    func knownDeviceMapsToTrackedPersonEntity() {
        let device = KnownDevice(name: "Steffi", deviceID: "DEVICE-1", color: UIColor.systemBlue, hasCurrentLocationAccess: true)

        let record = MiataruIntentLocationDataProvider.record(from: device)
        let entity = IntentLocationService.entity(from: record)

        #expect(record.id == "DEVICE-1")
        #expect(record.name == "Steffi")
        #expect(record.hasCurrentLocationAccess)
        #expect(entity.id == "DEVICE-1")
        #expect(entity.name == "Steffi")
    }

    @Test("Suggested people only include visible devices with current location access")
    func suggestedPeopleOnlyIncludeVisibleDevices() async throws {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentPersonRecord(id: "VISIBLE-1", name: "Daniel", hasCurrentLocationAccess: true),
                    IntentPersonRecord(id: "HIDDEN-1", name: "Hidden", hasCurrentLocationAccess: false),
                    IntentPersonRecord(id: "  ", name: "Empty", hasCurrentLocationAccess: true)
                ]
            )
        )

        let people = try await service.suggestedPeople()

        #expect(people == [TrackedPersonEntity(id: "VISIBLE-1", name: "Daniel")])
    }

    @Test("API location payload maps to intent person location")
    func apiLocationPayloadMapsToIntentPersonLocation() {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let apiLocation = MiataruLocationData(
            Device: "DEVICE-1",
            Timestamp: String(Int64(timestamp.timeIntervalSince1970)),
            Longitude: 13.405,
            Latitude: 52.52,
            HorizontalAccuracy: 12
        )
        let person = IntentPersonRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)

        let payload = MiataruIntentLocationDataProvider.payload(from: apiLocation)
        let location = IntentLocationService.location(from: payload, person: person, placeDescription: "Berlin, Germany")

        #expect(location.personID == "DEVICE-1")
        #expect(location.displayName == "Steffi")
        #expect(location.latitude == 52.52)
        #expect(location.longitude == 13.405)
        #expect(location.timestamp == timestamp)
        #expect(location.horizontalAccuracy == 12)
        #expect(location.placeDescription == "Berlin, Germany")
    }

    @Test("Latest location throws when no location exists")
    func latestLocationThrowsWhenNoLocationExists() async {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentPersonRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ]
            )
        )

        await expectLocationError(.noLocationAvailable) {
            _ = try await service.latestLocation(for: "DEVICE-1")
        }
    }

    @Test("Person without current location access is not visible and cannot be queried")
    func personWithoutCurrentLocationAccessIsNotVisible() async throws {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentPersonRecord(id: "DEVICE-HIDDEN", name: "Hidden", hasCurrentLocationAccess: false)
                ],
                payloads: [
                    "DEVICE-HIDDEN": IntentLocationPayload(
                        deviceID: "DEVICE-HIDDEN",
                        latitude: 52,
                        longitude: 13,
                        timestamp: Date(),
                        horizontalAccuracy: 20
                    )
                ]
            )
        )

        let people = try await service.suggestedPeople()
        let person = try await service.person(for: "DEVICE-HIDDEN")

        #expect(people.isEmpty)
        #expect(person == nil)
        await expectLocationError(.unauthorized) {
            _ = try await service.latestLocation(for: "DEVICE-HIDDEN")
        }
    }

    @Test("Apple Maps URL uses coordinates and does not leak person identifiers")
    func appleMapsURLUsesCoordinatesWithoutDeviceIDLeak() throws {
        let location = IntentPersonLocation(
            personID: "SECRET-DEVICE-ID",
            displayName: "Steffi",
            latitude: 52.52,
            longitude: 13.405,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            horizontalAccuracy: 12,
            placeDescription: "Berlin"
        )

        let url = OpenRouteToPersonIntent.appleMapsURL(for: location)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let destination = components.queryItems?.first { $0.name == "daddr" }?.value

        #expect(components.scheme == "http")
        #expect(components.host == "maps.apple.com")
        #expect(destination == "52.52,13.405")
        #expect(!url.absoluteString.contains("SECRET-DEVICE-ID"))
        #expect(!url.absoluteString.contains("Steffi"))
    }

    @Test("Frequent tracking start requires normal location tracking")
    func frequentTrackingStartRequiresNormalLocationTracking() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(locationTrackingEnabled: false)
        )
        let service = IntentFrequentTrackingService(controller: controller)

        await expectFrequentTrackingError(.locationTrackingDisabled) {
            _ = try await service.startFrequentTracking()
        }

        #expect(controller.startCallCount == 0)
        #expect(controller.reconcileReasons.isEmpty)
    }

    @Test("Frequent tracking start fails while DeviceKey auth is blocked")
    func frequentTrackingStartFailsWhileDeviceKeyAuthIsBlocked() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(deviceKeyAuthBlocked: true)
        )
        let service = IntentFrequentTrackingService(controller: controller)

        await expectFrequentTrackingError(.deviceKeyBlocked) {
            _ = try await service.startFrequentTracking()
        }

        #expect(controller.startCallCount == 0)
        #expect(controller.reconcileReasons.isEmpty)
    }

    @Test("Frequent tracking start requires Always location authorization")
    func frequentTrackingStartRequiresAlwaysLocationAuthorization() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(authorizationStatus: .authorizedWhenInUse)
        )
        let service = IntentFrequentTrackingService(controller: controller)

        await expectFrequentTrackingError(.alwaysAuthorizationRequired) {
            _ = try await service.startFrequentTracking()
        }

        #expect(controller.startCallCount == 0)
        #expect(controller.reconcileReasons.isEmpty)
    }

    @Test("Frequent tracking start enables manual frequent mode using configured duration")
    func frequentTrackingStartEnablesManualFrequentModeUsingConfiguredDuration() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(durationMode: .oneHour)
        )
        let service = IntentFrequentTrackingService(controller: controller, nowProvider: { now })

        let result = try await service.startFrequentTracking()
        let expectedExpiration = try #require(FrequentBackgroundLocationUpdateDuration.oneHour.expirationDate(from: now))

        #expect(!result.wasAlreadyActive)
        #expect(result.durationMode == .oneHour)
        #expect(result.expiresAt == expectedExpiration)
        #expect(controller.currentState.manualFrequentTrackingEnabled)
        #expect(controller.currentState.frequentTrackingExpiresAt == expectedExpiration)
        #expect(controller.startCallCount == 1)
        #expect(controller.reconcileReasons == ["start frequent tracking intent"])
    }

    @Test("Frequent tracking start renews active manual frequent expiration")
    func frequentTrackingStartRenewsActiveManualFrequentExpiration() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldExpiration = now.addingTimeInterval(60)
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(
                manualFrequentTrackingEnabled: true,
                frequentTrackingExpiresAt: oldExpiration,
                durationMode: .fourHours
            )
        )
        let service = IntentFrequentTrackingService(controller: controller, nowProvider: { now })

        let result = try await service.startFrequentTracking()
        let expectedExpiration = try #require(FrequentBackgroundLocationUpdateDuration.fourHours.expirationDate(from: now))

        #expect(result.wasAlreadyActive)
        #expect(result.expiresAt == expectedExpiration)
        #expect(controller.currentState.frequentTrackingExpiresAt == expectedExpiration)
    }

    @Test("Frequent tracking stop disables manual frequent mode and is idempotent")
    func frequentTrackingStopDisablesManualFrequentModeAndIsIdempotent() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(
                manualFrequentTrackingEnabled: true,
                frequentTrackingExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        let service = IntentFrequentTrackingService(controller: controller)

        let firstResult = await service.stopFrequentTracking()
        let secondResult = await service.stopFrequentTracking()

        #expect(firstResult.wasActive)
        #expect(!secondResult.wasActive)
        #expect(!controller.currentState.manualFrequentTrackingEnabled)
        #expect(controller.currentState.frequentTrackingExpiresAt == nil)
        #expect(controller.stopCallCount == 2)
        #expect(controller.reconcileReasons == [
            "stop frequent tracking intent",
            "stop frequent tracking intent"
        ])
    }

    @Test("App Intent localization keys exist for all app locales")
    func appIntentLocalizationKeysExistForAllAppLocales() throws {
        let data = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/miataru/Assets/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        let locales = ["da", "de", "en", "es", "fi", "fr", "it", "ja", "nl", "zh-Hans"]
        let intentKeys = strings.keys.filter { $0.hasPrefix("intent_") }.sorted()

        #expect(!intentKeys.isEmpty)

        var missingEntries: [String] = []
        for key in intentKeys {
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                missingEntries.append("\(key):all")
                continue
            }

            for locale in locales {
                guard let localeEntry = localizations[locale] as? [String: Any],
                      let stringUnit = localeEntry["stringUnit"] as? [String: Any],
                      let value = stringUnit["value"] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    missingEntries.append("\(key):\(locale)")
                    continue
                }
            }
        }

        #expect(missingEntries.isEmpty, "Missing App Intent localizations: \(missingEntries)")
    }

    private func expectLocationError(
        _ expectedError: IntentLocationError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expectedError), but operation succeeded")
        } catch let error as IntentLocationError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), but got \(error)")
        }
    }

    private func expectFrequentTrackingError(
        _ expectedError: IntentFrequentTrackingError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expectedError), but operation succeeded")
        } catch let error as IntentFrequentTrackingError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), but got \(error)")
        }
    }

    private func frequentTrackingState(
        locationTrackingEnabled: Bool = true,
        deviceKeyAuthBlocked: Bool = false,
        authorizationStatus: CLAuthorizationStatus = .authorizedAlways,
        manualFrequentTrackingEnabled: Bool = false,
        frequentTrackingExpiresAt: Date? = nil,
        durationMode: FrequentBackgroundLocationUpdateDuration = .fourHours
    ) -> IntentFrequentTrackingState {
        IntentFrequentTrackingState(
            locationTrackingEnabled: locationTrackingEnabled,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            authorizationStatus: authorizationStatus,
            manualFrequentTrackingEnabled: manualFrequentTrackingEnabled,
            frequentTrackingExpiresAt: frequentTrackingExpiresAt,
            durationMode: durationMode
        )
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class FakeFrequentTrackingController: IntentFrequentTrackingControlling {
    var currentState: IntentFrequentTrackingState
    var startCallCount = 0
    var stopCallCount = 0
    var reconcileReasons: [String] = []

    init(state: IntentFrequentTrackingState) {
        self.currentState = state
    }

    func state() async -> IntentFrequentTrackingState {
        currentState
    }

    func startManualFrequentTracking(now: Date) async {
        startCallCount += 1
        currentState = IntentFrequentTrackingState(
            locationTrackingEnabled: currentState.locationTrackingEnabled,
            deviceKeyAuthBlocked: currentState.deviceKeyAuthBlocked,
            authorizationStatus: currentState.authorizationStatus,
            manualFrequentTrackingEnabled: true,
            frequentTrackingExpiresAt: currentState.durationMode.expirationDate(from: now),
            durationMode: currentState.durationMode
        )
    }

    func stopManualFrequentTracking() async {
        stopCallCount += 1
        currentState = IntentFrequentTrackingState(
            locationTrackingEnabled: currentState.locationTrackingEnabled,
            deviceKeyAuthBlocked: currentState.deviceKeyAuthBlocked,
            authorizationStatus: currentState.authorizationStatus,
            manualFrequentTrackingEnabled: false,
            frequentTrackingExpiresAt: nil,
            durationMode: currentState.durationMode
        )
    }

    func reconcileTrackingState(reason: String) async {
        reconcileReasons.append(reason)
    }
}

private struct FakeIntentLocationProvider: IntentLocationDataProviding {
    var records: [IntentPersonRecord] = []
    var payloads: [String: IntentLocationPayload] = [:]
    var placeDescriptions: [String: String] = [:]

    func personRecords() async -> [IntentPersonRecord] {
        records
    }

    func latestLocationPayload(for personID: String) async throws -> IntentLocationPayload? {
        payloads[personID]
    }

    func cachedPlaceDescription(for personID: String) async -> String? {
        placeDescriptions[personID]
    }
}
