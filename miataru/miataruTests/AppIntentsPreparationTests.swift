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
        #expect(!url.absoluteString.contains("Steffi"))
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

    @Test("Tracking status reports stopped when normal tracking is off")
    func trackingStatusReportsStoppedWhenTrackingIsOff() async {
        let controller = FakeFrequentTrackingController(
            state: frequentTrackingState(locationTrackingEnabled: false, locationTrackingActive: false)
        )
        let service = IntentFrequentTrackingService(controller: controller)

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
        let service = IntentFrequentTrackingService(controller: controller)

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

    @Test("App Intent localization keys exist for all app locales")
    func appIntentLocalizationKeysExistForAllAppLocales() throws {
        let data = try Data(contentsOf: repoRootURL().appendingPathComponent("miataru/miataru/Assets/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        let locales = ["da", "de", "en", "es", "fi", "fr", "it", "ja", "nl", "zh-Hans"]
        let appIntentExtractionKeys = [
            "Get Miataru tracking status",
            "Get frequent tracking status",
            "Get status for ${device}",
            "Get distance to ${device}",
            "Get ETA to ${device}",
            "Open Apple Maps route to ${device}",
            "Open Miataru navigation to ${device}",
            "Show location of ${device}",
            "Start frequent tracking",
            "Stop frequent tracking"
        ]
        let intentKeys = (
            strings.keys.filter { $0.hasPrefix("intent_") }
                + appIntentExtractionKeys.filter { strings[$0] != nil }
        ).sorted()

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
        smartFrequentTrackingEnabled: Bool = false,
        smartFrequentTrackingRuntimeActive: Bool = false,
        frequentTrackingExpiresAt: Date? = nil,
        durationMode: FrequentBackgroundLocationUpdateDuration = .fourHours,
        applicationState: UIApplication.State = .background,
        locationTrackingActive: Bool = true
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
            locationTrackingActive: locationTrackingActive
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
            smartFrequentTrackingEnabled: currentState.smartFrequentTrackingEnabled,
            smartFrequentTrackingRuntimeActive: currentState.smartFrequentTrackingRuntimeActive,
            frequentTrackingExpiresAt: currentState.durationMode.expirationDate(from: now),
            durationMode: currentState.durationMode,
            applicationState: currentState.applicationState,
            locationTrackingActive: currentState.locationTrackingActive
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
            locationTrackingActive: currentState.locationTrackingActive
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
