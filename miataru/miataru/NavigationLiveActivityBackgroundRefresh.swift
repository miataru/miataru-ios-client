/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationLiveActivityBackgroundRefresh.swift
 * miataru
 */

import BackgroundTasks
import CoreLocation
import Foundation
import MapKit

struct NavigationLiveActivityBackgroundLocationSample: Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct NavigationLiveActivityBackgroundRouteEstimate: Equatable {
    let distanceMeters: Double
    let remainingTravelTime: TimeInterval
}

@MainActor
final class NavigationLiveActivityBackgroundRefresher {
    typealias RemoteLocationFetcher = (String) async throws -> NavigationLiveActivityBackgroundLocationSample?
    typealias OwnLocationProvider = () -> NavigationLiveActivityBackgroundLocationSample?
    typealias RouteProvider = (
        NavigationLiveActivityBackgroundLocationSample,
        NavigationLiveActivityBackgroundLocationSample,
        String,
        String
    ) async throws -> NavigationLiveActivityBackgroundRouteEstimate
    typealias RemoteDescriptionProvider = (String) -> String?

    static let shared = NavigationLiveActivityBackgroundRefresher(
        fetchRemoteLocation: { deviceID in
            guard let serverURL = URL(string: SettingsManager.shared.miataruServerURL) else { return nil }
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: [deviceID],
                requestingDeviceID: thisDeviceIDManager.shared.deviceID,
                requestingDeviceKey: SettingsManager.shared.deviceKey
            )
            guard let location = locations.first else { return nil }
            return NavigationLiveActivityBackgroundLocationSample(
                latitude: location.Latitude,
                longitude: location.Longitude,
                timestamp: location.TimestampDate
            )
        },
        ownLocation: {
            guard let cached = DeviceLocationCacheStore.shared.getLocation(
                for: thisDeviceIDManager.shared.deviceID
            ) else { return nil }
            return NavigationLiveActivityBackgroundLocationSample(
                latitude: cached.latitude,
                longitude: cached.longitude,
                timestamp: cached.timestamp
            )
        },
        route: { own, remote, direction, transportMode in
            guard RouteRequestCounter.shared.canRequestAndIncrement(limit: 17_000) else {
                throw NavigationLiveActivityBackgroundRefreshError.routeUnavailable
            }
            let request = MKDirections.Request()
            let ownItem = MKMapItem(placemark: MKPlacemark(coordinate: own.coordinate))
            let remoteItem = MKMapItem(placemark: MKPlacemark(coordinate: remote.coordinate))
            if direction == DeviceNavigationRouteDirection.deviceToUser.rawValue {
                request.source = remoteItem
                request.destination = ownItem
            } else {
                request.source = ownItem
                request.destination = remoteItem
            }
            switch transportMode {
            case IntentTransportMode.walking.rawValue:
                request.transportType = .walking
            case IntentTransportMode.transit.rawValue:
                request.transportType = .transit
            default:
                request.transportType = .automobile
            }
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                throw NavigationLiveActivityBackgroundRefreshError.routeUnavailable
            }
            return NavigationLiveActivityBackgroundRouteEstimate(
                distanceMeters: route.distance,
                remainingTravelTime: route.expectedTravelTime
            )
        },
        remoteDescription: { deviceID in
            guard let cached = DeviceLocationCacheStore.shared.getLocation(for: deviceID) else { return nil }
            return NavigationLiveActivityBackgroundRefresher.locationDescription(
                locality: cached.locality,
                country: cached.country
            )
        }
    )

    private let fetchRemoteLocation: RemoteLocationFetcher
    private let ownLocation: OwnLocationProvider
    private let route: RouteProvider
    private let remoteDescription: RemoteDescriptionProvider
    private let now: () -> Date

    init(
        fetchRemoteLocation: @escaping RemoteLocationFetcher,
        ownLocation: @escaping OwnLocationProvider,
        route: @escaping RouteProvider,
        remoteDescription: @escaping RemoteDescriptionProvider,
        now: @escaping () -> Date = Date.init
    ) {
        self.fetchRemoteLocation = fetchRemoteLocation
        self.ownLocation = ownLocation
        self.route = route
        self.remoteDescription = remoteDescription
        self.now = now
    }

    func refresh(_ snapshot: NavigationLiveActivitySnapshot) async -> NavigationLiveActivitySnapshot? {
        do {
            guard let remote = try await fetchRemoteLocation(snapshot.deviceID) else { return nil }
            let description = remoteDescription(snapshot.deviceID) ?? snapshot.remoteLocationDescription
            guard let own = ownLocation() else {
                return snapshot.replacingBackgroundRefreshValues(
                    remoteLocationTimestamp: remote.timestamp,
                    remoteLocationDescription: description
                )
            }

            do {
                let estimate = try await route(own, remote, snapshot.direction, snapshot.transportMode)
                return snapshot.replacingBackgroundRefreshValues(
                    distanceMeters: estimate.distanceMeters,
                    remainingTravelTime: estimate.remainingTravelTime,
                    ownLocationTimestamp: own.timestamp,
                    remoteLocationTimestamp: remote.timestamp,
                    lastUpdatedAt: now(),
                    remoteLocationDescription: description
                )
            } catch {
                debugLog("[NavigationLiveActivityBackgroundRefresher] Route refresh failed: \(error)")
                return snapshot.replacingBackgroundRefreshValues(
                    ownLocationTimestamp: own.timestamp,
                    remoteLocationTimestamp: remote.timestamp,
                    remoteLocationDescription: description
                )
            }
        } catch {
            debugLog("[NavigationLiveActivityBackgroundRefresher] Remote location refresh failed: \(error)")
            return nil
        }
    }

    private static func locationDescription(locality: String?, country: String?) -> String? {
        let locality = locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = country?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validLocality = locality.flatMap { $0.isEmpty ? nil : $0 }
        let validCountry = country.flatMap { $0.isEmpty ? nil : $0 }
        switch (validLocality, validCountry) {
        case let (locality?, country?) where locality.caseInsensitiveCompare(country) != .orderedSame:
            return "\(locality), \(country)"
        case let (locality?, _):
            return locality
        case let (_, country?):
            return country
        default:
            return nil
        }
    }
}

private enum NavigationLiveActivityBackgroundRefreshError: Error {
    case routeUnavailable
}

private extension NavigationLiveActivitySnapshot {
    func replacingBackgroundRefreshValues(
        distanceMeters: Double? = nil,
        remainingTravelTime: TimeInterval? = nil,
        ownLocationTimestamp: Date? = nil,
        remoteLocationTimestamp: Date? = nil,
        lastUpdatedAt: Date? = nil,
        remoteLocationDescription: String? = nil
    ) -> NavigationLiveActivitySnapshot {
        NavigationLiveActivitySnapshot(
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            direction: direction,
            transportMode: transportMode,
            transportSymbolName: transportSymbolName,
            distanceMeters: distanceMeters ?? self.distanceMeters,
            remainingTravelTime: remainingTravelTime ?? self.remainingTravelTime,
            ownLocationTimestamp: ownLocationTimestamp ?? self.ownLocationTimestamp,
            remoteLocationTimestamp: remoteLocationTimestamp ?? self.remoteLocationTimestamp,
            lastUpdatedAt: lastUpdatedAt ?? self.lastUpdatedAt,
            refreshInterval: refreshInterval,
            presentationMode: presentationMode,
            remoteLocationDescription: remoteLocationDescription ?? self.remoteLocationDescription,
            maneuverInstruction: maneuverInstruction,
            maneuverSymbolName: maneuverSymbolName,
            maneuverDistanceMeters: maneuverDistanceMeters
        )
    }
}

enum NavigationLiveActivityBackgroundRefreshPolicy {
    static let minimumSchedulingInterval: TimeInterval = 15 * 60

    static func shouldSchedule(hasLiveActivity: Bool, frequentBackgroundUpdatesActive: Bool) -> Bool {
        hasLiveActivity && !frequentBackgroundUpdatesActive
    }

    static func earliestBeginDate(
        now: Date,
        requestedInterval: TimeInterval
    ) -> Date {
        now.addingTimeInterval(max(minimumSchedulingInterval, requestedInterval))
    }
}

@MainActor
protocol NavigationLiveActivityBackgroundTaskScheduling: AnyObject {
    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool
    func submit(_ taskRequest: BGTaskRequest) throws
    func cancel(taskRequestWithIdentifier identifier: String)
}

extension BGTaskScheduler: NavigationLiveActivityBackgroundTaskScheduling {}

@MainActor
final class NavigationLiveActivityBackgroundRefreshScheduler {
    static let taskIdentifier = "com.miataru.ios.navigation-live-activity-refresh"
    static let shared = NavigationLiveActivityBackgroundRefreshScheduler(
        hasLiveActivity: { NavigationLiveActivityCoordinator.shared.hasRunningActivity },
        frequentBackgroundUpdatesActive: {
            LocationManager.shared.frequentBackgroundUpdatesAreEffectivelyActive
        },
        requestedInterval: {
            NavigationLiveActivityCoordinator.shared.currentSnapshot?.refreshInterval ?? 60
        },
        refresh: {
            await NavigationLiveActivityCoordinator.shared.performBestEffortBackgroundRefresh()
        }
    )

    private let scheduler: NavigationLiveActivityBackgroundTaskScheduling
    private let notificationCenter: NotificationCenter
    private let hasLiveActivity: () -> Bool
    private let frequentBackgroundUpdatesActive: () -> Bool
    private let requestedInterval: () -> TimeInterval
    private let refresh: () async -> Bool
    private let now: () -> Date
    private var isRegistered = false
    private var observers: [NSObjectProtocol] = []
    private var activeOperation: Task<Void, Never>?
    private var activeCompletion: ((Bool) -> Void)?

    init(
        scheduler: NavigationLiveActivityBackgroundTaskScheduling = BGTaskScheduler.shared,
        notificationCenter: NotificationCenter = .default,
        hasLiveActivity: @escaping () -> Bool,
        frequentBackgroundUpdatesActive: @escaping () -> Bool,
        requestedInterval: @escaping () -> TimeInterval,
        refresh: @escaping () async -> Bool,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduler = scheduler
        self.notificationCenter = notificationCenter
        self.hasLiveActivity = hasLiveActivity
        self.frequentBackgroundUpdatesActive = frequentBackgroundUpdatesActive
        self.requestedInterval = requestedInterval
        self.refresh = refresh
        self.now = now
    }

    func register() {
        guard !isRegistered else { return }
        isRegistered = scheduler.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handle(appRefreshTask)
            }
        }
        guard isRegistered else {
            debugLog("[NavigationLiveActivityBackgroundRefreshScheduler] BGTask registration failed")
            return
        }
        let names: [Notification.Name] = [
            .navigationLiveActivityStateDidChange,
            .frequentBackgroundTrackingEligibilityDidChange
        ]
        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcileScheduling() }
            }
        }
        reconcileScheduling()
    }

    func reconcileScheduling() {
        guard isRegistered else { return }
        scheduler.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        guard NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: hasLiveActivity(),
            frequentBackgroundUpdatesActive: frequentBackgroundUpdatesActive()
        ) else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = NavigationLiveActivityBackgroundRefreshPolicy.earliestBeginDate(
            now: now(),
            requestedInterval: requestedInterval()
        )
        do {
            try scheduler.submit(request)
            debugLog("[NavigationLiveActivityBackgroundRefreshScheduler] Scheduled best-effort refresh at or after \(String(describing: request.earliestBeginDate))")
        } catch {
            debugLog("[NavigationLiveActivityBackgroundRefreshScheduler] Scheduling failed: \(error)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        guard NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: hasLiveActivity(),
            frequentBackgroundUpdatesActive: frequentBackgroundUpdatesActive()
        ) else {
            scheduler.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            task.setTaskCompleted(success: true)
            return
        }

        reconcileScheduling()
        activeCompletion = { success in task.setTaskCompleted(success: success) }
        let operation = Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await refresh()
            completeActiveTask(success: success)
        }
        activeOperation = operation
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.activeOperation?.cancel()
                self?.completeActiveTask(success: false)
            }
        }
    }

    private func completeActiveTask(success: Bool) {
        guard let completion = activeCompletion else { return }
        activeCompletion = nil
        activeOperation = nil
        completion(success)
    }
}

extension Notification.Name {
    static let navigationLiveActivityStateDidChange = Notification.Name(
        "NavigationLiveActivityStateDidChange"
    )
    static let frequentBackgroundTrackingEligibilityDidChange = Notification.Name(
        "FrequentBackgroundTrackingEligibilityDidChange"
    )
}
