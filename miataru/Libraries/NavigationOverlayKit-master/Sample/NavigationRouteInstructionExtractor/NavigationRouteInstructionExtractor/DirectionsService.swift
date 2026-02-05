import Foundation
import MapKit

enum DirectionsServiceError: Error, LocalizedError {
    case geocodingFailed(details: [String])
    case missingMapItems
    case timeout(seconds: TimeInterval)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .geocodingFailed(let details):
            return "Geocoding failed: " + details.joined(separator: ", ")
        case .missingMapItems:
            return "Source or destination point could not be prepared."
        case .timeout(let seconds):
            return "Timeout after \(Int(seconds))s during route calculation."
        case .noRoute:
            return "No route found."
        }
    }
}

final class DirectionsService {
    // japan route
    private let sourceCoordinate = CLLocationCoordinate2D(latitude: 35.697190, longitude: 139.810837)
    private let destinationCoordinate = CLLocationCoordinate2D(latitude: 35.674747, longitude: 139.751626)

    // germany route
    //private let sourceCoordinate = CLLocationCoordinate2D(latitude: 48.191307, longitude: 11.652738)
    //private let destinationCoordinate = CLLocationCoordinate2D(latitude: 48.129768, longitude: 11.572516)

    
    private var sourceItem: MKMapItem?
    private var destinationItem: MKMapItem?

    func prepareGeocodedItems(preferredLocale: Locale? = nil) async throws {
        if sourceItem != nil && destinationItem != nil { return }

        var warnings: [String] = []

        if sourceItem == nil {
            do {
                sourceItem = try await makeMapItem(coordinate: sourceCoordinate, locale: preferredLocale)
            } catch {
                if #available(iOS 26.0, *) {
                    let location = CLLocation(latitude: sourceCoordinate.latitude, longitude: sourceCoordinate.longitude)
                    sourceItem = MKMapItem(location: location, address: nil)
                } else {
                    sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: sourceCoordinate))
                }
                warnings.append("Source: \(error.localizedDescription)")
            }
        }

        if destinationItem == nil {
            do {
                destinationItem = try await makeMapItem(coordinate: destinationCoordinate, locale: preferredLocale)
            } catch {
                if #available(iOS 26.0, *) {
                    let location = CLLocation(latitude: destinationCoordinate.latitude, longitude: destinationCoordinate.longitude)
                    destinationItem = MKMapItem(location: location, address: nil)
                } else {
                    destinationItem = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoordinate))
                }
                warnings.append("Destination: \(error.localizedDescription)")
            }
        }

        if sourceItem?.name == nil {
            sourceItem?.name = "Source"
        }
        if destinationItem?.name == nil {
            destinationItem?.name = "Destination"
        }

        if !warnings.isEmpty {
            throw DirectionsServiceError.geocodingFailed(details: warnings)
        }
    }

    func fetchRoute(for languageCode: String, timeout: TimeInterval = 20) async throws -> RouteLanguageResult {
        try await prepareGeocodedItems(preferredLocale: Locale(identifier: languageCode))

        guard let sourceItem, let destinationItem else {
            throw DirectionsServiceError.missingMapItems
        }

        let request = MKDirections.Request()
        request.source = sourceItem
        request.destination = destinationItem
        request.transportType = .walking

        let route = try await calculateRoute(with: request, timeout: timeout)
        let steps = route.steps.map { step -> RouteStepDTO in
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let notice = step.notice?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedNotice = notice?.isEmpty == true ? nil : notice
            let candidateStreet = cleanedNotice ?? (instruction.isEmpty ? nil : instruction)

            return RouteStepDTO(
                instruction: instruction,
                distanceMeters: step.distance,
                notice: cleanedNotice,
                streetName: candidateStreet,
                transportType: transportTypeDescription(route.transportType),
                expectedTravelTime: route.expectedTravelTime > 0 ? route.expectedTravelTime : nil,
                polylinePointCount: step.polyline.pointCount
            )
        }

        let preferred = LocaleSwitcher.normalizedIdentifier(Locale.preferredLanguages.first ?? "")
        let requested = LocaleSwitcher.normalizedIdentifier(languageCode)
        let matchesLanguage = !preferred.isEmpty && (preferred.hasPrefix(requested) || requested.hasPrefix(preferred))
        let languageSuspect = steps.isEmpty || !matchesLanguage

        return RouteLanguageResult(languageCode: languageCode, languageSuspect: languageSuspect, steps: steps)
    }

    // Unified helper that uses modern APIs on iOS 26+ and legacy on older iOS
    private func makeMapItem(coordinate: CLLocationCoordinate2D, locale: Locale?) async throws -> MKMapItem {
        if #available(iOS 26.0, *) {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return MKMapItem(location: location, address: nil)
        } else {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKMapItem, Error>) in
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { placemarks, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let placemark = placemarks?.first {
                        let mkPlacemark = MKPlacemark(placemark: placemark)
                        continuation.resume(returning: MKMapItem(placemark: mkPlacemark))
                    } else {
                        let fallbackError = NSError(domain: "DirectionsService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No placemark found"])
                        continuation.resume(throwing: fallbackError)
                    }
                }
            }
        }
    }

    private func calculateRoute(with request: MKDirections.Request, timeout: TimeInterval) async throws -> MKRoute {
        try await withThrowingTaskGroup(of: MKRoute.self) { group in
            let directions = MKDirections(request: request)

            group.addTask {
                let response = try await directions.calculate()
                guard let route = response.routes.first else {
                    throw DirectionsServiceError.noRoute
                }
                return route
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw DirectionsServiceError.timeout(seconds: timeout)
            }

            do {
                guard let result = try await group.next() else {
                    throw DirectionsServiceError.noRoute
                }
                group.cancelAll()
                return result
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func transportTypeDescription(_ transportType: MKDirectionsTransportType) -> String {
        if transportType.contains(.walking) { return "walking" }
        if transportType.contains(.automobile) { return "automobile" }
        if transportType.contains(.transit) { return "transit" }
        if transportType.contains(.any) { return "any" }
        return "unknown"
    }
}
