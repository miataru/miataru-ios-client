import Foundation
import CoreLocation
import UIKit

/// Coordinates the app's interaction with the system's location permission prompts.
///
/// This controller abstracts the logic for requesting location authorization and
/// upgrading from "when in use" to "always" access when tracking is enabled. By
/// moving this logic out of `LocationManager` the responsibilities are clearer and
/// easier to maintain.
final class PermissionController {
    private let locationManager: CLLocationManager
    private let settings: SettingsManager
    private let userDefaults = UserDefaults.standard
    private let alwaysAuthorizationRequestedKey = "miataru_always_authorization_requested"

    init(locationManager: CLLocationManager, settings: SettingsManager) {
        self.locationManager = locationManager
        self.settings = settings
    }

    private var hasRequestedAlwaysAuthorization: Bool {
        get { userDefaults.bool(forKey: alwaysAuthorizationRequestedKey) }
        set { userDefaults.set(newValue, forKey: alwaysAuthorizationRequestedKey) }
    }

    /// Requests location permission from the user depending on the current status.
    ///
    /// - If the status is `.notDetermined`, the user is prompted for *when in use*
    ///   access.
    /// - If already authorized for *when in use*, the controller escalates to
    ///   request *always* access.
    /// - For all other states no action is taken.
    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            // Initial request when the user has not yet made a choice.
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Upgrade to always authorization so background tracking works.
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    /// Ensures the proper authorization level is granted when tracking is enabled.
    ///
    /// When the app is configured to track and report location, this method checks
    /// the current authorization status and requests additional permissions if
    /// required. It also remembers whether the escalation to "always" has already
    /// been attempted to avoid nagging the user repeatedly.
    func ensureAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        if settings.trackAndReportLocation {
            switch status {
            case .notDetermined:
                // Ask for when‑in‑use permission on first run.
                locationManager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse:
                // Escalate to always authorization once, when tracking is enabled.
                if !hasRequestedAlwaysAuthorization {
                    hasRequestedAlwaysAuthorization = true
                    locationManager.requestAlwaysAuthorization()
                }
            default:
                break
            }
        }
    }

    /// Handles authorization status changes coming from `CLLocationManager`.
    ///
    /// If the app is actively tracking and the user has only granted *when in use*
    /// permission, this method escalates the request to *always* authorization.
    /// This ensures the app can continue to track in the background without
    /// requiring manual intervention elsewhere.
    func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse,
           settings.trackAndReportLocation,
           !hasRequestedAlwaysAuthorization {
            hasRequestedAlwaysAuthorization = true
            locationManager.requestAlwaysAuthorization()
        }
    }
}
