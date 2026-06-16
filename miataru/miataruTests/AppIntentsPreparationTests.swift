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
    @Test("KnownDevice maps to tracked device entity")
    func knownDeviceMapsToTrackedDeviceEntity() {
        let device = KnownDevice(name: "Steffi", deviceID: "DEVICE-1", color: UIColor.systemBlue, hasCurrentLocationAccess: true)

        let record = MiataruIntentLocationDataProvider.record(from: device)
        let entity = IntentLocationService.entity(from: record)

        #expect(record.id == "DEVICE-1")
        #expect(record.name == "Steffi")
        #expect(record.hasCurrentLocationAccess)
        #expect(entity.id == "DEVICE-1")
        #expect(entity.name == "Steffi")
    }

    @Test("Suggested devices only include visible devices with current location access")
    func suggestedDevicesOnlyIncludeVisibleDevices() async throws {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: " VISIBLE-1 ", name: "Daniel", hasCurrentLocationAccess: true),
                    IntentDeviceRecord(id: "HIDDEN-1", name: "Hidden", hasCurrentLocationAccess: false),
                    IntentDeviceRecord(id: "  ", name: "Empty", hasCurrentLocationAccess: true)
                ]
            )
        )

        let devices = try await service.suggestedDevices()

        #expect(devices == [TrackedDeviceEntity(id: "VISIBLE-1", name: "Daniel")])
    }

    @Test("Dynamic string options keep DeviceID values")
    func dynamicStringOptionsKeepDeviceIDValues() {
        let devices = [
            TrackedDeviceEntity(id: "DEVICE-1", name: "Daniel"),
            TrackedDeviceEntity(id: "DEVICE-2", name: "Steffi")
        ]

        #expect(TrackedDeviceOptionsProvider.optionValues(for: devices) == ["DEVICE-1", "DEVICE-2"])
    }

    @Test("Tracked device metadata excludes empty and unauthorized devices")
    func trackedDeviceMetadataExcludesEmptyAndUnauthorizedDevices() {
        let visible = KnownDevice(name: "Steffi", deviceID: " DEVICE-1 ", hasCurrentLocationAccess: true)
        let hidden = KnownDevice(name: "Hidden", deviceID: "DEVICE-HIDDEN", hasCurrentLocationAccess: false)
        let empty = KnownDevice(name: "Empty", deviceID: "  ", hasCurrentLocationAccess: true)

        #expect(TrackedDeviceIntentMetadata.entity(for: visible) == TrackedDeviceEntity(id: "DEVICE-1", name: "Steffi"))
        #expect(TrackedDeviceIntentMetadata.entity(for: hidden) == nil)
        #expect(TrackedDeviceIntentMetadata.entity(for: empty) == nil)
    }

    @Test("Tracked device indexed attributes contain display name only")
    func trackedDeviceIndexedAttributesContainDisplayNameOnly() {
        let entity = TrackedDeviceEntity(id: "SECRET-DEVICE-ID", name: "Steffi")
        let attributes = entity.attributeSet

        #expect(entity.hideInSpotlight)
        #expect(attributes.title == "Steffi")
        #expect(attributes.displayName == "Steffi")
        #expect(attributes.latitude == nil)
        #expect(attributes.longitude == nil)
        #expect(attributes.contentDescription == nil)
        #expect(attributes.keywords == nil)
    }

    @Test("Tracked device user activity annotation is entity-only and not searchable")
    func trackedDeviceUserActivityAnnotationIsEntityOnlyAndNotSearchable() {
        guard #available(iOS 26.0, *) else { return }

        let entity = TrackedDeviceEntity(id: "DEVICE-1", name: "Steffi")
        let activity = NSUserActivity(activityType: TrackedDeviceIntentMetadata.userActivityType)

        TrackedDeviceIntentMetadata.annotate(activity, with: entity)

        #expect(activity.title == "Steffi")
        #expect(activity.appEntityIdentifier == TrackedDeviceIntentMetadata.entityIdentifier(for: entity))
        #expect(activity.isEligibleForSearch == false)
        #expect(activity.isEligibleForPublicIndexing == false)
        #expect(activity.isEligibleForHandoff == false)
        #expect(activity.isEligibleForPrediction == false)
        #expect(activity.userInfo?.isEmpty ?? true)
    }

    @Test("Place entity maps and indexed attributes exclude private location data")
    func placeEntityMapsAndIndexedAttributesExcludePrivateLocationData() {
        let record = MiataruPlaceRecord(
            id: UUID(),
            deviceID: "DEVICE-1",
            name: "Home",
            latitude: 52.52,
            longitude: 13.405,
            radiusMeters: 150,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let entity = MiataruPlaceIntentMetadata.entity(from: record)
        let attributes = entity.attributeSet

        #expect(entity.id == record.id)
        #expect(entity.deviceID == "DEVICE-1")
        #expect(entity.name == "Home")
        #expect(entity.radiusMeters == 150)
        #expect(!entity.hideInSpotlight)
        #expect(attributes.title == "Home")
        #expect(attributes.displayName == "Home")
        #expect(attributes.latitude == nil)
        #expect(attributes.longitude == nil)
        #expect(attributes.keywords == nil)
        #expect(attributes.contentDescription?.contains("150") ?? true)
    }

    @Test("Place user activity annotation is searchable without raw coordinates")
    func placeUserActivityAnnotationIsSearchableWithoutRawCoordinates() {
        guard #available(iOS 26.0, *) else { return }

        let entity = MiataruPlaceEntity(id: UUID(), deviceID: "DEVICE-1", name: "Home", radiusMeters: 150)
        let activity = NSUserActivity(activityType: MiataruPlaceIntentMetadata.userActivityType)

        MiataruPlaceIntentMetadata.annotate(activity, with: entity)

        #expect(activity.title == "Home")
        #expect(activity.appEntityIdentifier == MiataruPlaceIntentMetadata.entityIdentifier(for: entity))
        #expect(activity.isEligibleForSearch)
        #expect(activity.isEligibleForPublicIndexing == false)
        #expect(activity.isEligibleForHandoff == false)
        #expect(activity.isEligibleForPrediction == false)
        #expect(activity.userInfo?.isEmpty ?? true)
    }

    @Test("Place query resolves exact IDs and case-insensitive names")
    func placeQueryResolvesExactIDsAndNames() async throws {
        let homeID = UUID()
        let officeID = UUID()
        let query = MiataruPlaceQuery(
            service: FakePlaceIntentService(
                places: [
                    MiataruPlaceEntity(id: homeID, deviceID: "DEVICE-1", name: "Home", radiusMeters: 150),
                    MiataruPlaceEntity(id: officeID, deviceID: "DEVICE-2", name: "Office", radiusMeters: 250)
                ]
            )
        )

        let exact = try await query.entities(for: [officeID])
        let matching = try await query.entities(matching: "hom")

        #expect(exact == [MiataruPlaceEntity(id: officeID, deviceID: "DEVICE-2", name: "Office", radiusMeters: 250)])
        #expect(matching == [MiataruPlaceEntity(id: homeID, deviceID: "DEVICE-1", name: "Home", radiusMeters: 150)])
    }

    @Test("API location payload maps to intent device location")
    func apiLocationPayloadMapsToIntentDeviceLocation() {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let apiLocation = MiataruLocationData(
            Device: "DEVICE-1",
            Timestamp: String(Int64(timestamp.timeIntervalSince1970)),
            Longitude: 13.405,
            Latitude: 52.52,
            HorizontalAccuracy: 12
        )
        let device = IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)

        let payload = MiataruIntentLocationDataProvider.payload(from: apiLocation)
        let location = IntentLocationService.location(from: payload, device: device, placeDescription: "Berlin, Germany")

        #expect(location.deviceID == "DEVICE-1")
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
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ]
            )
        )

        await expectLocationError(.noLocationAvailable) {
            _ = try await service.latestLocation(for: "DEVICE-1")
        }
    }

    @Test("Device without current location access is not visible and cannot be queried")
    func deviceWithoutCurrentLocationAccessIsNotVisible() async throws {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-HIDDEN", name: "Hidden", hasCurrentLocationAccess: false)
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

        let devices = try await service.suggestedDevices()
        let device = try await service.device(for: "DEVICE-HIDDEN")

        #expect(devices.isEmpty)
        #expect(device == nil)
        await expectLocationError(.unauthorized) {
            _ = try await service.latestLocation(for: "DEVICE-HIDDEN")
        }
    }

    @Test("Apple Maps URL uses coordinates and does not leak device identifiers")
    func appleMapsURLUsesCoordinatesWithoutDeviceIDLeak() throws {
        let location = IntentDeviceLocation(
            deviceID: "SECRET-DEVICE-ID",
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
        #expect(components.queryItems?.contains { $0.name == "saddr" } == false)
        #expect(components.queryItems?.contains { $0.name == "dirflg" } == false)
        #expect(!url.absoluteString.contains("SECRET-DEVICE-ID"))
        #expect(!url.absoluteString.contains("Steffi"))
    }

    @Test("Latest location request dialog includes device and requester place")
    func latestLocationRequestDialogIncludesDeviceAndPlace() {
        let entry = KnownVisitorAccessHistoryEntry(
            id: UUID(),
            deviceID: "DEVICE-1",
            deviceDisplayName: "Steffi",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            latitude: 52.52,
            longitude: 13.405,
            placeDescription: "Berlin, Germany"
        )

        let dialog = GetLatestLocationRequestIntent.dialogText(for: entry, displayName: "Steffi")

        #expect(dialog.contains("Steffi"))
        #expect(dialog.contains("Berlin, Germany"))
    }

    @Test("Apple Maps URL supports direction and explicit transport without leaking identifiers")
    func appleMapsURLSupportsDirectionAndTransport() throws {
        let location = IntentDeviceLocation(
            deviceID: "SECRET-DEVICE-ID",
            displayName: "Steffi",
            latitude: 52.52,
            longitude: 13.405,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            horizontalAccuracy: 12,
            placeDescription: "Berlin"
        )

        let url = OpenRouteToPersonIntent.appleMapsURL(
            for: location,
            direction: .deviceToUser,
            transportMode: .walking
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(queryItems["saddr"] == "52.52,13.405")
        #expect(queryItems["daddr"] == "Current Location")
        #expect(queryItems["dirflg"] == "w")
        #expect(!url.absoluteString.contains("SECRET-DEVICE-ID"))
        #expect(!url.absoluteString.contains("Steffi"))
    }

    @Test("Miataru navigation URL uses device ID and focused user-to-device mode")
    func miataruNavigationURLUsesDeviceIDAndFocusedMode() throws {
        let location = IntentDeviceLocation(
            deviceID: "DEVICE-1",
            displayName: "Steffi",
            latitude: 52.52,
            longitude: 13.405,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            horizontalAccuracy: 12,
            placeDescription: "Berlin"
        )

        let url = OpenMiataruNavigationToPersonIntent.miataruNavigationURL(for: location)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "miataru")
        #expect(components.host == "DEVICE-1")
        #expect(queryItems["action"] == "navigate")
        #expect(queryItems["direction"] == "userToDevice")
        #expect(queryItems["presentation"] == "focused")
        #expect(queryItems["transport"] == nil)
        #expect(!url.absoluteString.contains("Steffi"))
    }

    @Test("Miataru navigation URL supports direction presentation and transport")
    func miataruNavigationURLSupportsParameters() throws {
        let location = IntentDeviceLocation(
            deviceID: "DEVICE-1",
            displayName: "Steffi",
            latitude: 52.52,
            longitude: 13.405,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            horizontalAccuracy: 12,
            placeDescription: "Berlin"
        )

        let url = OpenMiataruNavigationToPersonIntent.miataruNavigationURL(
            for: location,
            direction: .deviceToUser,
            presentation: .standard,
            transportMode: .transit
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(queryItems["action"] == "navigate")
        #expect(queryItems["direction"] == "deviceToUser")
        #expect(queryItems["presentation"] == "overview")
        #expect(queryItems["transport"] == "transit")
        #expect(
            OpenMiataruNavigationToPersonIntent.miataruNavigationDestination(
                for: location,
                direction: .deviceToUser,
                presentation: .standard,
                transportMode: .transit
            ) == .navigation(
                "DEVICE-1",
                options: DeviceNavigationLaunchOptions(
                    direction: .deviceToUser,
                    presentation: .overview,
                    transportMode: .transit
                )
            )
        )
    }

    @Test("Miataru navigation intent opens app and resolves an internal navigation destination")
    func miataruNavigationIntentOpensAppAndResolvesInternalDestination() {
        let location = IntentDeviceLocation(
            deviceID: "DEVICE-1",
            displayName: "Steffi",
            latitude: 52.52,
            longitude: 13.405,
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            horizontalAccuracy: 12,
            placeDescription: "Berlin"
        )

        #expect(OpenMiataruNavigationToPersonIntent.openAppWhenRun)
        #expect(
            OpenMiataruNavigationToPersonIntent.miataruNavigationDestination(for: location) == .navigation(
                "DEVICE-1",
                options: .defaultDeepLink
            )
        )
    }

    @Test("Frequent tracking start requires normal location tracking")
    func frequentTrackingStartRequiresNormalLocationTracking() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(locationTrackingEnabled: false)
        )
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: NoOpMiataruAutomationEventRecorder())

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
        let recorder = FakeAutomationEventRecorder()
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: recorder)

        await expectFrequentTrackingError(.deviceKeyBlocked) {
            _ = try await service.startFrequentTracking()
        }

        #expect(controller.startCallCount == 0)
        #expect(controller.reconcileReasons.isEmpty)
        let records = await recorder.recordedEvents()
        #expect(records.map(\.kind) == [.deviceKeyBlockedOperation])
        #expect(records.first?.privacyLevel == .securitySensitive)
        #expect(records.first?.payload["operation"] == "startFrequentTracking")
    }

    @Test("Frequent tracking start requires Always location authorization")
    func frequentTrackingStartRequiresAlwaysLocationAuthorization() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(authorizationStatus: .authorizedWhenInUse)
        )
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: NoOpMiataruAutomationEventRecorder())

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
        let recorder = FakeAutomationEventRecorder()
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: recorder, nowProvider: { now })

        let result = try await service.startFrequentTracking()
        let expectedExpiration = try #require(FrequentBackgroundLocationUpdateDuration.oneHour.expirationDate(from: now))

        #expect(!result.wasAlreadyActive)
        #expect(result.durationMode == .oneHour)
        #expect(result.expiresAt == expectedExpiration)
        #expect(controller.currentState.manualFrequentTrackingEnabled)
        #expect(controller.currentState.frequentTrackingExpiresAt == expectedExpiration)
        #expect(controller.startCallCount == 1)
        #expect(controller.reconcileReasons == ["start frequent tracking intent"])
        let records = await recorder.recordedEvents()
        #expect(records.map(\.kind) == [.frequentTrackingStarted])
        #expect(records.first?.privacyLevel == .publicSummary)
        #expect(records.first?.payload["durationMode"] == "oneHour")
        #expect(records.first?.payload["wasAlreadyActive"] == "false")
    }

    @Test("Frequent tracking start accepts explicit duration override")
    func frequentTrackingStartAcceptsExplicitDurationOverride() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(durationMode: .oneHour)
        )
        let service = IntentFrequentTrackingService(
            controller: controller,
            eventRecorder: NoOpMiataruAutomationEventRecorder(),
            nowProvider: { now }
        )

        let result = try await service.startFrequentTracking(duration: .twelveHours)
        let expectedExpiration = try #require(FrequentBackgroundLocationUpdateDuration.twelveHours.expirationDate(from: now))

        #expect(result.durationMode == .twelveHours)
        #expect(result.expiresAt == expectedExpiration)
        #expect(controller.currentState.durationMode == .twelveHours)
        #expect(controller.currentState.frequentTrackingExpiresAt == expectedExpiration)
    }

    @Test("Frequent tracking start accepts explicit unlimited duration")
    func frequentTrackingStartAcceptsExplicitUnlimitedDuration() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(durationMode: .fourHours)
        )
        let service = IntentFrequentTrackingService(
            controller: controller,
            eventRecorder: NoOpMiataruAutomationEventRecorder(),
            nowProvider: { now }
        )

        let result = try await service.startFrequentTracking(duration: .unlimited)

        #expect(result.durationMode == .unlimited)
        #expect(result.expiresAt == nil)
        #expect(controller.currentState.durationMode == .unlimited)
        #expect(controller.currentState.frequentTrackingExpiresAt == nil)
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
        let service = IntentFrequentTrackingService(
            controller: controller,
            eventRecorder: NoOpMiataruAutomationEventRecorder(),
            nowProvider: { now }
        )

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
        let recorder = FakeAutomationEventRecorder()
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: recorder)

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
        let records = await recorder.recordedEvents()
        #expect(records.map(\.kind) == [.frequentTrackingStopped])
        #expect(records.first?.payload["durationMode"] == "fourHours")
    }

    @Test("Tracking status reports stopped when normal tracking is off")
    func trackingStatusReportsStoppedWhenTrackingIsOff() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(locationTrackingEnabled: false, locationTrackingActive: false)
        )
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: NoOpMiataruAutomationEventRecorder())

        let status = await service.trackingStatus()

        #expect(status.trackingEnabled == false)
        #expect(status.effectiveMode == .stopped)
        #expect(status.frequentTracking.blockingReason == .trackingDisabled)
        #expect(GetTrackingStatusIntent.isTrackingActive(status) == false)
    }

    @Test("Tracking status reports blocked while DeviceKey auth is blocked")
    func trackingStatusReportsDeviceKeyBlocked() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(deviceKeyAuthBlocked: true)
        )
        let service = IntentFrequentTrackingService(controller: controller, eventRecorder: NoOpMiataruAutomationEventRecorder())

        let status = await service.trackingStatus()

        #expect(status.deviceKeyAuthBlocked)
        #expect(status.effectiveMode == .blocked)
        #expect(status.frequentTracking.blockingReason == .deviceKeyBlocked)
        #expect(GetTrackingStatusIntent.dialogText(for: status).contains("SECRET-DEVICE-KEY") == false)
    }

    @Test("Tracking status maps smart and manual frequent modes")
    func trackingStatusMapsSmartAndManualFrequentModes() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let manualController = FakeFrequentTrackingController(
            state: frequentTrackingState(
                manualFrequentTrackingEnabled: true,
                frequentTrackingExpiresAt: now.addingTimeInterval(3_600)
            )
        )
        let smartController = FakeFrequentTrackingController(
            state: frequentTrackingState(
                smartFrequentTrackingEnabled: true,
                smartFrequentTrackingRuntimeActive: true
            )
        )
        let waitingController = FakeFrequentTrackingController(
            state: frequentTrackingState(smartFrequentTrackingEnabled: true)
        )

        let manualStatus = await IntentFrequentTrackingService(controller: manualController, nowProvider: { now }).trackingStatus()
        let smartStatus = await IntentFrequentTrackingService(controller: smartController, nowProvider: { now }).trackingStatus()
        let waitingStatus = await IntentFrequentTrackingService(controller: waitingController, nowProvider: { now }).trackingStatus()

        #expect(manualStatus.effectiveMode == .manualFrequentActive)
        #expect(smartStatus.effectiveMode == .smartFrequentActive)
        #expect(waitingStatus.effectiveMode == .smartWaiting)
    }

    @Test("Frequent tracking status covers inactive active unlimited and expired")
    func frequentTrackingStatusCoversCommonStates() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeExpiration = now.addingTimeInterval(7_200)
        let inactive = await IntentFrequentTrackingService(
            controller: FakeFrequentTrackingController(state: frequentTrackingState()),
            nowProvider: { now }
        ).frequentTrackingStatus()
        let activeWithExpiry = await IntentFrequentTrackingService(
            controller: FakeFrequentTrackingController(
                state: frequentTrackingState(
                    manualFrequentTrackingEnabled: true,
                    frequentTrackingExpiresAt: activeExpiration,
                    durationMode: .twoHours
                )
            ),
            nowProvider: { now }
        ).frequentTrackingStatus()
        let activeWithoutExpiry = await IntentFrequentTrackingService(
            controller: FakeFrequentTrackingController(
                state: frequentTrackingState(
                    manualFrequentTrackingEnabled: true,
                    frequentTrackingExpiresAt: nil,
                    durationMode: .unlimited
                )
            ),
            nowProvider: { now }
        ).frequentTrackingStatus()
        let expired = await IntentFrequentTrackingService(
            controller: FakeFrequentTrackingController(
                state: frequentTrackingState(
                    manualFrequentTrackingEnabled: true,
                    frequentTrackingExpiresAt: now.addingTimeInterval(-60),
                    durationMode: .oneHour
                )
            ),
            nowProvider: { now }
        ).frequentTrackingStatus()

        #expect(inactive.active == false)
        #expect(activeWithExpiry.active)
        #expect(activeWithExpiry.expiresAt == activeExpiration)
        #expect(activeWithExpiry.remainingSeconds == 7_200)
        #expect(activeWithoutExpiry.active)
        #expect(activeWithoutExpiry.remainingSeconds == nil)
        #expect(expired.active == false)
        #expect(expired.remainingSeconds == 0)
    }

    @Test("Frequent tracking status reports low battery blocked state")
    func frequentTrackingStatusReportsLowBatteryBlockedState() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let status = await IntentFrequentTrackingService(
            controller: FakeFrequentTrackingController(
                state: frequentTrackingState(
                    smartFrequentTrackingEnabled: true,
                    smartFrequentTrackingRuntimeActive: true,
                    lowBatteryFrequentTrackingDisabled: true
                )
            ),
            nowProvider: { now }
        ).frequentTrackingStatus()

        #expect(status.active == false)
        #expect(status.smartEnabled)
        #expect(status.blockingReason == .lowBatteryDisabled)
        #expect(GetFrequentTrackingStatusIntent.dialogText(for: status).isEmpty == false)
    }

    @Test("Device status includes cached place and stable age")
    func deviceStatusIncludesCachedPlaceAndStableAge() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let timestamp = now.addingTimeInterval(-3_600)
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: timestamp,
                        horizontalAccuracy: 12
                    )
                ],
                placeDescriptions: ["DEVICE-1": "Berlin, Germany"]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(
                location: IntentUserLocation(latitude: 52.50, longitude: 13.40, timestamp: now)
            ),
            nowProvider: { now }
        )

        let status = try await service.deviceStatus(for: "DEVICE-1")

        #expect(status.deviceID == "DEVICE-1")
        #expect(status.displayName == "Steffi")
        #expect(status.timestamp == timestamp)
        #expect(status.ageText == IntentDeviceLocation.ageText(for: timestamp, referenceDate: now))
        #expect(status.horizontalAccuracy == 12)
        #expect(status.coarsePlaceDescription == "Berlin, Germany")
        #expect(status.distanceMeters != nil)
    }

    @Test("Empty DeviceID is rejected for status intents")
    func emptyDeviceIDIsRejectedForStatusIntents() async {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ]
            )
        )

        await expectLocationError(.deviceUnavailable) {
            _ = try await service.deviceStatus(for: "  ")
        }
    }

    @Test("Distance status uses Core Location distance and bearing")
    func distanceStatusUsesCoreLocationDistanceAndBearing() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let userLocation = IntentUserLocation(latitude: 52.52, longitude: 13.405, timestamp: now)
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.52,
                        longitude: 13.505,
                        timestamp: now,
                        horizontalAccuracy: nil
                    )
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(location: userLocation),
            nowProvider: { now }
        )

        let status = try await service.distanceStatus(for: "DEVICE-1")
        let expectedDistance = CLLocation(latitude: 52.52, longitude: 13.405)
            .distance(from: CLLocation(latitude: 52.52, longitude: 13.505))

        #expect(abs((status.distanceMeters ?? 0) - expectedDistance) < 0.5)
        #expect((status.bearingDegrees ?? 0) > 80)
        #expect((status.bearingDegrees ?? 0) < 100)
    }

    @Test("Distance status requires current user location")
    func distanceStatusRequiresCurrentUserLocation() async {
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: Date(),
                        horizontalAccuracy: nil
                    )
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(location: nil)
        )

        await expectLocationError(.userLocationUnavailable) {
            _ = try await service.distanceStatus(for: "DEVICE-1")
        }
    }

    @Test("Saving current place uses current location and rejects stale locations")
    func savingCurrentPlaceUsesCurrentLocationAndRejectsStaleLocations() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let placeStore = MiataruPlaceStore(fileURL: try temporaryFileURL(named: "places.json"), nowProvider: { now })
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true),
                    IntentDeviceRecord(id: "DEVICE-2", name: "Daniel", hasCurrentLocationAccess: true)
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(
                location: IntentUserLocation(latitude: 52.52, longitude: 13.405, timestamp: now)
            ),
            placeStore: placeStore,
            nowProvider: { now }
        )

        let place = try await service.saveCurrentPlace(deviceID: "device-1", name: "  Home  ", radiusMeters: 10)
        _ = try await service.saveCurrentPlace(deviceID: "DEVICE-2", name: "  Home  ", radiusMeters: nil)

        #expect(place.deviceID == "DEVICE-1")
        #expect(place.name == "Home")
        #expect(place.radiusMeters == MiataruPlaceStore.minimumRadiusMeters)
        #expect(try await service.knownPlaces(forDeviceID: "DEVICE-1") == [place])

        let staleService = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(
                location: IntentUserLocation(
                    latitude: 52.52,
                    longitude: 13.405,
                    timestamp: now.addingTimeInterval(-IntentLocationService.maximumCurrentLocationAge - 1)
                )
            ),
            placeStore: MiataruPlaceStore(fileURL: try temporaryFileURL(named: "stale-places.json"), nowProvider: { now }),
            nowProvider: { now }
        )

        await expectLocationError(.currentLocationTooOld) {
            _ = try await staleService.saveCurrentPlace(deviceID: "DEVICE-1", name: "Stale", radiusMeters: nil)
        }
    }

    @Test("Proximity checks include horizontal accuracy allowance")
    func proximityChecksIncludeHorizontalAccuracyAllowance() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let placeStore = MiataruPlaceStore(fileURL: try temporaryFileURL(named: "proximity-places.json"), nowProvider: { now })
        let place = try await placeStore.savePlace(deviceID: "DEVICE-1", name: "Home", latitude: 52.52, longitude: 13.405, radiusMeters: 50)
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.5209,
                        longitude: 13.405,
                        timestamp: now,
                        horizontalAccuracy: 60
                    )
                ]
            ),
            placeStore: placeStore,
            nowProvider: { now }
        )

        let status = try await service.isDeviceNearPlace(deviceID: "DEVICE-1", placeID: place.id)

        #expect(status.isNear)
        #expect(status.placeName == "Home")
        #expect(status.radiusMeters == 50)
        #expect(status.horizontalAccuracy == 60)
        #expect(status.distanceMeters > 50)
    }

    @Test("Devices near place excludes hidden devices")
    func devicesNearPlaceExcludesHiddenDevices() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let placeStore = MiataruPlaceStore(fileURL: try temporaryFileURL(named: "visible-places.json"), nowProvider: { now })
        let place = try await placeStore.savePlace(deviceID: "VISIBLE-1", name: "Hotel", latitude: 52.52, longitude: 13.405, radiusMeters: 150)
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "VISIBLE-1", name: "Daniel", hasCurrentLocationAccess: true),
                    IntentDeviceRecord(id: "HIDDEN-1", name: "Hidden", hasCurrentLocationAccess: false)
                ],
                payloads: [
                    "VISIBLE-1": IntentLocationPayload(
                        deviceID: "VISIBLE-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: now,
                        horizontalAccuracy: nil
                    ),
                    "HIDDEN-1": IntentLocationPayload(
                        deviceID: "HIDDEN-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: now,
                        horizontalAccuracy: nil
                    )
                ]
            ),
            placeStore: placeStore,
            nowProvider: { now }
        )

        let statuses = try await service.devicesNearPlace(placeID: place.id)

        #expect(statuses.map(\.displayName) == ["Daniel"])
    }

    @Test("ETA status uses injected route provider and transport mode")
    func etaStatusUsesInjectedRouteProviderAndTransportMode() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let routeProvider = FakeRouteProvider(
            result: .success(IntentRouteStatus(expectedTravelTimeSeconds: 900, distanceMeters: 5_000))
        )
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: now,
                        horizontalAccuracy: nil
                    )
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(
                location: IntentUserLocation(latitude: 52.50, longitude: 13.40, timestamp: now)
            ),
            routeProvider: routeProvider,
            navigationSettingsProvider: FakeNavigationSettingsProvider(mode: .walking),
            nowProvider: { now }
        )

        let status = try await service.etaStatus(for: "DEVICE-1")

        #expect(status.expectedTravelTimeSeconds == 900)
        #expect(status.distanceMeters == 5_000)
        #expect(status.transportMode == .walking)
        #expect(routeProvider.requests.count == 1)
        #expect(routeProvider.requests.first?.transportMode == .walking)
    }

    @Test("ETA failure returns localized error without route details")
    func etaFailureReturnsLocalizedErrorWithoutRouteDetails() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let service = IntentLocationService(
            provider: FakeIntentLocationProvider(
                records: [
                    IntentDeviceRecord(id: "DEVICE-1", name: "Steffi", hasCurrentLocationAccess: true)
                ],
                payloads: [
                    "DEVICE-1": IntentLocationPayload(
                        deviceID: "DEVICE-1",
                        latitude: 52.52,
                        longitude: 13.405,
                        timestamp: now,
                        horizontalAccuracy: nil
                    )
                ]
            ),
            currentLocationProvider: FakeCurrentLocationProvider(
                location: IntentUserLocation(latitude: 52.50, longitude: 13.40, timestamp: now)
            ),
            routeProvider: FakeRouteProvider(result: .failure(IntentLocationError.etaUnavailable)),
            nowProvider: { now }
        )

        await expectLocationError(.etaUnavailable) {
            _ = try await service.etaStatus(for: "DEVICE-1")
        }
        let message = IntentLocationError.etaUnavailable.errorDescription ?? ""
        #expect(message.contains("MKDirections") == false)
        #expect(message.contains("52.52") == false)
    }

    @Test("Status dialogs do not leak device identifiers or raw coordinates")
    func statusDialogsDoNotLeakSensitiveIdentifiers() {
        let deviceStatus = IntentDeviceStatus(
            deviceID: "SECRET-DEVICE-ID",
            displayName: "SECRET-DEVICE-ID",
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            ageText: "one minute",
            horizontalAccuracy: 12,
            coarsePlaceDescription: "Berlin",
            distanceMeters: 1_200,
            bearingDegrees: 90
        )
        let etaStatus = IntentETAStatus(
            deviceStatus: deviceStatus,
            expectedTravelTimeSeconds: 900,
            distanceMeters: 1_200,
            transportMode: .automobile
        )

        let dialogs = [
            GetDeviceStatusIntent.dialogText(for: deviceStatus),
            GetDistanceToDeviceIntent.dialogText(for: deviceStatus),
            GetETAForDeviceIntent.dialogText(for: etaStatus)
        ]

        for dialog in dialogs {
            #expect(dialog.contains("SECRET-DEVICE-ID") == false)
            #expect(dialog.contains("52.") == false)
            #expect(dialog.contains("13.") == false)
            #expect(dialog.contains("MiataruAPI") == false)
        }
    }

    @Test("Place intent dialogs and JSON do not leak identifiers or raw coordinates")
    func placeIntentDialogsAndJSONDoNotLeakIdentifiersOrRawCoordinates() {
        let place = MiataruPlaceEntity(id: UUID(), deviceID: "SECRET-DEVICE-ID", name: "Home", radiusMeters: 150)
        let status = IntentPlaceProximityStatus(
            deviceID: "SECRET-DEVICE-ID",
            displayName: "SECRET-DEVICE-ID",
            placeID: place.id,
            placeName: place.name,
            radiusMeters: place.radiusMeters,
            distanceMeters: 42,
            horizontalAccuracy: 12,
            isNear: true
        )

        let texts = [
            SaveCurrentPlaceIntent.dialogText(for: place),
            ListPlacesIntent.dialogText(for: [place]),
            IsDeviceNearPlaceIntent.dialogText(for: status),
            FindDevicesNearPlaceIntent.dialogText(for: [status], placeName: place.name),
            MiataruPlaceIntentFormatting.jsonString(for: [status])
        ]

        for text in texts {
            #expect(text.contains("SECRET-DEVICE-ID") == false)
            #expect(text.contains("52.") == false)
            #expect(text.contains("13.") == false)
            #expect(text.contains("DeviceKey") == false)
            #expect(text.contains("miataruServerURL") == false)
        }
    }

    @Test("App Intent and shortcut localization keys exist for all app locales")
    func appIntentLocalizationKeysExistForAllAppLocales() throws {
        let localizableData = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/miataru/Assets/Localization/Localizable.xcstrings"))
        let localizableJSON = try JSONSerialization.jsonObject(with: localizableData) as? [String: Any]
        let localizableStrings = try #require(localizableJSON?["strings"] as? [String: Any])
        let appShortcutsData = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/miataru/Assets/Localization/AppShortcuts.xcstrings"))
        let appShortcutsJSON = try JSONSerialization.jsonObject(with: appShortcutsData) as? [String: Any]
        let appShortcutsStrings = try #require(appShortcutsJSON?["strings"] as? [String: Any])
        let appIntentsData = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/miataru/Assets/Localization/AppIntents.xcstrings"))
        let appIntentsJSON = try JSONSerialization.jsonObject(with: appIntentsData) as? [String: Any]
        let appIntentsStrings = try #require(appIntentsJSON?["strings"] as? [String: Any])
        let locales = ["da", "de", "en", "es", "fi", "fr", "it", "ja", "nl", "zh-Hans"]
        let appIntentExtractionKeys = [
            "Get latest Miataru event",
            "List recent Miataru events",
            "Clear Miataru events",
            "Export Miataru events",
            "Get Miataru tracking status",
            "Get frequent tracking status",
            "Get status for ${device}",
            "Get distance to ${device}",
            "Get latest location request from ${device}",
            "Get ETA to ${device}",
            "Open Maps route to ${device}",
            "Open Miataru navigation to ${device}",
            "Show location of ${device}",
            "Save ${name} as a Miataru place for ${device}",
            "List saved Miataru places for ${device}",
            "Check whether ${device} is near ${place}",
            "Find devices near ${place}",
            "Start frequent tracking for ${duration}",
            "Stop frequent tracking"
        ]
        let appShortcutPhraseGroups = [
            [
                "Find a device in ${applicationName}",
                "Show a Miataru location in ${applicationName}"
            ],
            [
                "Open a Maps route in ${applicationName}",
                "Route in Maps with ${applicationName}"
            ],
            [
                "Start Miataru navigation in ${applicationName}",
                "Navigate in Miataru with ${applicationName}"
            ],
            [
                "Start frequent tracking in ${applicationName}",
                "Enable frequent tracking in ${applicationName}"
            ],
            [
                "Stop frequent tracking in ${applicationName}",
                "Disable frequent tracking in ${applicationName}"
            ],
            [
                "Check tracking status in ${applicationName}",
                "Is Miataru tracking active in ${applicationName}"
            ],
            [
                "Check frequent tracking in ${applicationName}",
                "How long is frequent tracking active in ${applicationName}"
            ],
            [
                "Check a device status in ${applicationName}",
                "How old is a Miataru location in ${applicationName}"
            ],
            [
                "Check distance to a device in ${applicationName}",
                "How far away is a Miataru device in ${applicationName}"
            ],
            [
                "When did a device last request my location in ${applicationName}",
                "Check a location request in ${applicationName}"
            ]
        ]
        let appShortcutPhraseKeys = appShortcutPhraseGroups.flatMap { $0 }
        let appShortcutCatalogKeys = appShortcutPhraseGroups.compactMap(\.first)
        let appShortcutTitleKeys = [
            "intent_find_device_shortcut_title",
            "intent_open_route_to_device_shortcut_title",
            "intent_open_miataru_navigation_to_device_shortcut_title",
            "intent_start_frequent_tracking_shortcut_title",
            "intent_stop_frequent_tracking_shortcut_title",
            "intent_get_tracking_status_shortcut_title",
            "intent_get_frequent_tracking_status_shortcut_title",
            "intent_get_device_status_shortcut_title",
            "intent_get_distance_to_device_shortcut_title",
            "intent_get_latest_location_request_shortcut_title"
        ]
        let intentKeys = appIntentsStrings.keys.filter { $0.hasPrefix("intent_") }.sorted()

        #expect(!intentKeys.isEmpty)
        #expect(!appShortcutPhraseKeys.isEmpty)
        #expect(
            appShortcutPhraseKeys.allSatisfy { localizableStrings[$0] == nil },
            "App Shortcut phrase keys belong in AppShortcuts.xcstrings, not Localizable.xcstrings"
        )
        #expect(
            Set(appShortcutsStrings.keys) == Set(appShortcutCatalogKeys),
            "AppShortcuts.xcstrings should use one top-level key per shortcut and keep alternates in stringSet.values"
        )
        #expect(
            appShortcutTitleKeys.allSatisfy { appIntentsStrings[$0] != nil },
            "App Shortcut tile titles belong in AppIntents.xcstrings so AppShortcuts.xcstrings remains phrase-only"
        )
        #expect(
            appShortcutPhraseGroups.allSatisfy { group in
                group.dropFirst().allSatisfy { appShortcutsStrings[$0] == nil }
            },
            "Alternate App Shortcut phrases belong in stringSet.values, not as top-level keys"
        )

        var missingEntries: [String] = []
        var staleEntries: [String] = []
        var newUnits: [String] = []
        var englishFallbacks: [String] = []
        var placeholderMismatches: [String] = []

        func placeholders(in value: String) -> [String] {
            let regex = try! NSRegularExpression(pattern: #"%[@df]|\$\{[^}]+\}"#)
            return regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
                guard let range = Range(match.range, in: value) else {
                    return nil
                }
                return String(value[range])
            }
        }

        func validateStringUnits(keys: [String], in strings: [String: Any], catalogName: String) {
            for key in keys {
                guard let entry = strings[key] as? [String: Any],
                      let localizations = entry["localizations"] as? [String: Any] else {
                    missingEntries.append("\(catalogName):\(key):all")
                    continue
                }
                if entry["extractionState"] as? String == "stale" {
                    staleEntries.append("\(catalogName):\(key)")
                }
                guard let englishEntry = localizations["en"] as? [String: Any],
                      let englishStringUnit = englishEntry["stringUnit"] as? [String: Any],
                      let englishValue = englishStringUnit["value"] as? String else {
                    missingEntries.append("\(catalogName):\(key):en")
                    continue
                }
                let englishPlaceholders = placeholders(in: englishValue)

                for locale in locales {
                    guard let localeEntry = localizations[locale] as? [String: Any],
                          let stringUnit = localeEntry["stringUnit"] as? [String: Any],
                          let value = stringUnit["value"] as? String,
                          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        missingEntries.append("\(catalogName):\(key):\(locale)")
                        continue
                    }
                    if stringUnit["state"] as? String == "new" {
                        newUnits.append("\(catalogName):\(key):\(locale)")
                    }
                    if locale != "en" && value == englishValue {
                        englishFallbacks.append("\(catalogName):\(key):\(locale)")
                    }
                    if placeholders(in: value) != englishPlaceholders {
                        placeholderMismatches.append("\(catalogName):\(key):\(locale)")
                    }
                }
            }
        }

        func validateShortcutStringSets(_ groups: [[String]]) {
            for group in groups {
                guard let key = group.first,
                      let entry = appShortcutsStrings[key] as? [String: Any],
                      let localizations = entry["localizations"] as? [String: Any] else {
                    missingEntries.append("AppShortcuts:\(group.first ?? "<empty>"):all")
                    continue
                }
                if entry["extractionState"] as? String == "stale" {
                    staleEntries.append("AppShortcuts:\(key)")
                }
                guard let englishEntry = localizations["en"] as? [String: Any],
                      let englishStringSet = englishEntry["stringSet"] as? [String: Any],
                      let englishValues = englishStringSet["values"] as? [String] else {
                    missingEntries.append("AppShortcuts:\(key):en")
                    continue
                }

                for locale in locales {
                    guard let localeEntry = localizations[locale] as? [String: Any],
                          let stringSet = localeEntry["stringSet"] as? [String: Any],
                          let values = stringSet["values"] as? [String],
                          values.count == group.count,
                          values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                        missingEntries.append("AppShortcuts:\(key):\(locale)")
                        continue
                    }
                    if stringSet["state"] as? String == "new" {
                        newUnits.append("AppShortcuts:\(key):\(locale)")
                    }
                    if locale == "en" && values != group {
                        missingEntries.append("AppShortcuts:\(key):\(locale):values")
                    }
                    for (index, value) in values.enumerated() {
                        guard index < englishValues.count else {
                            continue
                        }
                        if locale != "en" && value == englishValues[index] {
                            englishFallbacks.append("AppShortcuts:\(key):\(locale):\(index)")
                        }
                        if placeholders(in: value) != placeholders(in: englishValues[index]) {
                            placeholderMismatches.append("AppShortcuts:\(key):\(locale):\(index)")
                        }
                    }
                }
            }
        }

        validateStringUnits(keys: intentKeys, in: appIntentsStrings, catalogName: "AppIntents")
        validateStringUnits(keys: appIntentExtractionKeys, in: localizableStrings, catalogName: "Localizable")
        validateStringUnits(keys: appShortcutTitleKeys, in: appIntentsStrings, catalogName: "AppIntents")
        validateShortcutStringSets(appShortcutPhraseGroups)

        #expect(missingEntries.isEmpty, "Missing App Intent localizations: \(missingEntries)")
        #expect(staleEntries.isEmpty, "Stale App Intent localizations: \(staleEntries)")
        #expect(newUnits.isEmpty, "New App Intent localization units: \(newUnits)")
        #expect(englishFallbacks.isEmpty, "Untranslated English fallback values: \(englishFallbacks)")
        #expect(placeholderMismatches.isEmpty, "Localization placeholder mismatches: \(placeholderMismatches)")
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
        smartFrequentTrackingEnabled: Bool = false,
        smartFrequentTrackingRuntimeActive: Bool = false,
        frequentTrackingExpiresAt: Date? = nil,
        durationMode: FrequentBackgroundLocationUpdateDuration = .fourHours,
        applicationState: UIApplication.State = .background,
        locationTrackingActive: Bool = true,
        lowBatteryFrequentTrackingDisabled: Bool = false
    ) -> IntentFrequentTrackingState {
        IntentFrequentTrackingState(
            locationTrackingEnabled: locationTrackingEnabled,
            deviceKeyAuthBlocked: deviceKeyAuthBlocked,
            authorizationStatus: authorizationStatus,
            manualFrequentTrackingEnabled: manualFrequentTrackingEnabled,
            smartFrequentTrackingEnabled: smartFrequentTrackingEnabled,
            smartFrequentTrackingRuntimeActive: smartFrequentTrackingRuntimeActive,
            frequentTrackingExpiresAt: frequentTrackingExpiresAt,
            durationMode: durationMode,
            applicationState: applicationState,
            locationTrackingActive: locationTrackingActive,
            lowBatteryFrequentTrackingDisabled: lowBatteryFrequentTrackingDisabled
        )
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryFileURL(named fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIntentsPreparationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }
}

private struct FakePlaceIntentService: IntentLocationServicing {
    let places: [MiataruPlaceEntity]

    func suggestedDevices() async throws -> [TrackedDeviceEntity] {
        []
    }

    func device(for id: String) async throws -> TrackedDeviceEntity? {
        nil
    }

    func latestLocation(for deviceID: String) async throws -> IntentDeviceLocation {
        throw IntentLocationError.deviceUnavailable
    }

    func deviceStatus(for deviceID: String) async throws -> IntentDeviceStatus {
        throw IntentLocationError.deviceUnavailable
    }

    func distanceStatus(for deviceID: String) async throws -> IntentDeviceStatus {
        throw IntentLocationError.deviceUnavailable
    }

    func etaStatus(for deviceID: String) async throws -> IntentETAStatus {
        throw IntentLocationError.deviceUnavailable
    }

    func knownPlaces() async throws -> [MiataruPlaceEntity] {
        places
    }

    func knownPlaces(forDeviceID deviceID: String) async throws -> [MiataruPlaceEntity] {
        places.filter {
            TrackedDeviceIntentMetadata.normalizedDeviceID($0.deviceID) ==
            TrackedDeviceIntentMetadata.normalizedDeviceID(deviceID)
        }
    }

    func place(for id: UUID) async throws -> MiataruPlaceEntity? {
        places.first { $0.id == id }
    }

    func saveCurrentPlace(deviceID: String, name: String, radiusMeters: Double?) async throws -> MiataruPlaceEntity {
        throw IntentLocationError.userLocationUnavailable
    }

    func isDeviceNearPlace(deviceID: String, placeID: UUID) async throws -> IntentPlaceProximityStatus {
        throw IntentLocationError.deviceUnavailable
    }

    func devicesNearPlace(placeID: UUID) async throws -> [IntentPlaceProximityStatus] {
        []
    }
}

private actor FakeAutomationEventRecorder: MiataruAutomationEventRecording {
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
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
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

    func startManualFrequentTracking(now: Date, durationMode: FrequentBackgroundLocationUpdateDuration?) async {
        startCallCount += 1
        let effectiveDurationMode = durationMode ?? currentState.durationMode
        currentState = IntentFrequentTrackingState(
            locationTrackingEnabled: currentState.locationTrackingEnabled,
            deviceKeyAuthBlocked: currentState.deviceKeyAuthBlocked,
            authorizationStatus: currentState.authorizationStatus,
            manualFrequentTrackingEnabled: true,
            smartFrequentTrackingEnabled: currentState.smartFrequentTrackingEnabled,
            smartFrequentTrackingRuntimeActive: currentState.smartFrequentTrackingRuntimeActive,
            frequentTrackingExpiresAt: effectiveDurationMode.expirationDate(from: now),
            durationMode: effectiveDurationMode,
            applicationState: currentState.applicationState,
            locationTrackingActive: currentState.locationTrackingActive,
            lowBatteryFrequentTrackingDisabled: currentState.lowBatteryFrequentTrackingDisabled
        )
    }

    func stopManualFrequentTracking() async {
        stopCallCount += 1
        currentState = IntentFrequentTrackingState(
            locationTrackingEnabled: currentState.locationTrackingEnabled,
            deviceKeyAuthBlocked: currentState.deviceKeyAuthBlocked,
            authorizationStatus: currentState.authorizationStatus,
            manualFrequentTrackingEnabled: false,
            smartFrequentTrackingEnabled: currentState.smartFrequentTrackingEnabled,
            smartFrequentTrackingRuntimeActive: currentState.smartFrequentTrackingRuntimeActive,
            frequentTrackingExpiresAt: nil,
            durationMode: currentState.durationMode,
            applicationState: currentState.applicationState,
            locationTrackingActive: currentState.locationTrackingActive,
            lowBatteryFrequentTrackingDisabled: currentState.lowBatteryFrequentTrackingDisabled
        )
    }

    func reconcileTrackingState(reason: String) async {
        reconcileReasons.append(reason)
    }
}

private struct FakeIntentLocationProvider: IntentLocationDataProviding {
    var records: [IntentDeviceRecord] = []
    var payloads: [String: IntentLocationPayload] = [:]
    var placeDescriptions: [String: String] = [:]

    func deviceRecords() async -> [IntentDeviceRecord] {
        records
    }

    func latestLocationPayload(for deviceID: String) async throws -> IntentLocationPayload? {
        payloads[deviceID]
    }

    func cachedPlaceDescription(for deviceID: String) async -> String? {
        placeDescriptions[deviceID]
    }
}

private struct FakeCurrentLocationProvider: IntentCurrentLocationProviding {
    var location: IntentUserLocation?

    func currentUserLocation() async -> IntentUserLocation? {
        location
    }
}

private struct FakeNavigationSettingsProvider: IntentNavigationSettingsProviding {
    var mode: IntentTransportMode = .automobile

    func transportMode() async -> IntentTransportMode {
        mode
    }
}

private final class FakeRouteProvider: IntentRouteProviding, @unchecked Sendable {
    var result: Result<IntentRouteStatus, Error>
    private(set) var requests: [(source: IntentCoordinate, destination: IntentCoordinate, transportMode: IntentTransportMode)] = []

    init(result: Result<IntentRouteStatus, Error>) {
        self.result = result
    }

    func route(
        from source: IntentCoordinate,
        to destination: IntentCoordinate,
        transportMode: IntentTransportMode
    ) async throws -> IntentRouteStatus {
        requests.append((source, destination, transportMode))
        return try result.get()
    }
}
