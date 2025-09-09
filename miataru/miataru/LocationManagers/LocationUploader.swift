import Foundation
import CoreLocation
import UIKit
import MiataruAPIClient

/// Encapsulates the logic for packaging and uploading location updates to a server.
///
/// The uploader validates network availability and server configuration before
/// constructing a payload to send via `MiataruAPIClient`. It reports progress back
/// to `LocationManager` so the UI can reflect upload state.
final class LocationUploader {
    private unowned let manager: LocationManager
    private let settings: SettingsManager

    /// Designated initializer.
    /// - Parameters:
    ///   - manager: The owning `LocationManager` used for state updates.
    ///   - settings: Application settings used to configure uploads.
    init(manager: LocationManager, settings: SettingsManager) {
        self.manager = manager
        self.settings = settings
    }

    /// Uploads a single location point to the configured Miataru server.
    ///
    /// - Parameter location: The `CLLocation` instance to send.
    ///
    /// The method checks network availability and server configuration before
    /// attempting the upload. It computes additional metadata such as altitude,
    /// speed and battery level, then asynchronously sends the payload. The result is
    /// communicated back through `manager.serverUpdateStatus`.
    @MainActor
    func sendLocationToServer(_ location: CLLocation) {
        guard manager.isNetworkAvailable else {
            // Abort if offline so we don't queue unnecessary work.
            debugLog("No network available, skipping server update.")
            manager.serverUpdateStatus = .failed("No network connection")
            return
        }
        guard !settings.miataruServerURL.isEmpty,
              let serverURL = URL(string: settings.miataruServerURL) else {
            manager.serverUpdateStatus = .failed("Invalid server configuration")
            return
        }
        manager.serverUpdateStatus = .updating

        // Only include altitude, speed and battery information when available.
        let altitudeValue: Double? = (location.verticalAccuracy >= 0) ? location.altitude : -1
        let speedValue: Double? = (location.speed >= 0) ? location.speed : -1
        let batteryLevelRaw = UIDevice.current.batteryLevel
        let batteryPercent: Double? = batteryLevelRaw >= 0 ? Double(Int(batteryLevelRaw * 100)) : -1

        let locationData = UpdateLocationPayload(
            Device: thisDeviceIDManager.shared.deviceID,
            Timestamp: String(Int64(location.timestamp.timeIntervalSince1970)),
            Longitude: location.coordinate.longitude,
            Latitude: location.coordinate.latitude,
            HorizontalAccuracy: location.horizontalAccuracy,
            Speed: speedValue,
            BatteryLevel: batteryPercent,
            Altitude: altitudeValue
        )

        // Perform the network call asynchronously to avoid blocking the main thread.
        Task {
            do {
                let success = try await MiataruAPIClient.updateLocation(
                    serverURL: serverURL,
                    locationData: locationData,
                    enableHistory: settings.saveLocationHistoryOnServer,
                    retentionTime: settings.locationDataRetentionTime
                )
                if success {
                    manager.serverUpdateStatus = .success
                    manager.lastServerUpdate = Date()
                    NotificationCenter.default.post(name: .didSendOwnLocationUpdate, object: nil)
                } else {
                    manager.serverUpdateStatus = .failed("Server response was not successful")
                }
            } catch {
                manager.serverUpdateStatus = .failed(error.localizedDescription)
            }
        }
    }
}
