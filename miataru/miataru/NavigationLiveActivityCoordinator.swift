/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationLiveActivityCoordinator.swift
 * miataru
 */

import ActivityKit
import Foundation

struct NavigationLiveActivitySnapshot: Codable, Equatable {
    let deviceID: String
    let deviceDisplayName: String
    let direction: String
    let transportMode: String
    let transportSymbolName: String
    let distanceMeters: Double
    let remainingTravelTime: TimeInterval
    let ownLocationTimestamp: Date?
    let remoteLocationTimestamp: Date?
    let lastUpdatedAt: Date
    let refreshInterval: TimeInterval
    let presentationMode: String?
    let remoteLocationDescription: String?
    let maneuverInstruction: String?
    let maneuverSymbolName: String?
    let maneuverDistanceMeters: Double?

    var attributes: NavigationLiveActivityAttributes {
        NavigationLiveActivityAttributes(
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName
        )
    }

    func contentState(now: Date = Date()) -> NavigationLiveActivityAttributes.ContentState {
        let normalizedInterval = max(5, refreshInterval)
        let sourceStaleInterval = max(60, normalizedInterval * 2)
        return NavigationLiveActivityAttributes.ContentState(
            direction: direction,
            transportMode: transportMode,
            transportSymbolName: transportSymbolName,
            distanceMeters: max(0, distanceMeters),
            estimatedArrivalDate: now.addingTimeInterval(max(0, remainingTravelTime)),
            ownLocationTimestamp: ownLocationTimestamp,
            remoteLocationTimestamp: remoteLocationTimestamp,
            lastUpdatedAt: lastUpdatedAt,
            ownLocationIsStale: Self.isStale(ownLocationTimestamp, now: now, interval: sourceStaleInterval),
            remoteLocationIsStale: Self.isStale(remoteLocationTimestamp, now: now, interval: sourceStaleInterval),
            refreshInterval: normalizedInterval,
            presentationMode: presentationMode,
            remoteLocationDescription: Self.normalizedText(remoteLocationDescription),
            maneuverInstruction: Self.normalizedText(maneuverInstruction),
            maneuverSymbolName: Self.normalizedText(maneuverSymbolName),
            maneuverDistanceMeters: maneuverDistanceMeters.map { max(0, $0) }
        )
    }

    func staleDate(now: Date = Date()) -> Date {
        lastUpdatedAt.addingTimeInterval(max(60, max(5, refreshInterval) * 2))
    }

    private static func isStale(_ timestamp: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let timestamp else { return true }
        return now.timeIntervalSince(timestamp) > interval
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(160))
    }
}

struct NavigationLiveActivityPresentation: Equatable {
    let state: NavigationLiveActivityAttributes.ContentState
    let staleDate: Date
}

struct NavigationLiveActivityRecord: Equatable {
    let id: String
    let attributes: NavigationLiveActivityAttributes
}

enum NavigationLiveActivityLifecycleState: Equatable {
    case active
    case inactive
}

@MainActor
protocol NavigationLiveActivityClient: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func activeActivities() -> [NavigationLiveActivityRecord]
    func request(
        attributes: NavigationLiveActivityAttributes,
        presentation: NavigationLiveActivityPresentation
    ) async throws -> String
    func update(id: String, presentation: NavigationLiveActivityPresentation) async -> Bool
    func end(id: String, presentation: NavigationLiveActivityPresentation?) async
    func lifecycleUpdates(id: String) -> AsyncStream<NavigationLiveActivityLifecycleState>
}

@MainActor
final class ActivityKitNavigationLiveActivityClient: NavigationLiveActivityClient {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func activeActivities() -> [NavigationLiveActivityRecord] {
        Activity<NavigationLiveActivityAttributes>.activities.map {
            NavigationLiveActivityRecord(id: $0.id, attributes: $0.attributes)
        }
    }

    func request(
        attributes: NavigationLiveActivityAttributes,
        presentation: NavigationLiveActivityPresentation
    ) async throws -> String {
        let activity = try Activity<NavigationLiveActivityAttributes>.request(
            attributes: attributes,
            content: ActivityContent(state: presentation.state, staleDate: presentation.staleDate),
            pushType: nil
        )
        return activity.id
    }

    func update(id: String, presentation: NavigationLiveActivityPresentation) async -> Bool {
        guard let activity = Activity<NavigationLiveActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return false
        }
        await activity.update(
            ActivityContent(state: presentation.state, staleDate: presentation.staleDate)
        )
        return true
    }

    func end(id: String, presentation: NavigationLiveActivityPresentation?) async {
        guard let activity = Activity<NavigationLiveActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return
        }
        let finalContent = presentation.map {
            ActivityContent(state: $0.state, staleDate: $0.staleDate)
        }
        await activity.end(finalContent, dismissalPolicy: .immediate)
    }

    func lifecycleUpdates(id: String) -> AsyncStream<NavigationLiveActivityLifecycleState> {
        guard let activity = Activity<NavigationLiveActivityAttributes>.activities.first(where: { $0.id == id }) else {
            return AsyncStream { continuation in
                continuation.yield(.inactive)
                continuation.finish()
            }
        }
        return AsyncStream { continuation in
            let observationTask = Task {
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .pending, .active, .stale:
                        continuation.yield(.active)
                    case .ended, .dismissed:
                        continuation.yield(.inactive)
                        continuation.finish()
                        return
                    @unknown default:
                        continuation.yield(.inactive)
                        continuation.finish()
                        return
                    }
                }
            }
            continuation.onTermination = { _ in
                observationTask.cancel()
            }
        }
    }
}

extension Notification.Name {
    static let navigationLiveActivityBackgroundRefreshRequested = Notification.Name(
        "NavigationLiveActivityBackgroundRefreshRequested"
    )
}

@MainActor
final class NavigationLiveActivityCoordinator {
    static let shared = NavigationLiveActivityCoordinator(
        client: ActivityKitNavigationLiveActivityClient(),
        defaults: UserDefaults(suiteName: "group.com.miataru.ios") ?? .standard
    )

    private static let persistedSnapshotKey = "navigationLiveActivitySnapshot"

    private let client: NavigationLiveActivityClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private let backgroundRefresh: (NavigationLiveActivitySnapshot) async -> NavigationLiveActivitySnapshot?

    private(set) var currentSnapshot: NavigationLiveActivitySnapshot?
    private(set) var activityID: String?
    private var lastActivityUpdateAt: Date?
    private var lastPersistedAt: Date?
    private var isStartingActivity = false
    private var activityLifecycleObservationTask: Task<Void, Never>?
    private var activityUnavailableForCurrentNavigation = false
    private var hasLiveViewRegistration = false
    private var sceneIsPreparingForBackground = false
    private var sceneIsBackground = false
    private var activityHasBeenBackgrounded = false

    var hasRunningActivity: Bool {
        activityID != nil && currentSnapshot != nil
    }

    init(
        client: NavigationLiveActivityClient,
        defaults: UserDefaults,
        now: @escaping () -> Date = Date.init,
        backgroundRefresh: @escaping (NavigationLiveActivitySnapshot) async -> NavigationLiveActivitySnapshot? = {
            await NavigationLiveActivityBackgroundRefresher.shared.refresh($0)
        }
    ) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.backgroundRefresh = backgroundRefresh
        currentSnapshot = Self.loadPersistedSnapshot(from: defaults)
    }

    func registerOrUpdate(_ snapshot: NavigationLiveActivitySnapshot) {
        guard snapshot.distanceMeters.isFinite,
              snapshot.remainingTravelTime.isFinite,
              snapshot.refreshInterval.isFinite,
              snapshot.maneuverDistanceMeters?.isFinite != false else {
            return
        }

        hasLiveViewRegistration = true
        let previous = currentSnapshot
        let targetChanged = previous.map { $0.deviceID != snapshot.deviceID } ?? false
        if targetChanged {
            endCurrentActivity(presentationSnapshot: previous)
            activityUnavailableForCurrentNavigation = false
        }

        currentSnapshot = snapshot
        let importantContentChanged = previous.map {
            $0.direction != snapshot.direction ||
            $0.transportMode != snapshot.transportMode ||
            $0.transportSymbolName != snapshot.transportSymbolName ||
            $0.presentationMode != snapshot.presentationMode ||
            $0.remoteLocationDescription != snapshot.remoteLocationDescription ||
            $0.maneuverInstruction != snapshot.maneuverInstruction ||
            $0.maneuverSymbolName != snapshot.maneuverSymbolName
        } ?? true
        persistIfNeeded(snapshot, force: targetChanged || importantContentChanged)

        guard activityID != nil else { return }
        updateActivityIfNeeded(force: importantContentChanged)
    }

    func sceneWillResignActive() {
        guard hasLiveViewRegistration, let currentSnapshot else { return }
        sceneIsPreparingForBackground = true
        persistIfNeeded(currentSnapshot, force: true)
        startActivityIfNeeded()
    }

    func sceneDidEnterBackground() {
        sceneIsPreparingForBackground = false
        sceneIsBackground = true
        guard hasLiveViewRegistration, currentSnapshot != nil else {
            endNavigation()
            return
        }
        activityHasBeenBackgrounded = true
        startActivityIfNeeded()
        NotificationCenter.default.post(name: .navigationLiveActivityBackgroundRefreshRequested, object: nil)
    }

    func sceneDidBecomeActive() {
        sceneIsPreparingForBackground = false
        sceneIsBackground = false
        if activityID != nil, !activityHasBeenBackgrounded {
            endCurrentActivity(presentationSnapshot: currentSnapshot)
            return
        }
        if activityID == nil {
            activityHasBeenBackgrounded = false
        }
        updateActivityIfNeeded(force: true)
    }

    func endNavigation() {
        let snapshot = currentSnapshot
        currentSnapshot = nil
        hasLiveViewRegistration = false
        activityUnavailableForCurrentNavigation = false
        defaults.removeObject(forKey: Self.persistedSnapshotKey)
        endCurrentActivity(presentationSnapshot: snapshot)
    }

    func matchesActiveNavigation(
        deviceID: String,
        direction: String,
        transportMode: String?
    ) -> Bool {
        guard hasLiveViewRegistration,
              let currentSnapshot,
              currentSnapshot.deviceID.caseInsensitiveCompare(deviceID) == .orderedSame,
              currentSnapshot.direction == direction else {
            return false
        }
        return transportMode == nil || currentSnapshot.transportMode == transportMode
    }

    func reconcileAtLaunch() async {
        let records = client.activeActivities()
        guard let snapshot = currentSnapshot,
              let matchingRecord = records.first(where: {
                  $0.attributes.deviceID.caseInsensitiveCompare(snapshot.deviceID) == .orderedSame
              }) else {
            for record in records {
                await client.end(id: record.id, presentation: nil)
            }
            activityID = nil
            currentSnapshot = nil
            defaults.removeObject(forKey: Self.persistedSnapshotKey)
            publishActivityStateChange()
            return
        }

        activityID = matchingRecord.id
        activityHasBeenBackgrounded = true
        publishActivityStateChange()
        observeLifecycle(of: matchingRecord.id)
        for record in records where record.id != matchingRecord.id {
            await client.end(id: record.id, presentation: nil)
        }
        updateActivityIfNeeded(force: true)
    }

    private func startActivityIfNeeded() {
        guard activityID == nil,
              !isStartingActivity,
              hasLiveViewRegistration,
              !activityUnavailableForCurrentNavigation,
              client.areActivitiesEnabled,
              let snapshot = currentSnapshot else {
            return
        }

        isStartingActivity = true
        let requestDate = now()
        let presentation = Self.presentation(for: snapshot, now: requestDate)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isStartingActivity = false }
            do {
                let newActivityID = try await client.request(
                    attributes: snapshot.attributes,
                    presentation: presentation
                )
                guard hasLiveViewRegistration,
                      currentSnapshot?.deviceID == snapshot.deviceID else {
                    await client.end(id: newActivityID, presentation: presentation)
                    return
                }
                guard sceneIsPreparingForBackground || sceneIsBackground || activityHasBeenBackgrounded else {
                    await client.end(id: newActivityID, presentation: presentation)
                    return
                }
                activityID = newActivityID
                lastActivityUpdateAt = requestDate
                publishActivityStateChange()
                observeLifecycle(of: newActivityID)
            } catch {
                debugLog("[NavigationLiveActivityCoordinator] Failed to start Live Activity: \(error)")
            }
        }
    }

    private func updateActivityIfNeeded(force: Bool) {
        guard let activityID,
              let snapshot = currentSnapshot else {
            return
        }
        let updateDate = now()
        let minimumInterval = max(5, snapshot.refreshInterval)
        if !force,
           let lastActivityUpdateAt,
           updateDate.timeIntervalSince(lastActivityUpdateAt) < minimumInterval {
            return
        }

        lastActivityUpdateAt = updateDate
        let presentation = Self.presentation(for: snapshot, now: updateDate)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didUpdate = await client.update(id: activityID, presentation: presentation)
            guard !didUpdate, self.activityID == activityID else { return }
            self.activityID = nil
            self.lastActivityUpdateAt = nil
            self.activityHasBeenBackgrounded = false
            self.activityUnavailableForCurrentNavigation = true
            self.activityLifecycleObservationTask?.cancel()
            self.activityLifecycleObservationTask = nil
            self.publishActivityStateChange()
        }
    }

    func performBestEffortBackgroundRefresh() async -> Bool {
        guard let activityID, let snapshot = currentSnapshot else { return false }
        guard let refreshedSnapshot = await backgroundRefresh(snapshot), !Task.isCancelled else {
            return false
        }
        guard self.activityID == activityID,
              currentSnapshot?.deviceID == snapshot.deviceID else {
            return false
        }

        currentSnapshot = refreshedSnapshot
        persistIfNeeded(refreshedSnapshot, force: true)
        let updateDate = now()
        let didUpdate = await client.update(
            id: activityID,
            presentation: Self.presentation(for: refreshedSnapshot, now: updateDate)
        )
        guard self.activityID == activityID else { return didUpdate }
        if didUpdate {
            lastActivityUpdateAt = updateDate
            return true
        }

        self.activityID = nil
        lastActivityUpdateAt = nil
        activityHasBeenBackgrounded = false
        activityUnavailableForCurrentNavigation = true
        activityLifecycleObservationTask?.cancel()
        activityLifecycleObservationTask = nil
        publishActivityStateChange()
        return false
    }

    private func endCurrentActivity(presentationSnapshot: NavigationLiveActivitySnapshot?) {
        let endedActivityID = activityID
        activityID = nil
        activityLifecycleObservationTask?.cancel()
        activityLifecycleObservationTask = nil
        lastActivityUpdateAt = nil
        activityHasBeenBackgrounded = false
        publishActivityStateChange()

        guard let endedActivityID else { return }
        let endDate = now()
        let presentation = presentationSnapshot.map { Self.presentation(for: $0, now: endDate) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await client.end(id: endedActivityID, presentation: presentation)
        }
    }

    private func observeLifecycle(of observedActivityID: String) {
        activityLifecycleObservationTask?.cancel()
        let updates = client.lifecycleUpdates(id: observedActivityID)
        activityLifecycleObservationTask = Task { @MainActor [weak self] in
            for await state in updates {
                guard let self,
                      state == .inactive,
                      activityID == observedActivityID else {
                    continue
                }
                activityID = nil
                lastActivityUpdateAt = nil
                activityHasBeenBackgrounded = false
                activityUnavailableForCurrentNavigation = true
                activityLifecycleObservationTask = nil
                publishActivityStateChange()
                break
            }
        }
    }

    private func persistIfNeeded(_ snapshot: NavigationLiveActivitySnapshot, force: Bool) {
        let persistenceDate = now()
        if !force,
           let lastPersistedAt,
           persistenceDate.timeIntervalSince(lastPersistedAt) < max(5, snapshot.refreshInterval) {
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.persistedSnapshotKey)
        lastPersistedAt = persistenceDate
    }

    private func publishActivityStateChange() {
        NotificationCenter.default.post(name: .navigationLiveActivityStateDidChange, object: nil)
    }

    private static func loadPersistedSnapshot(from defaults: UserDefaults) -> NavigationLiveActivitySnapshot? {
        guard let data = defaults.data(forKey: persistedSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(NavigationLiveActivitySnapshot.self, from: data)
    }

    private static func presentation(
        for snapshot: NavigationLiveActivitySnapshot,
        now: Date
    ) -> NavigationLiveActivityPresentation {
        NavigationLiveActivityPresentation(
            state: snapshot.contentState(now: now),
            staleDate: snapshot.staleDate(now: now)
        )
    }
}
