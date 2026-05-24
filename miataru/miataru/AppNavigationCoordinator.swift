/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * AppNavigationCoordinator.swift
 * miataru
 *
 * Created by Codex on 26.04.26.
 */

import Combine
import Foundation

enum AppRootNavigationDestination: Equatable {
    case devices
    case settings
}

enum SettingsNavigationDestination: Equatable {
    case advancedOptions
}

struct SettingsNavigationRequest: Equatable, Identifiable {
    let id = UUID()
    let destination: SettingsNavigationDestination
}

struct DeviceOpenRequest: Equatable, Identifiable {
    let id = UUID()
    let deviceID: String
}

struct AddDeviceRequest: Equatable, Identifiable {
    let id = UUID()
    let deviceID: String
}

struct UnknownDeviceActionRequest: Equatable, Identifiable {
    let id = UUID()
    let deviceID: String
    let visitDate: Date?
}

@MainActor
final class AppNavigationCoordinator: ObservableObject {
    static let shared = AppNavigationCoordinator()

    @Published private(set) var rootDestination: AppRootNavigationDestination?
    @Published private(set) var settingsRequest: SettingsNavigationRequest?
    @Published private(set) var deviceOpenRequest: DeviceOpenRequest?
    @Published private(set) var addDeviceRequest: AddDeviceRequest?
    @Published private(set) var unknownDeviceActionRequest: UnknownDeviceActionRequest?

    private init() {}

    func openDevices() {
        rootDestination = .devices
    }

    func openKnownDevice(_ rawDeviceID: String) {
        guard let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) else { return }
        rootDestination = .devices
        SettingsManager.shared.lastOpenedDeviceID = deviceID
        deviceOpenRequest = DeviceOpenRequest(deviceID: deviceID)
    }

    func openDeviceLink(_ rawDeviceID: String) {
        if let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
            openKnownDevice(deviceID)
        } else if let deviceID = DeviceLinkResolver.normalizedDeviceID(rawDeviceID) {
            openAddDevice(deviceID)
        }
    }

    func openAddDevice(_ rawDeviceID: String) {
        guard let deviceID = DeviceLinkResolver.normalizedDeviceID(rawDeviceID) else { return }
        rootDestination = .devices
        addDeviceRequest = AddDeviceRequest(deviceID: deviceID)
    }

    func openUnknownVisitorNotificationDevice(_ rawDeviceID: String, visitDate: Date? = nil) {
        if let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
            openKnownDevice(deviceID)
        } else {
            presentUnknownDeviceActions(rawDeviceID, visitDate: visitDate)
        }
    }

    func presentUnknownDeviceActions(_ rawDeviceID: String, visitDate: Date? = nil) {
        guard let deviceID = DeviceLinkResolver.normalizedDeviceID(rawDeviceID) else { return }
        rootDestination = .devices
        unknownDeviceActionRequest = UnknownDeviceActionRequest(deviceID: deviceID, visitDate: visitDate)
    }

    func openAdvancedSettings() {
        rootDestination = .settings
        settingsRequest = SettingsNavigationRequest(destination: .advancedOptions)
    }

    func consumeRootDestination(_ destination: AppRootNavigationDestination) {
        guard rootDestination == destination else { return }
        rootDestination = nil
    }

    func consumeSettingsRequest(_ request: SettingsNavigationRequest) {
        guard settingsRequest?.id == request.id else { return }
        settingsRequest = nil
        rootDestination = nil
    }

    func consumeDeviceOpenRequest(_ request: DeviceOpenRequest) {
        guard deviceOpenRequest?.id == request.id else { return }
        deviceOpenRequest = nil
    }

    func consumeAddDeviceRequest(_ request: AddDeviceRequest) {
        guard addDeviceRequest?.id == request.id else { return }
        addDeviceRequest = nil
    }

    func consumeUnknownDeviceActionRequest(_ request: UnknownDeviceActionRequest) {
        guard unknownDeviceActionRequest?.id == request.id else { return }
        unknownDeviceActionRequest = nil
    }
}
