/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateUploadService.swift
 * miataru
 */

import Foundation
import CoreLocation
import MiataruAPIClient
import UIKit

@MainActor
private final class LocationUploadBackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

final class LocationUpdateUploadService {
    enum SubmissionResult {
        case invalidPayload
        case delivery(LocationUpdateDeliveryCoordinator.SubmitResult)
    }

    private let coordinator: LocationUpdateDeliveryCoordinator

    init(coordinator: LocationUpdateDeliveryCoordinator = .shared) {
        self.coordinator = coordinator
    }

    @MainActor
    func submit(location: CLLocation,
                serverURL: URL,
                deviceID: String,
                deviceKey: String?,
                enableHistory: Bool,
                retentionTime: Int,
                deliveryDelay: TimeInterval?,
                visitorCheckMinimumInterval: TimeInterval?,
                applicationState: UIApplication.State,
                batteryLevel: Float) async -> SubmissionResult {
        guard let payload = Self.payload(
            from: location,
            deviceID: deviceID,
            deviceKey: deviceKey,
            batteryLevel: batteryLevel
        ) else {
            return .invalidPayload
        }

        let backgroundTask = beginBackgroundTaskIfNeeded(for: applicationState)
        defer {
            backgroundTask?.end()
        }

        let result = await coordinator.submit(
            serverURL: serverURL,
            payload: payload,
            enableHistory: enableHistory,
            retentionTime: retentionTime,
            deliveryDelay: deliveryDelay,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval
        )
        return .delivery(result)
    }

    static func payload(from location: CLLocation,
                        deviceID: String,
                        deviceKey: String?,
                        batteryLevel: Float) -> UpdateLocationPayload? {
        let longitude = location.coordinate.longitude
        let latitude = location.coordinate.latitude
        let accuracy = location.horizontalAccuracy
        guard longitude.isFinite, latitude.isFinite, accuracy.isFinite, accuracy >= 0 else {
            return nil
        }

        let altitudeValue: Double? = (location.verticalAccuracy >= 0 && location.altitude.isFinite) ? location.altitude : nil
        let speedValue: Double? = (location.speed >= 0 && location.speed.isFinite) ? location.speed : nil
        let batteryPercent: Double? = (batteryLevel >= 0 && batteryLevel.isFinite) ? Double(Int(batteryLevel * 100)) : nil
        let timestamp = location.timestamp.timeIntervalSince1970
        guard timestamp.isFinite else { return nil }

        return UpdateLocationPayload(
            Device: deviceID,
            DeviceKey: deviceKey,
            Timestamp: String(Int64(timestamp)),
            Longitude: longitude,
            Latitude: latitude,
            HorizontalAccuracy: accuracy,
            Speed: speedValue,
            BatteryLevel: batteryPercent,
            Altitude: altitudeValue
        )
    }

    static func apiErrorDiagnosticCategory(_ error: Error) -> String {
        guard let apiError = error as? MiataruAPIClient.APIError else {
            let nsError = error as NSError
            return "\(nsError.domain)#\(nsError.code)"
        }

        switch apiError {
        case .invalidURL:
            return "invalidURL"
        case .invalidResponse(let response):
            if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                return "invalidResponse#\(statusCode)"
            }
            return "invalidResponse"
        case .encodingError(let underlyingError):
            let nsError = underlyingError as NSError
            return "encodingError#\(nsError.domain)#\(nsError.code)"
        case .decodingError(let underlyingError):
            let nsError = underlyingError as NSError
            return "decodingError#\(nsError.domain)#\(nsError.code)"
        case .requestFailed(let underlyingError):
            let nsError = underlyingError as NSError
            return "requestFailed#\(nsError.domain)#\(nsError.code)"
        case .serverError(let statusCode, _):
            return "serverError#\(statusCode)"
        }
    }

    @MainActor
    private func beginBackgroundTaskIfNeeded(for applicationState: UIApplication.State) -> LocationUploadBackgroundTaskToken? {
        guard applicationState != .active else { return nil }
        return LocationUploadBackgroundTaskToken(name: "MiataruLocationUpdate")
    }
}
