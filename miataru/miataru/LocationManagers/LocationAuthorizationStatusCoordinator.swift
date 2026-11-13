/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationAuthorizationStatusCoordinator.swift
 * miataru
 */

import CoreLocation
import Combine
import Foundation

protocol LocationAuthorizationStatusQuerying: AnyObject {
    func start(onStatusChange: @escaping (CLAuthorizationStatus) -> Void)
    func readStatus(completion: @escaping (CLAuthorizationStatus) -> Void)
}

struct LocationAuthorizationStatusSnapshot: Equatable {
    let status: CLAuthorizationStatus
    let isResolved: Bool
}

/// Serializes authorization reads without ever asking a main-thread CLLocationManager
/// for `authorizationStatus`. The coordinator's state is owned by the main thread.
final class LocationAuthorizationStatusCoordinator {
    private let source: LocationAuthorizationStatusQuerying
    @Published private(set) var snapshot = LocationAuthorizationStatusSnapshot(status: .notDetermined, isResolved: false)
    var onChange: ((LocationAuthorizationStatusSnapshot) -> Void)?

    private var hasStarted = false
    private var nextGeneration: UInt64 = 0
    private var inFlightGeneration: UInt64?
    private var refreshPending = false

    init(source: LocationAuthorizationStatusQuerying) {
        self.source = source
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        source.start { [weak self] status in
            self?.deliverToMain { coordinator in
                coordinator.receiveObservedStatus(status)
            }
        }
        requestRefresh()
    }

    func requestRefresh() {
        guard hasStarted else {
            start()
            return
        }
        nextGeneration &+= 1
        refreshPending = true
        startPendingReadIfNeeded()
    }

    /// Intent callers may await the first result without blocking launch or waiting
    /// indefinitely for an unresponsive location daemon. Cancellation ends the wait.
    @MainActor
    func resolvedStatus(timeout: DispatchQueue.SchedulerTimeType.Stride = .seconds(5)) async -> CLAuthorizationStatus? {
        guard !Task.isCancelled else { return nil }
        if snapshot.isResolved { return snapshot.status }
        requestRefresh()
        let resolved = $snapshot
            .filter { $0.isResolved }
            .prefix(1)
            .timeout(timeout, scheduler: DispatchQueue.main)
            .values
        for await _ in resolved {
            guard !Task.isCancelled else { return nil }
            return snapshot.isResolved ? snapshot.status : nil
        }
        return nil
    }

    private func receiveObservedStatus(_ status: CLAuthorizationStatus) {
        nextGeneration &+= 1
        publish(status)
        if inFlightGeneration != nil {
            refreshPending = true
        }
    }

    private func startPendingReadIfNeeded() {
        guard inFlightGeneration == nil, refreshPending else { return }
        refreshPending = false
        let generation = nextGeneration
        inFlightGeneration = generation
        source.readStatus { [weak self] status in
            self?.deliverToMain { coordinator in
                coordinator.finishRead(status, generation: generation)
            }
        }
    }

    private func finishRead(_ status: CLAuthorizationStatus, generation: UInt64) {
        guard inFlightGeneration == generation else { return }
        inFlightGeneration = nil
        if generation == nextGeneration {
            publish(status)
        }
        startPendingReadIfNeeded()
    }

    private func publish(_ status: CLAuthorizationStatus) {
        let next = LocationAuthorizationStatusSnapshot(status: status, isResolved: true)
        guard next != snapshot else { return }
        snapshot = next
        onChange?(next)
    }

    private func deliverToMain(_ operation: @escaping (LocationAuthorizationStatusCoordinator) -> Void) {
        if Thread.isMainThread {
            operation(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                operation(self)
            }
        }
    }
}

/// Owns one CLLocationManager on one long-lived thread with an active run loop.
/// This manager is query-only: it never requests permission or location updates.
final class CoreLocationAuthorizationStatusSource: NSObject, LocationAuthorizationStatusQuerying, CLLocationManagerDelegate {
    private final class ReadRequest: NSObject {
        let completion: (CLAuthorizationStatus) -> Void

        init(completion: @escaping (CLAuthorizationStatus) -> Void) {
            self.completion = completion
        }
    }

    private let lock = NSLock()
    private var workerThread: Thread?
    private var workerManager: CLLocationManager?
    private var statusChangeHandler: ((CLAuthorizationStatus) -> Void)?
    private var isWorkerReady = false
    private var pendingReadRequest: ReadRequest?

    func start(onStatusChange: @escaping (CLAuthorizationStatus) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard workerThread == nil else { return }
        statusChangeHandler = onStatusChange
        let thread = Thread(target: self, selector: #selector(runWorker), object: nil)
        thread.name = "Miataru.AuthorizationStatus"
        thread.qualityOfService = .userInitiated
        workerThread = thread
        thread.start()
    }

    func readStatus(completion: @escaping (CLAuthorizationStatus) -> Void) {
        lock.lock()
        let thread = workerThread
        guard let thread else {
            lock.unlock()
            completion(.notDetermined)
            return
        }
        let isReady = isWorkerReady
        if !isReady {
            pendingReadRequest = ReadRequest(completion: completion)
        }
        lock.unlock()
        guard isReady else { return }
        let request = ReadRequest(completion: completion)
        perform(#selector(readStatusOnWorker(_:)), on: thread, with: request, waitUntilDone: false)
    }

    @objc private func runWorker() {
        autoreleasepool {
            let manager = CLLocationManager()
            manager.delegate = self
            workerManager = manager
            RunLoop.current.add(Port(), forMode: .default)
            lock.lock()
            isWorkerReady = true
            let pendingRequest = pendingReadRequest
            self.pendingReadRequest = nil
            lock.unlock()
            if let pendingRequest {
                perform(#selector(readStatusOnWorker(_:)), on: Thread.current, with: pendingRequest, waitUntilDone: false)
            }
            RunLoop.current.run()
        }
    }

    @objc private func readStatusOnWorker(_ request: ReadRequest) {
        guard let workerManager else {
            request.completion(.notDetermined)
            return
        }
        request.completion(workerManager.authorizationStatus)
    }

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        reportStatusIfOwned(manager)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        reportStatusIfOwned(manager)
    }

    private func reportStatusIfOwned(_ manager: CLLocationManager) {
        guard manager === workerManager else { return }
        let status = manager.authorizationStatus
        lock.lock()
        let handler = statusChangeHandler
        lock.unlock()
        handler?(status)
    }
}
