import Foundation
import Testing
@testable import miataru

@MainActor
@Suite("Navigation Live Activity coordinator tests")
struct NavigationLiveActivityCoordinatorTests {
    @Test("Live Activity starts once for a registered route and survives foregrounding")
    func startsOnceAndSurvivesForegrounding() async throws {
        let harness = makeHarness()
        harness.coordinator.registerOrUpdate(snapshot(direction: "deviceToUser"))
        #expect(harness.coordinator.matchesActiveNavigation(
            deviceID: "target",
            direction: "deviceToUser",
            transportMode: "automobile"
        ))

        harness.coordinator.sceneWillResignActive()
        await settle()
        #expect(harness.client.requests.count == 1)
        #expect(harness.locationSessions.begun == 1)

        harness.coordinator.sceneDidEnterBackground()
        harness.coordinator.sceneDidBecomeActive()
        harness.coordinator.sceneWillResignActive()
        harness.coordinator.sceneDidEnterBackground()
        await settle()
        #expect(harness.client.requests.count == 1)
        #expect(harness.client.endedIDs.isEmpty)
        #expect(harness.client.updates.count == 1)

        harness.coordinator.endNavigation()
        await settle()
        #expect(harness.client.endedIDs == ["activity-1"])
        #expect(harness.locationSessions.ended == 1)
    }

    @Test("System-ended activity releases its background location session")
    func systemEndedActivityReleasesLocationSession() async {
        let harness = makeHarness()
        harness.coordinator.registerOrUpdate(snapshot())
        harness.coordinator.sceneWillResignActive()
        await settle()
        harness.coordinator.sceneDidEnterBackground()
        harness.client.records = []

        harness.coordinator.sceneDidBecomeActive()
        await settle()
        #expect(harness.coordinator.activityID == nil)
        #expect(harness.locationSessions.ended == 1)
    }

    @Test("Dismissed activity immediately releases background location and is not recreated")
    func dismissedActivityImmediatelyReleasesBackgroundLocation() async {
        let harness = makeHarness()
        harness.coordinator.registerOrUpdate(snapshot())
        harness.coordinator.sceneWillResignActive()
        await settle()
        harness.coordinator.sceneDidEnterBackground()
        #expect(harness.locationSessions.begun == 1)

        harness.client.sendLifecycle(.inactive, for: "activity-1")
        await settle()
        #expect(harness.coordinator.activityID == nil)
        #expect(harness.locationSessions.ended == 1)

        harness.coordinator.sceneDidBecomeActive()
        harness.coordinator.sceneWillResignActive()
        await settle()
        #expect(harness.client.requests.count == 1)
    }

    @Test("Inactive without background removes the prepared Live Activity")
    func inactiveWithoutBackgroundDoesNotLeaveActivityRunning() async {
        let harness = makeHarness()
        harness.coordinator.registerOrUpdate(snapshot())
        harness.coordinator.sceneWillResignActive()
        await settle()
        #expect(harness.client.requests.count == 1)

        harness.coordinator.sceneDidBecomeActive()
        await settle()
        #expect(harness.client.endedIDs == ["activity-1"])
        #expect(harness.coordinator.currentSnapshot != nil)
        #expect(harness.locationSessions.ended == 1)
    }

    @Test("No route and disabled ActivityKit never start a Live Activity")
    func missingRouteAndDisabledActivityKitDoNotStart() async {
        let noRoute = makeHarness()
        noRoute.coordinator.sceneWillResignActive()
        await settle()
        #expect(noRoute.client.requests.isEmpty)

        let disabled = makeHarness(activitiesEnabled: false)
        disabled.coordinator.registerOrUpdate(snapshot(direction: "userToDevice"))
        disabled.coordinator.sceneWillResignActive()
        await settle()
        #expect(disabled.client.requests.isEmpty)
        #expect(disabled.coordinator.currentSnapshot != nil)
    }

    @Test("Direction changes update the existing activity and target changes replace it")
    func directionAndTargetChangesAreReconciled() async {
        let harness = makeHarness()
        harness.coordinator.registerOrUpdate(snapshot(direction: "deviceToUser"))
        harness.coordinator.sceneWillResignActive()
        await settle()

        harness.coordinator.registerOrUpdate(snapshot(direction: "userToDevice"))
        await settle()
        #expect(harness.client.requests.count == 1)
        #expect(harness.client.updates.last?.presentation.state.direction == "userToDevice")

        harness.coordinator.registerOrUpdate(snapshot(deviceID: "OTHER", direction: "userToDevice"))
        await settle()
        #expect(harness.client.endedIDs == ["activity-1"])
        #expect(harness.coordinator.activityID == nil)

        harness.coordinator.sceneWillResignActive()
        await settle()
        #expect(harness.client.requests.count == 2)
        #expect(harness.client.requests.last?.attributes.deviceID == "OTHER")
    }

    @Test("Updates are coalesced to the configured map interval")
    func updatesAreCoalesced() async {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let harness = makeHarness(now: { clock.now })
        harness.coordinator.registerOrUpdate(snapshot(lastUpdatedAt: clock.now, refreshInterval: 30))
        harness.coordinator.sceneWillResignActive()
        await settle()

        clock.now = clock.now.addingTimeInterval(10)
        harness.coordinator.registerOrUpdate(snapshot(distanceMeters: 900, lastUpdatedAt: clock.now, refreshInterval: 30))
        await settle()
        #expect(harness.client.updates.isEmpty)

        clock.now = clock.now.addingTimeInterval(20)
        harness.coordinator.registerOrUpdate(snapshot(distanceMeters: 800, lastUpdatedAt: clock.now, refreshInterval: 30))
        await settle()
        #expect(harness.client.updates.count == 1)
        #expect(harness.client.updates[0].presentation.state.distanceMeters == 800)
    }

    @Test("Freshness state and navigation URL preserve route inputs")
    func freshnessAndDeepLinkPreserveInputs() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let source = snapshot(
            direction: "userToDevice",
            transportMode: "walking",
            ownLocationTimestamp: now.addingTimeInterval(-121),
            remoteLocationTimestamp: now,
            lastUpdatedAt: now,
            refreshInterval: 30,
            presentationMode: "focused",
            remoteLocationDescription: "Bamberg, Germany",
            maneuverInstruction: "Turn right onto Hauptstraße",
            maneuverSymbolName: "arrow.turn.up.right",
            maneuverDistanceMeters: 120
        )
        let state = source.contentState(now: now)
        #expect(state.ownLocationIsStale)
        #expect(!state.remoteLocationIsStale)
        #expect(state.isFocusedNavigation)
        #expect(state.remoteLocationDescription == "Bamberg, Germany")
        #expect(state.maneuverInstruction == "Turn right onto Hauptstraße")
        #expect(state.maneuverSymbolName == "arrow.turn.up.right")
        #expect(state.maneuverDistanceMeters == 120)
        #expect(source.staleDate(now: now) == now.addingTimeInterval(60))

        let url = try #require(source.attributes.navigationURL(for: state))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(url.host == "TARGET")
        #expect(components.queryItems?.first(where: { $0.name == "action" })?.value == "navigate")
        #expect(components.queryItems?.first(where: { $0.name == "direction" })?.value == "userToDevice")
        #expect(components.queryItems?.first(where: { $0.name == "presentation" })?.value == "focused")
        #expect(components.queryItems?.first(where: { $0.name == "transport" })?.value == "walking")
    }

    @Test("Maneuver and location context changes update an active activity immediately")
    func contextChangesUpdateImmediately() async {
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_000))
        let harness = makeHarness(now: { clock.now })
        harness.coordinator.registerOrUpdate(snapshot(
            lastUpdatedAt: clock.now,
            refreshInterval: 60,
            presentationMode: "standard",
            remoteLocationDescription: "Bamberg"
        ))
        harness.coordinator.sceneWillResignActive()
        await settle()

        clock.now = clock.now.addingTimeInterval(1)
        harness.coordinator.registerOrUpdate(snapshot(
            direction: "userToDevice",
            lastUpdatedAt: clock.now,
            refreshInterval: 60,
            presentationMode: "focused",
            remoteLocationDescription: "Bamberg",
            maneuverInstruction: "Turn left",
            maneuverSymbolName: "arrow.turn.up.left",
            maneuverDistanceMeters: 80
        ))
        await settle()

        #expect(harness.client.updates.count == 1)
        #expect(harness.client.updates[0].presentation.state.isFocusedNavigation)
        #expect(harness.client.updates[0].presentation.state.maneuverInstruction == "Turn left")
        #expect(harness.client.updates[0].presentation.state.maneuverDistanceMeters == 80)
    }

    @Test("Launch reconciliation binds a matching activity and removes orphans")
    func launchReconciliationBindsAndRemovesOrphans() async {
        let defaults = isolatedDefaults()
        let storedSnapshot = snapshot()
        defaults.set(try? JSONEncoder().encode(storedSnapshot), forKey: "navigationLiveActivitySnapshot")
        let client = FakeNavigationLiveActivityClient()
        client.records = [
            NavigationLiveActivityRecord(id: "matching", attributes: storedSnapshot.attributes),
            NavigationLiveActivityRecord(
                id: "orphan",
                attributes: NavigationLiveActivityAttributes(deviceID: "ORPHAN", deviceDisplayName: "Orphan")
            )
        ]
        let sessions = LocationSessionSpy()
        let coordinator = makeCoordinator(client: client, defaults: defaults, sessions: sessions)

        await coordinator.reconcileAtLaunch()
        await settle()
        #expect(coordinator.activityID == "matching")
        #expect(client.endedIDs == ["orphan"])
        #expect(sessions.begun == 0)
        #expect(!coordinator.requiresHighAccuracyBackgroundLocation)

        coordinator.registerOrUpdate(storedSnapshot)
        coordinator.sceneWillResignActive()
        #expect(sessions.begun == 1)
        #expect(coordinator.requiresHighAccuracyBackgroundLocation)
    }

    @Test("A restored Activity without an open navigation cannot retain background location")
    func restoredActivityWithoutLiveNavigationReleasesBackgroundLocation() async {
        let defaults = isolatedDefaults()
        let storedSnapshot = snapshot()
        defaults.set(try? JSONEncoder().encode(storedSnapshot), forKey: "navigationLiveActivitySnapshot")
        let client = FakeNavigationLiveActivityClient()
        client.records = [NavigationLiveActivityRecord(id: "matching", attributes: storedSnapshot.attributes)]
        let sessions = LocationSessionSpy()
        let coordinator = makeCoordinator(client: client, defaults: defaults, sessions: sessions)

        await coordinator.reconcileAtLaunch()
        coordinator.sceneWillResignActive()
        coordinator.sceneDidEnterBackground()
        await settle()

        #expect(client.endedIDs == ["matching"])
        #expect(coordinator.activityID == nil)
        #expect(coordinator.currentSnapshot == nil)
        #expect(sessions.begun == 0)
        #expect(!coordinator.requiresHighAccuracyBackgroundLocation)
    }

    private func makeHarness(
        activitiesEnabled: Bool = true,
        now: @escaping () -> Date = Date.init
    ) -> TestHarness {
        let client = FakeNavigationLiveActivityClient()
        client.areActivitiesEnabled = activitiesEnabled
        let defaults = isolatedDefaults()
        let sessions = LocationSessionSpy()
        let coordinator = makeCoordinator(
            client: client,
            defaults: defaults,
            sessions: sessions,
            now: now
        )
        return TestHarness(
            coordinator: coordinator,
            client: client,
            locationSessions: sessions
        )
    }

    private func makeCoordinator(
        client: FakeNavigationLiveActivityClient,
        defaults: UserDefaults,
        sessions: LocationSessionSpy,
        now: @escaping () -> Date = Date.init
    ) -> NavigationLiveActivityCoordinator {
        NavigationLiveActivityCoordinator(
            client: client,
            defaults: defaults,
            now: now,
            beginNavigationLocationSession: {
                sessions.begun += 1
                return UUID()
            },
            endNavigationLocationSession: { _ in
                sessions.ended += 1
            }
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "NavigationLiveActivityCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func snapshot(
        deviceID: String = "TARGET",
        direction: String = "deviceToUser",
        transportMode: String = "automobile",
        distanceMeters: Double = 1_000,
        ownLocationTimestamp: Date? = Date(timeIntervalSince1970: 1_000),
        remoteLocationTimestamp: Date? = Date(timeIntervalSince1970: 1_000),
        lastUpdatedAt: Date = Date(timeIntervalSince1970: 1_000),
        refreshInterval: TimeInterval = 30,
        presentationMode: String? = "standard",
        remoteLocationDescription: String? = nil,
        maneuverInstruction: String? = nil,
        maneuverSymbolName: String? = nil,
        maneuverDistanceMeters: Double? = nil
    ) -> NavigationLiveActivitySnapshot {
        NavigationLiveActivitySnapshot(
            deviceID: deviceID,
            deviceDisplayName: "Target",
            direction: direction,
            transportMode: transportMode,
            transportSymbolName: transportMode == "walking" ? "figure.walk" : "car",
            distanceMeters: distanceMeters,
            remainingTravelTime: 600,
            ownLocationTimestamp: ownLocationTimestamp,
            remoteLocationTimestamp: remoteLocationTimestamp,
            lastUpdatedAt: lastUpdatedAt,
            refreshInterval: refreshInterval,
            presentationMode: presentationMode,
            remoteLocationDescription: remoteLocationDescription,
            maneuverInstruction: maneuverInstruction,
            maneuverSymbolName: maneuverSymbolName,
            maneuverDistanceMeters: maneuverDistanceMeters
        )
    }

    private func settle() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private final class FakeNavigationLiveActivityClient: NavigationLiveActivityClient {
    struct Request {
        let attributes: NavigationLiveActivityAttributes
        let presentation: NavigationLiveActivityPresentation
    }

    struct Update {
        let id: String
        let presentation: NavigationLiveActivityPresentation
    }

    var areActivitiesEnabled = true
    var records: [NavigationLiveActivityRecord] = []
    var requests: [Request] = []
    var updates: [Update] = []
    var endedIDs: [String] = []
    private var lifecycleContinuations: [String: AsyncStream<NavigationLiveActivityLifecycleState>.Continuation] = [:]

    func activeActivities() -> [NavigationLiveActivityRecord] {
        records
    }

    func request(
        attributes: NavigationLiveActivityAttributes,
        presentation: NavigationLiveActivityPresentation
    ) async throws -> String {
        requests.append(Request(attributes: attributes, presentation: presentation))
        let id = "activity-\(requests.count)"
        records.append(NavigationLiveActivityRecord(id: id, attributes: attributes))
        return id
    }

    func update(id: String, presentation: NavigationLiveActivityPresentation) async -> Bool {
        updates.append(Update(id: id, presentation: presentation))
        return records.contains { $0.id == id }
    }

    func end(id: String, presentation: NavigationLiveActivityPresentation?) async {
        endedIDs.append(id)
        records.removeAll { $0.id == id }
        lifecycleContinuations.removeValue(forKey: id)?.finish()
    }

    func lifecycleUpdates(id: String) -> AsyncStream<NavigationLiveActivityLifecycleState> {
        AsyncStream { continuation in
            lifecycleContinuations[id] = continuation
            continuation.yield(records.contains { $0.id == id } ? .active : .inactive)
        }
    }

    func sendLifecycle(_ state: NavigationLiveActivityLifecycleState, for id: String) {
        lifecycleContinuations[id]?.yield(state)
        if state == .inactive {
            records.removeAll { $0.id == id }
            lifecycleContinuations.removeValue(forKey: id)?.finish()
        }
    }
}

@MainActor
private final class LocationSessionSpy {
    var begun = 0
    var ended = 0
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private struct TestHarness {
    let coordinator: NavigationLiveActivityCoordinator
    let client: FakeNavigationLiveActivityClient
    let locationSessions: LocationSessionSpy
}
