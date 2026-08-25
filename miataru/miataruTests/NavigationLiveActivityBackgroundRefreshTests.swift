import Foundation
import CoreLocation
import BackgroundTasks
import Testing
@testable import miataru

@MainActor
@Suite("Navigation Live Activity background refresh tests")
struct NavigationLiveActivityBackgroundRefreshTests {
    @Test("BGAppRefresh fallback runs only without effective frequent updates")
    func schedulingEligibilityExcludesSmartAndManualFrequentUpdates() {
        #expect(!NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: false,
            frequentBackgroundUpdatesActive: false
        ))
        #expect(NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: true,
            frequentBackgroundUpdatesActive: false
        ))
        #expect(!NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: true,
            frequentBackgroundUpdatesActive: true
        ))
    }

    @Test("Smart movement activates frequent mode and suppresses BGAppRefresh fallback")
    func smartMovementActivatesFrequentModeAndSuppressesFallback() {
        #expect(SmartFrequentBackgroundPolicy.shouldActivate(speedKmh: 12, thresholdKmh: 10))
        let effectiveFrequent = LocationTrackingPolicy.effectiveFrequentBackgroundUpdatesEnabled(
            manualFrequentEnabled: false,
            smartEnabled: true,
            smartRuntimeActive: true
        )
        #expect(effectiveFrequent)
        #expect(LocationTrackingPolicy.resolvedTrackingMode(
            isTracking: true,
            authorizationStatus: .authorizedAlways,
            applicationState: .background,
            frequentUpdatesEnabled: effectiveFrequent,
            distanceFilterMeters: 100,
            hasNavigationLocationSession: true
        ) == .backgroundFrequent(
            distanceFilter: 100,
            desiredAccuracy: kCLLocationAccuracyHundredMeters
        ))
        #expect(LocationTrackingPolicy.shouldMaintainFrequentBackgroundActivitySession(
            trackAndReportLocation: true,
            isTracking: true,
            frequentUpdatesEnabled: effectiveFrequent,
            authorizationStatus: .authorizedAlways,
            deviceKeyAuthBlocked: false
        ))
        #expect(!NavigationLiveActivityBackgroundRefreshPolicy.shouldSchedule(
            hasLiveActivity: true,
            frequentBackgroundUpdatesActive: true
        ))
    }

    @Test("Scheduling requests no earlier than the system-friendly minimum")
    func schedulingUsesMinimumInterval() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(NavigationLiveActivityBackgroundRefreshPolicy.earliestBeginDate(
            now: now,
            requestedInterval: 30
        ) == now.addingTimeInterval(15 * 60))
        #expect(NavigationLiveActivityBackgroundRefreshPolicy.earliestBeginDate(
            now: now,
            requestedInterval: 20 * 60
        ) == now.addingTimeInterval(20 * 60))
    }

    @Test("Scheduler submits only while Activity runs without frequent tracking")
    func schedulerReconcilesActivityAndFrequentEligibility() throws {
        let state = SchedulingState()
        let taskScheduler = FakeBackgroundTaskScheduler()
        let now = Date(timeIntervalSince1970: 10_000)
        let scheduler = NavigationLiveActivityBackgroundRefreshScheduler(
            scheduler: taskScheduler,
            notificationCenter: NotificationCenter(),
            hasLiveActivity: { state.hasLiveActivity },
            frequentBackgroundUpdatesActive: { state.frequentActive },
            requestedInterval: { 30 },
            refresh: { true },
            now: { now }
        )

        scheduler.register()
        #expect(taskScheduler.submittedRequests.isEmpty)

        state.hasLiveActivity = true
        scheduler.reconcileScheduling()
        let request = try #require(taskScheduler.submittedRequests.last as? BGAppRefreshTaskRequest)
        #expect(request.identifier == NavigationLiveActivityBackgroundRefreshScheduler.taskIdentifier)
        #expect(request.earliestBeginDate == now.addingTimeInterval(15 * 60))

        state.frequentActive = true
        scheduler.reconcileScheduling()
        #expect(taskScheduler.submittedRequests.count == 1)
        #expect(taskScheduler.cancelledIdentifiers.last == NavigationLiveActivityBackgroundRefreshScheduler.taskIdentifier)
    }

    @Test("Successful background fetch updates route values and source timestamps")
    func successfulRefreshUpdatesRoute() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let own = NavigationLiveActivityBackgroundLocationSample(
            latitude: 49.89,
            longitude: 10.89,
            timestamp: now.addingTimeInterval(-20)
        )
        let remote = NavigationLiveActivityBackgroundLocationSample(
            latitude: 49.90,
            longitude: 10.90,
            timestamp: now.addingTimeInterval(-10)
        )
        let refresher = NavigationLiveActivityBackgroundRefresher(
            fetchRemoteLocation: { _ in remote },
            ownLocation: { own },
            route: { _, _, direction, transport in
                #expect(direction == "userToDevice")
                #expect(transport == "walking")
                return NavigationLiveActivityBackgroundRouteEstimate(
                    distanceMeters: 750,
                    remainingTravelTime: 480
                )
            },
            remoteDescription: { _ in "Bamberg, Germany" },
            now: { now }
        )

        let updated = try #require(await refresher.refresh(snapshot()))
        #expect(updated.distanceMeters == 750)
        #expect(updated.remainingTravelTime == 480)
        #expect(updated.ownLocationTimestamp == own.timestamp)
        #expect(updated.remoteLocationTimestamp == remote.timestamp)
        #expect(updated.lastUpdatedAt == now)
        #expect(updated.remoteLocationDescription == "Bamberg, Germany")
    }

    @Test("Remote success preserves the last route when route calculation fails")
    func routeFailurePreservesLastSuccessfulRoute() async throws {
        let original = snapshot()
        let remoteTimestamp = Date(timeIntervalSince1970: 2_100)
        let refresher = NavigationLiveActivityBackgroundRefresher(
            fetchRemoteLocation: { _ in
                NavigationLiveActivityBackgroundLocationSample(
                    latitude: 49.90,
                    longitude: 10.90,
                    timestamp: remoteTimestamp
                )
            },
            ownLocation: {
                NavigationLiveActivityBackgroundLocationSample(
                    latitude: 49.89,
                    longitude: 10.89,
                    timestamp: Date(timeIntervalSince1970: 2_000)
                )
            },
            route: { _, _, _, _ in throw TestError.routeUnavailable },
            remoteDescription: { _ in nil }
        )

        let updated = try #require(await refresher.refresh(original))
        #expect(updated.distanceMeters == original.distanceMeters)
        #expect(updated.remainingTravelTime == original.remainingTravelTime)
        #expect(updated.lastUpdatedAt == original.lastUpdatedAt)
        #expect(updated.remoteLocationTimestamp == remoteTimestamp)
        #expect(updated.remoteLocationDescription == original.remoteLocationDescription)
    }

    private func snapshot() -> NavigationLiveActivitySnapshot {
        NavigationLiveActivitySnapshot(
            deviceID: "TARGET",
            deviceDisplayName: "Target",
            direction: "userToDevice",
            transportMode: "walking",
            transportSymbolName: "figure.walk",
            distanceMeters: 1_000,
            remainingTravelTime: 600,
            ownLocationTimestamp: Date(timeIntervalSince1970: 1_000),
            remoteLocationTimestamp: Date(timeIntervalSince1970: 1_000),
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            refreshInterval: 30,
            presentationMode: "focused",
            remoteLocationDescription: "Old place",
            maneuverInstruction: "Turn left",
            maneuverSymbolName: "arrow.turn.up.left",
            maneuverDistanceMeters: 100
        )
    }
}

private enum TestError: Error {
    case routeUnavailable
}

@MainActor
private final class SchedulingState {
    var hasLiveActivity = false
    var frequentActive = false
}

@MainActor
private final class FakeBackgroundTaskScheduler: NavigationLiveActivityBackgroundTaskScheduling {
    private(set) var submittedRequests: [BGTaskRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    func register(
        forTaskWithIdentifier identifier: String,
        using queue: DispatchQueue?,
        launchHandler: @escaping (BGTask) -> Void
    ) -> Bool {
        true
    }

    func submit(_ taskRequest: BGTaskRequest) throws {
        submittedRequests.append(taskRequest)
    }

    func cancel(taskRequestWithIdentifier identifier: String) {
        cancelledIdentifiers.append(identifier)
    }
}
