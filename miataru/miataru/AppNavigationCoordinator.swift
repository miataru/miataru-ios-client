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

struct DeviceNavigationOpenRequest: Equatable, Identifiable {
    let id = UUID()
    let deviceID: String
    let options: DeviceNavigationLaunchOptions
}

enum AddDeviceRequestSource: Equatable {
    case general
    case unknownVisitor
}

struct AddDeviceRequest: Equatable, Identifiable {
    let id = UUID()
    let deviceID: String
    let source: AddDeviceRequestSource

    init(deviceID: String, source: AddDeviceRequestSource = .general) {
        self.deviceID = deviceID
        self.source = source
    }
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
    @Published private(set) var deviceNavigationOpenRequest: DeviceNavigationOpenRequest?
    @Published private(set) var addDeviceRequest: AddDeviceRequest?
    @Published private(set) var unknownDeviceActionRequest: UnknownDeviceActionRequest?

    private var automationEventRecorder: any MiataruAutomationEventRecording = MiataruAutomationEventRecorder.shared

    private init() {}

    func openDevices() {
        rootDestination = .devices
    }

    func openKnownDevice(_ rawDeviceID: String) {
        guard let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) else { return }
        rootDestination = .devices
        SettingsManager.shared.lastOpenedDeviceID = deviceID
        deviceNavigationOpenRequest = nil
        deviceOpenRequest = DeviceOpenRequest(deviceID: deviceID)
    }

    func openKnownDeviceNavigation(_ rawDeviceID: String, options: DeviceNavigationLaunchOptions = .defaultDeepLink) {
        guard let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) else { return }
        rootDestination = .devices
        SettingsManager.shared.lastOpenedDeviceID = nil
        deviceOpenRequest = nil
        deviceNavigationOpenRequest = DeviceNavigationOpenRequest(deviceID: deviceID, options: options)
        recordNavigationStarted(deviceID: deviceID, options: options)
    }

    func openDeviceLink(_ rawDeviceID: String) {
        if let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
            openKnownDevice(deviceID)
        } else if let deviceID = DeviceLinkResolver.trimmedDeviceID(rawDeviceID) {
            openAddDevice(deviceID)
        }
    }

    func openDeviceLink(_ destination: DeviceLinkDestination) {
        switch destination {
        case .device(let rawDeviceID):
            openDeviceLink(rawDeviceID)
        case .navigation(let rawDeviceID, let options):
            if let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
                openKnownDeviceNavigation(deviceID, options: options)
            } else if let deviceID = DeviceLinkResolver.trimmedDeviceID(rawDeviceID) {
                openAddDevice(deviceID)
            }
        }
    }

    func openAddDevice(_ rawDeviceID: String, source: AddDeviceRequestSource = .general) {
        guard let deviceID = DeviceLinkResolver.trimmedDeviceID(rawDeviceID) else { return }
        rootDestination = .devices
        deviceOpenRequest = nil
        deviceNavigationOpenRequest = nil
        addDeviceRequest = AddDeviceRequest(deviceID: deviceID, source: source)
    }

    func openUnknownVisitorNotificationDevice(_ rawDeviceID: String, visitDate: Date? = nil) {
        if let deviceID = DeviceLinkResolver.canonicalKnownDeviceID(for: rawDeviceID) {
            openKnownDevice(deviceID)
        } else {
            presentUnknownDeviceActions(rawDeviceID, visitDate: visitDate)
        }
    }

    func presentUnknownDeviceActions(_ rawDeviceID: String, visitDate: Date? = nil) {
        guard let deviceID = DeviceLinkResolver.trimmedDeviceID(rawDeviceID) else { return }
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

    func consumeDeviceNavigationOpenRequest(_ request: DeviceNavigationOpenRequest) {
        guard deviceNavigationOpenRequest?.id == request.id else { return }
        deviceNavigationOpenRequest = nil
    }

    func consumeAddDeviceRequest(_ request: AddDeviceRequest) {
        guard addDeviceRequest?.id == request.id else { return }
        addDeviceRequest = nil
    }

    func consumeUnknownDeviceActionRequest(_ request: UnknownDeviceActionRequest) {
        guard unknownDeviceActionRequest?.id == request.id else { return }
        unknownDeviceActionRequest = nil
    }

    func setAutomationEventRecorderForTesting(_ recorder: any MiataruAutomationEventRecording) {
        automationEventRecorder = recorder
    }

    private func recordNavigationStarted(deviceID: String, options: DeviceNavigationLaunchOptions) {
        let knownDevice = KnownDeviceStore.shared.devices.first { $0.DeviceID == deviceID }
        let deviceDisplayName = TrackedDeviceIntentMetadata.displayName(
            deviceName: knownDevice?.DeviceName ?? "",
            deviceID: deviceID
        )
        let transport = options.transportMode ?? IntentTransportMode.fromNavigationSetting(SettingsManager.shared.navigationTransportType)
        let payload = [
            "direction": options.direction.rawValue,
            "presentation": options.presentation.rawValue,
            "transport": transport.rawValue,
            "reason": "accepted"
        ]
        let recorder = automationEventRecorder
        Task {
            await recorder.record(
                kind: .navigationStarted,
                privacyLevel: .publicSummary,
                deviceID: deviceID,
                deviceDisplayName: deviceDisplayName,
                placeID: nil,
                placeName: nil,
                payload: payload
            )
        }
    }
}
