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
}

enum DeviceKeyAuthHandler {
    static func handle(error: Error) -> String? {
        guard isDeviceKeyAuthError(error) else { return nil }
        let message = deviceKeyAuthMessage(for: error)
        DispatchQueue.main.async {
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
            return NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
        }
        switch apiError {
        case .serverError(_, let message):
            let lowercased = message.lowercased()
            if lowercased.contains("does not match") || lowercased.contains("doesn't match") {
                return NSLocalizedString("device_key_auth_mismatch_message", comment: "Message when stored DeviceKey does not match server")
            }
            return NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
        default:
            return NSLocalizedString("device_key_auth_required_message", comment: "Message when device key authentication is required")
        }
    }
}
