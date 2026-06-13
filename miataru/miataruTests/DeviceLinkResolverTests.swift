/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLinkResolverTests.swift
 * miataruTests
 *
 * Created by Codex on 24.05.26.
 */

import Foundation
import Testing
import UIKit
@testable import miataru

@Suite(.serialized)
@MainActor
struct DeviceLinkResolverTests {
    @Test("Canonical miataru URI parses device ID")
    func canonicalMiataruURIParsesDeviceID() throws {
        let url = try #require(URL(string: "miataru://Device_abc-123"))

        #expect(DeviceLinkResolver.deviceID(from: url) == "Device_abc-123")
    }

    @Test("Path-style miataru URI remains accepted for compatibility")
    func pathStyleMiataruURIParsesDeviceID() throws {
        let url = try #require(URL(string: "miataru:/device_abc-123"))

        #expect(DeviceLinkResolver.deviceID(from: url) == "device_abc-123")
    }

    @Test("Navigation miataru URI parses destination options")
    func navigationMiataruURIParsesDestinationOptions() throws {
        let url = try #require(URL(string: "miataru://Device_abc-123?action=navigate&direction=userToDevice&presentation=focused"))

        #expect(
            DeviceLinkResolver.destination(from: url) == .navigation(
                "Device_abc-123",
                options: DeviceNavigationLaunchOptions(
                    direction: .userToDevice,
                    presentation: .focused
                )
            )
        )
        #expect(DeviceLinkResolver.deviceID(from: url) == "Device_abc-123")
    }

    @Test("Navigation URL generation uses canonical action query")
    func navigationURLGenerationUsesCanonicalActionQuery() throws {
        let url = DeviceLinkResolver.navigationURL(for: "Device_abc-123")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "miataru")
        #expect(components.host == "Device_abc-123")
        #expect(queryItems["action"] == "navigate")
        #expect(queryItems["direction"] == "userToDevice")
        #expect(queryItems["presentation"] == "focused")
    }

    @Test("Wrong URI scheme is ignored")
    func wrongSchemeIsIgnored() throws {
        let url = try #require(URL(string: "https://device_abc-123"))

        #expect(DeviceLinkResolver.deviceID(from: url) == nil)
    }

    @Test("Empty miataru URI is ignored")
    func emptyMiataruURIIsIgnored() throws {
        let url = try #require(URL(string: "miataru://"))

        #expect(DeviceLinkResolver.deviceID(from: url) == nil)
    }

    @Test("Canonical scanner code keeps miataru prefix compatibility")
    func canonicalScannerCodeKeepsPrefixCompatibility() {
        #expect(DeviceLinkResolver.deviceID(fromCanonicalCode: "miataru://Device_abc-123") == "Device_abc-123")
        #expect(DeviceLinkResolver.urlString(for: "CURRENT_DEVICE") == "miataru://CURRENT_DEVICE")
    }

    @Test("Device ID trimming preserves case")
    func deviceIDTrimmingPreservesCase() {
        #expect(DeviceLinkResolver.trimmedDeviceID("  MixedCase-device_123  ") == "MixedCase-device_123")
        #expect(DeviceLinkResolver.normalizedDeviceID("  MixedCase-device_123  ") == "MIXEDCASE-DEVICE_123")
    }

    @Test("Known device resolution is case-insensitive and returns canonical stored ID")
    func knownDeviceResolutionReturnsCanonicalStoredID() {
        let store = KnownDeviceStore.shared
        let canonicalID = "MixedCase-\(UUID().uuidString)"
        store.removeDevice(byID: canonicalID)
        defer { store.removeDevice(byID: canonicalID) }

        let device = KnownDevice(name: "Canonical Device", deviceID: canonicalID, color: UIColor.systemBlue)
        #expect(store.add(device: device))

        #expect(DeviceLinkResolver.canonicalKnownDeviceID(for: " \(canonicalID.uppercased()) ") == canonicalID)
    }

    @Test("Known device store rejects case-insensitive Device ID duplicates")
    func knownDeviceStoreRejectsCaseInsensitiveDeviceIDDuplicates() {
        let store = KnownDeviceStore.shared
        let canonicalID = "MixedCase-\(UUID().uuidString)"
        let lowercaseID = canonicalID.lowercased()
        store.removeDevice(byID: canonicalID)
        store.removeDevice(byID: lowercaseID)
        defer {
            store.removeDevice(byID: canonicalID)
            store.removeDevice(byID: lowercaseID)
        }

        let original = KnownDevice(name: "Original Device", deviceID: canonicalID, color: UIColor.systemBlue)
        let duplicate = KnownDevice(name: "Duplicate Device", deviceID: lowercaseID, color: UIColor.systemRed)

        #expect(store.add(device: original))
        #expect(!store.add(device: duplicate))
        #expect(store.device(matchingDeviceIDCaseInsensitive: lowercaseID)?.DeviceID == canonicalID)
    }

    @Test("Known device store detects case-insensitive name duplicates without blocking")
    func knownDeviceStoreDetectsCaseInsensitiveNameDuplicatesWithoutBlocking() {
        let store = KnownDeviceStore.shared
        let firstID = "NameCaseA-\(UUID().uuidString)"
        let secondID = "NameCaseB-\(UUID().uuidString)"
        store.removeDevice(byID: firstID)
        store.removeDevice(byID: secondID)
        defer {
            store.removeDevice(byID: firstID)
            store.removeDevice(byID: secondID)
        }

        let first = KnownDevice(name: "Family iPhone", deviceID: firstID, color: UIColor.systemBlue)
        let second = KnownDevice(name: "family iphone", deviceID: secondID, color: UIColor.systemGreen)

        #expect(store.add(device: first))
        #expect(store.add(device: second))
        #expect(store.hasCaseInsensitiveNameDuplicate(for: first))
        #expect(store.hasCaseInsensitiveNameDuplicate(for: second))
    }

    @Test("Known device store detects existing case-insensitive Device ID conflicts")
    func knownDeviceStoreDetectsExistingCaseInsensitiveDeviceIDConflicts() {
        let store = KnownDeviceStore.shared
        let originalDevices = store.devices
        let canonicalID = "ExistingCase-\(UUID().uuidString)"
        let lowercaseID = canonicalID.lowercased()
        defer {
            store.devices = originalDevices
        }

        let first = KnownDevice(name: "First Device", deviceID: canonicalID, color: UIColor.systemBlue)
        let second = KnownDevice(name: "Second Device", deviceID: lowercaseID, color: UIColor.systemOrange)
        store.devices = [first, second]

        #expect(store.hasCaseInsensitiveDeviceIDDuplicate(for: first))
        #expect(store.hasCaseInsensitiveDeviceIDDuplicate(for: second))
    }

    @Test("Device link routing opens known devices and adds unknown devices")
    func deviceLinkRoutingOpensKnownAndAddsUnknown() {
        let coordinator = AppNavigationCoordinator.shared
        clearCoordinatorRequests(coordinator)

        let store = KnownDeviceStore.shared
        let canonicalID = "Known-\(UUID().uuidString)"
        store.removeDevice(byID: canonicalID)
        defer {
            store.removeDevice(byID: canonicalID)
            clearCoordinatorRequests(coordinator)
        }

        let device = KnownDevice(name: "Known Device", deviceID: canonicalID, color: UIColor.systemGreen)
        #expect(store.add(device: device))

        coordinator.openDeviceLink(canonicalID.lowercased())
        #expect(coordinator.deviceOpenRequest?.deviceID == canonicalID)
        #expect(coordinator.addDeviceRequest == nil)

        if let request = coordinator.deviceOpenRequest {
            coordinator.consumeDeviceOpenRequest(request)
        }

        let unknownID = "Unknown-\(UUID().uuidString)"
        let lowercaseUnknownID = unknownID.lowercased()
        coordinator.openDeviceLink(lowercaseUnknownID)
        #expect(coordinator.addDeviceRequest?.deviceID == lowercaseUnknownID)
        #expect(coordinator.addDeviceRequest?.source == .general)
    }

    @Test("Navigation device link routing opens known navigation and adds unknown devices")
    func navigationDeviceLinkRoutingOpensKnownNavigationAndAddsUnknown() async throws {
        let coordinator = AppNavigationCoordinator.shared
        clearCoordinatorRequests(coordinator)
        let recorder = DeviceLinkAutomationEventRecorder()
        coordinator.setAutomationEventRecorderForTesting(recorder)

        let store = KnownDeviceStore.shared
        let canonicalID = "KnownNav-\(UUID().uuidString)"
        store.removeDevice(byID: canonicalID)
        defer {
            store.removeDevice(byID: canonicalID)
            clearCoordinatorRequests(coordinator)
            coordinator.setAutomationEventRecorderForTesting(MiataruAutomationEventRecorder.shared)
        }

        let device = KnownDevice(name: "Known Navigation Device", deviceID: canonicalID, color: UIColor.systemGreen)
        #expect(store.add(device: device))

        coordinator.openDeviceLink(.navigation(canonicalID.lowercased(), options: .defaultDeepLink))
        #expect(coordinator.deviceNavigationOpenRequest?.deviceID == canonicalID)
        #expect(coordinator.deviceNavigationOpenRequest?.options == .defaultDeepLink)
        #expect(coordinator.deviceOpenRequest == nil)
        #expect(coordinator.addDeviceRequest == nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        let events = await recorder.recordedEvents()
        #expect(events.map(\.kind) == [.navigationStarted])
        #expect(events.first?.deviceID == canonicalID)
        #expect(events.first?.deviceDisplayName == "Known Navigation Device")
        #expect(events.first?.payload["direction"] == DeviceNavigationLaunchOptions.defaultDeepLink.direction.rawValue)
        #expect(events.first?.payload["presentation"] == DeviceNavigationLaunchOptions.defaultDeepLink.presentation.rawValue)

        if let request = coordinator.deviceNavigationOpenRequest {
            coordinator.consumeDeviceNavigationOpenRequest(request)
        }

        let unknownID = "UnknownNav-\(UUID().uuidString)"
        let lowercaseUnknownID = unknownID.lowercased()
        coordinator.openDeviceLink(.navigation(lowercaseUnknownID, options: .defaultDeepLink))
        #expect(coordinator.addDeviceRequest?.deviceID == lowercaseUnknownID)
        #expect(coordinator.addDeviceRequest?.source == .general)
        try await Task.sleep(nanoseconds: 50_000_000)
        let eventsAfterUnknownNavigation = await recorder.recordedEvents()
        #expect(eventsAfterUnknownNavigation.count == 1)
    }

    @Test("Unknown visitor add requests preserve source and case")
    func unknownVisitorAddRequestPreservesSourceAndCase() {
        let coordinator = AppNavigationCoordinator.shared
        clearCoordinatorRequests(coordinator)
        defer { clearCoordinatorRequests(coordinator) }

        let unknownID = "Unknown-\(UUID().uuidString)"
        coordinator.openAddDevice(unknownID, source: .unknownVisitor)

        #expect(coordinator.addDeviceRequest?.deviceID == unknownID)
        #expect(coordinator.addDeviceRequest?.source == .unknownVisitor)
    }

    @Test("Unknown visitor notification routes to dialog unless device is now known")
    func unknownVisitorNotificationRoutesByKnownState() {
        let coordinator = AppNavigationCoordinator.shared
        clearCoordinatorRequests(coordinator)

        let unknownID = "Unknown-\(UUID().uuidString)"
        let visitDate = Date(timeIntervalSince1970: 1_775_999_123)
        coordinator.openUnknownVisitorNotificationDevice(unknownID, visitDate: visitDate)
        #expect(coordinator.unknownDeviceActionRequest?.deviceID == unknownID)
        #expect(coordinator.unknownDeviceActionRequest?.visitDate == visitDate)
        #expect(coordinator.deviceOpenRequest == nil)

        clearCoordinatorRequests(coordinator)

        let store = KnownDeviceStore.shared
        let knownID = "Known-\(UUID().uuidString)"
        store.removeDevice(byID: knownID)
        defer {
            store.removeDevice(byID: knownID)
            clearCoordinatorRequests(coordinator)
        }

        let device = KnownDevice(name: "Known Device", deviceID: knownID, color: UIColor.systemOrange)
        #expect(store.add(device: device))

        coordinator.openUnknownVisitorNotificationDevice(knownID.lowercased())
        #expect(coordinator.deviceOpenRequest?.deviceID == knownID)
        #expect(coordinator.unknownDeviceActionRequest == nil)
    }

    private func clearCoordinatorRequests(_ coordinator: AppNavigationCoordinator) {
        if let request = coordinator.deviceOpenRequest {
            coordinator.consumeDeviceOpenRequest(request)
        }
        if let request = coordinator.deviceNavigationOpenRequest {
            coordinator.consumeDeviceNavigationOpenRequest(request)
        }
        if let request = coordinator.addDeviceRequest {
            coordinator.consumeAddDeviceRequest(request)
        }
        if let request = coordinator.unknownDeviceActionRequest {
            coordinator.consumeUnknownDeviceActionRequest(request)
        }
        if let request = coordinator.settingsRequest {
            coordinator.consumeSettingsRequest(request)
        }
        coordinator.consumeRootDestination(.devices)
        coordinator.consumeRootDestination(.settings)
    }
}

private actor DeviceLinkAutomationEventRecorder: MiataruAutomationEventRecording {
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
