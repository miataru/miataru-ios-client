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
