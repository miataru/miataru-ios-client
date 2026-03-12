/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAppAPI.swift
 * miataru
 *
 * Created by Codex on 04.03.26.
 */

import Foundation
import MiataruAPIClient

enum MiataruAppAPI {
    private static let executor = MiataruRequestExecutor.shared
    static let maxDeviceSloganLength = 40

    static func cleanseDeviceSlogan(_ slogan: String, maxLength: Int = maxDeviceSloganLength) -> String {
        let sanitizedScalars = slogan.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let withoutControlCharacters = String(String.UnicodeScalarView(sanitizedScalars))
        let trimmed = withoutControlCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxLength))
    }

    static func getLocation(
        serverURL: URL,
        forDeviceIDs deviceIDs: [String],
        requestingDeviceID: String? = nil,
        requestingDeviceKey: String? = nil
    ) async throws -> [MiataruLocationData] {
        try await executor.execute(policy: .read, operationName: "getLocation") {
            try await MiataruAPIClient.getLocation(
                serverURL: serverURL,
                forDeviceIDs: deviceIDs,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
        }
    }

    static func getLocationHistory(
        serverURL: URL,
        forDeviceID deviceID: String,
        requestingDeviceID: String,
        requestingDeviceKey: String? = nil,
        amount: Int
    ) async throws -> [MiataruLocationData] {
        try await executor.execute(policy: .read, operationName: "getLocationHistory") {
            try await MiataruAPIClient.getLocationHistory(
                serverURL: serverURL,
                forDeviceID: deviceID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey,
                amount: amount
            )
        }
    }

    static func getVisitorHistory(
        serverURL: URL,
        forDeviceID deviceID: String,
        deviceKey: String? = nil,
        amount: Int
    ) async throws -> [MiataruVisitor] {
        try await executor.execute(policy: .read, operationName: "getVisitorHistory") {
            try await MiataruAPIClient.getVisitorHistory(
                serverURL: serverURL,
                forDeviceID: deviceID,
                deviceKey: deviceKey,
                amount: amount
            )
        }
    }

    static func getVisitorHistoryWithConfig(
        serverURL: URL,
        forDeviceID deviceID: String,
        deviceKey: String? = nil,
        amount: Int?
    ) async throws -> MiataruGetVisitorHistoryResponse {
        try await executor.execute(policy: .read, operationName: "getVisitorHistoryWithConfig") {
            try await MiataruAPIClient.getVisitorHistoryWithConfig(
                serverURL: serverURL,
                forDeviceID: deviceID,
                deviceKey: deviceKey,
                amount: amount
            )
        }
    }

    static func getDeviceSlogan(
        serverURL: URL,
        forDeviceID deviceID: String,
        requestingDeviceID: String,
        requestingDeviceKey: String
    ) async throws -> MiataruDeviceSlogan {
        try await executor.execute(policy: .read, operationName: "getDeviceSlogan") {
            try await MiataruAPIClient.getDeviceSlogan(
                serverURL: serverURL,
                forDeviceID: deviceID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
        }
    }

    static func getDeviceSecurityStatus(
        serverURL: URL,
        forDeviceID deviceID: String,
        requestingDeviceID: String,
        requestingDeviceKey: String
    ) async throws -> MiataruDeviceSecurityStatus {
        try await executor.execute(policy: .read, operationName: "getDeviceSecurityStatus") {
            try await MiataruAPIClient.getDeviceSecurityStatus(
                serverURL: serverURL,
                forDeviceID: deviceID,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
        }
    }

    static func setAllowedDeviceList(
        serverURL: URL,
        deviceID: String,
        deviceKey: String,
        allowedDevices: [MiataruAllowedDevice]
    ) async throws -> MiataruSetAllowedDeviceListResponse {
        try await executor.execute(policy: .write, operationName: "setAllowedDeviceList") {
            try await MiataruAPIClient.setAllowedDeviceList(
                serverURL: serverURL,
                deviceID: deviceID,
                deviceKey: deviceKey,
                allowedDevices: allowedDevices
            )
        }
    }

    static func setDeviceKey(
        serverURL: URL,
        deviceID: String,
        currentDeviceKey: String? = nil,
        newDeviceKey: String
    ) async throws -> MiataruSetDeviceKeyResponse {
        try await executor.execute(policy: .write, operationName: "setDeviceKey") {
            try await MiataruAPIClient.setDeviceKey(
                serverURL: serverURL,
                deviceID: deviceID,
                currentDeviceKey: currentDeviceKey,
                newDeviceKey: newDeviceKey
            )
        }
    }

    static func setDeviceSlogan(
        serverURL: URL,
        deviceID: String,
        deviceKey: String,
        slogan: String
    ) async throws -> MiataruSetDeviceSloganResponse {
        let cleansedSlogan = cleanseDeviceSlogan(slogan)
        return try await executor.execute(policy: .write, operationName: "setDeviceSlogan") {
            try await MiataruAPIClient.setDeviceSlogan(
                serverURL: serverURL,
                deviceID: deviceID,
                deviceKey: deviceKey,
                slogan: cleansedSlogan
            )
        }
    }

    static func updateLocation(
        serverURL: URL,
        locationData: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        retryPolicy: MiataruRetryPolicy = .updateLocation
    ) async throws -> Bool {
        try await executor.execute(policy: retryPolicy, operationName: "updateLocation") {
            try await MiataruAPIClient.updateLocation(
                serverURL: serverURL,
                locationData: locationData,
                enableHistory: enableHistory,
                retentionTime: retentionTime
            )
        }
    }
}
