/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceKeyAuthHandler.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 31.01.26.
 */

import Foundation
import MiataruAPIClient

extension Notification.Name {
    static let deviceKeyAuthRequired = Notification.Name("deviceKeyAuthRequired")
    static let deviceKeyAuthResolved = Notification.Name("deviceKeyAuthResolved")
    static let deviceIdentityDidReset = Notification.Name("deviceIdentityDidReset")
}

enum DeviceKeyAuthHandler {
    static func handle(error: Error) -> String? {
        guard isDeviceKeyAuthError(error) else { return nil }
        let message = deviceKeyAuthMessage(for: error)
        DispatchQueue.main.async {
            let settings = SettingsManager.shared
            if settings.trackAndReportLocation {
                settings.trackAndReportLocationDisabledByDeviceKeyAuth = true
                settings.trackAndReportLocation = false
            }
            settings.deviceKeyAuthBlocked = true
            settings.deviceKeyAuthBlockedKey = settings.deviceKey
            NotificationCenter.default.post(name: .deviceKeyAuthRequired, object: nil, userInfo: ["message": message])
        }
        return message
    }

    private static func isDeviceKeyAuthError(_ error: Error) -> Bool {
        guard let apiError = error as? MiataruAPIClient.APIError else { return false }
        switch apiError {
        case .serverError(let statusCode, let message):
            if statusCode == 401 || statusCode == 403 {
                return true
            }
            let lowercased = message.lowercased()
            return lowercased.contains("devicekey") || lowercased.contains("device key")
        default:
            return false
        }
    }

    private static func deviceKeyAuthMessage(for error: Error) -> String {
        guard let apiError = error as? MiataruAPIClient.APIError else {
            return NSLocalizedString("device_key_auth_runtime_error_message", tableName: "Devices", comment: "Runtime auth error when stored DeviceKey is missing or invalid")
        }
        switch apiError {
        case .serverError(_, let message):
            let lowercased = message.lowercased()
            if lowercased.contains("does not match") || lowercased.contains("doesn't match") {
                return NSLocalizedString("device_key_auth_mismatch_message", tableName: "Devices", comment: "Message when stored DeviceKey does not match server")
            }
            return NSLocalizedString("device_key_auth_runtime_error_message", tableName: "Devices", comment: "Runtime auth error when stored DeviceKey is missing or invalid")
        default:
            return NSLocalizedString("device_key_auth_runtime_error_message", tableName: "Devices", comment: "Runtime auth error when stored DeviceKey is missing or invalid")
        }
    }
}
