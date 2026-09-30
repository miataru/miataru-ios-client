/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * LocationUpdateOutboxStore.swift
 * miataru
 *
 * Created by Codex on 04.03.26.
 */

import Foundation
import MiataruAPIClient

struct LocationUpdateOutboxItem: Codable {
    let dedupeKey: String
    var serverURLString: String
    let enqueuedAt: Date
    let availableAfter: Date?
    var attemptCount: Int
    let payload: UpdateLocationPayload
    var enableHistory: Bool
    let retentionTime: Int
    let visitorCheckMinimumInterval: TimeInterval?
    let processKnownVisitorAlerts: Bool

    init(
        serverURLString: String,
        enqueuedAt: Date,
        availableAfter: Date? = nil,
        attemptCount: Int = 0,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        visitorCheckMinimumInterval: TimeInterval? = nil,
        processKnownVisitorAlerts: Bool = false
    ) {
        self.dedupeKey = Self.makeDedupeKey(for: payload)
        self.serverURLString = serverURLString
        self.enqueuedAt = enqueuedAt
        self.availableAfter = availableAfter
        self.attemptCount = attemptCount
        self.payload = payload
        self.enableHistory = enableHistory
        self.retentionTime = retentionTime
        self.visitorCheckMinimumInterval = visitorCheckMinimumInterval
        self.processKnownVisitorAlerts = processKnownVisitorAlerts
    }

    private enum CodingKeys: String, CodingKey {
        case dedupeKey
        case serverURLString
        case enqueuedAt
        case availableAfter
        case attemptCount
        case payload
        case enableHistory
        case retentionTime
        case visitorCheckMinimumInterval
        case processKnownVisitorAlerts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.dedupeKey = try container.decode(String.self, forKey: .dedupeKey)
        self.serverURLString = try container.decode(String.self, forKey: .serverURLString)
        self.enqueuedAt = try container.decode(Date.self, forKey: .enqueuedAt)
        self.availableAfter = try container.decodeIfPresent(Date.self, forKey: .availableAfter)
        self.attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        self.payload = try container.decode(UpdateLocationPayload.self, forKey: .payload)
        self.enableHistory = try container.decode(Bool.self, forKey: .enableHistory)
        self.retentionTime = try container.decode(Int.self, forKey: .retentionTime)
        self.visitorCheckMinimumInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .visitorCheckMinimumInterval)
        self.processKnownVisitorAlerts = try container.decodeIfPresent(Bool.self, forKey: .processKnownVisitorAlerts) ?? false
    }

    static func makeDedupeKey(for payload: UpdateLocationPayload) -> String {
        "\(payload.Device)|\(payload.Timestamp)|\(payload.Latitude)|\(payload.Longitude)"
    }
}

actor LocationUpdateOutboxStore {
    private enum LoadResult {
        case loaded([LocationUpdateOutboxItem])
        case unavailable
    }

    private var items: [LocationUpdateOutboxItem] = []
    private var storageUnavailable = false

    private let fileURL: URL
    private var maxItems: Int
    private var ttl: TimeInterval?
    private let nowProvider: () -> Date
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL? = nil,
        maxItems: Int = 500,
        ttl: TimeInterval? = 24 * 60 * 60,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let resolvedFileURL = fileURL ?? Self.defaultFileURL()
        let resolvedMaxItems = max(1, maxItems)
        let resolvedTTL = ttl.map { max(1, $0) }
        let resolvedEncoder = JSONEncoder()
        let resolvedDecoder = JSONDecoder()
        let initialItems: [LocationUpdateOutboxItem]
        let initialStorageUnavailable: Bool

        switch Self.loadItems(from: resolvedFileURL, decoder: resolvedDecoder) {
        case .loaded(let loadedItems):
            let prunedItems = Self.prunedItems(loadedItems, now: nowProvider(), ttl: resolvedTTL)
            let limitedItems = Self.limitedItems(prunedItems, maxItems: resolvedMaxItems)
            if limitedItems.count == loadedItems.count || Self.persist(limitedItems, to: resolvedFileURL, encoder: resolvedEncoder) {
                initialItems = limitedItems
                initialStorageUnavailable = false
            } else {
                initialItems = loadedItems
                initialStorageUnavailable = true
            }
        case .unavailable:
            initialItems = []
            initialStorageUnavailable = true
        }

        self.fileURL = resolvedFileURL
        self.maxItems = resolvedMaxItems
        self.ttl = resolvedTTL
        self.nowProvider = nowProvider
        self.encoder = resolvedEncoder
        self.decoder = resolvedDecoder
        self.items = initialItems
        self.storageUnavailable = initialStorageUnavailable
    }

    func isStorageAvailable() -> Bool {
        recoverStorageIfNeeded()
    }

    func updatePolicy(maxItems: Int, ttl: TimeInterval?) {
        self.maxItems = max(1, maxItems)
        self.ttl = ttl.map { max(1, $0) }
        pruneExpiredEntriesIfNeeded()
        enforceMaximumItemCountIfNeeded()
    }

    func updateServerURLForPendingItems(_ serverURL: URL) -> Bool {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return false }

        let serverURLString = serverURL.absoluteString
        var updatedItems = items
        var didChange = false
        for index in updatedItems.indices where updatedItems[index].serverURLString != serverURLString {
            updatedItems[index].serverURLString = serverURLString
            didChange = true
        }

        if didChange {
            return commit(updatedItems)
        }
        return false
    }

    @discardableResult
    func enqueue(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        availableAfter: Date? = nil,
        visitorCheckMinimumInterval: TimeInterval? = nil,
        processKnownVisitorAlerts: Bool = false
    ) -> Bool {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return false }

        let item = LocationUpdateOutboxItem(
            serverURLString: serverURL.absoluteString,
            enqueuedAt: nowProvider(),
            availableAfter: availableAfter,
            payload: payload,
            enableHistory: enableHistory,
            retentionTime: retentionTime,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval,
            processKnownVisitorAlerts: processKnownVisitorAlerts
        )

        guard !items.contains(where: { $0.dedupeKey == item.dedupeKey }) else {
            return true
        }

        var updatedItems = items
        if updatedItems.count >= maxItems {
            let overflow = (updatedItems.count - maxItems) + 1
            updatedItems.removeFirst(overflow)
        }

        updatedItems.append(item)
        return commit(updatedItems)
    }

    /// Persists one Core Location callback as a single ordered outbox change.
    /// No network request can overtake a later sample in the same callback.
    @discardableResult
    func enqueueBatch(_ batch: [LocationUpdateOutboxItem]) -> Bool {
        guard !batch.isEmpty else { return true }
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return false }

        var updatedItems = items
        var knownKeys = Set(updatedItems.map(\.dedupeKey))
        for item in batch where knownKeys.insert(item.dedupeKey).inserted {
            updatedItems.append(item)
        }
        guard updatedItems.count != items.count else { return true }
        if updatedItems.count > maxItems {
            updatedItems.removeFirst(updatedItems.count - maxItems)
        }
        return commit(updatedItems)
    }

    @discardableResult
    func enqueueAtFront(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        visitorCheckMinimumInterval: TimeInterval? = nil,
        processKnownVisitorAlerts: Bool = false
    ) -> Bool {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return false }

        let item = LocationUpdateOutboxItem(
            serverURLString: serverURL.absoluteString,
            enqueuedAt: nowProvider(),
            payload: payload,
            enableHistory: enableHistory,
            retentionTime: retentionTime,
            visitorCheckMinimumInterval: visitorCheckMinimumInterval,
            processKnownVisitorAlerts: processKnownVisitorAlerts
        )

        var updatedItems = items
        if let existingIndex = updatedItems.firstIndex(where: { $0.dedupeKey == item.dedupeKey }) {
            updatedItems.remove(at: existingIndex)
        }

        updatedItems.insert(item, at: 0)

        if updatedItems.count > maxItems {
            let overflow = updatedItems.count - maxItems
            updatedItems.removeLast(overflow)
        }

        return commit(updatedItems)
    }

    func pruneExpiredEntries() {
        pruneExpiredEntriesIfNeeded()
    }

    func peekHead() -> LocationUpdateOutboxItem? {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return nil }
        return items.first
    }

    func removeHead() {
        guard recoverStorageIfNeeded() else { return }
        guard !items.isEmpty else { return }
        _ = commit(Array(items.dropFirst()))
    }

    func removeHead(matching item: LocationUpdateOutboxItem) -> Bool {
        guard recoverStorageIfNeeded() else { return false }
        guard let head = items.first,
              Self.isSameQueuedRecord(head, item) else {
            return false
        }
        return commit(Array(items.dropFirst()))
    }

    func removeAll() {
        guard recoverStorageIfNeeded() else { return }
        guard !items.isEmpty else { return }
        _ = commit([])
    }

    func incrementHeadAttemptCount() {
        guard recoverStorageIfNeeded() else { return }
        guard !items.isEmpty else { return }
        var updatedItems = items
        updatedItems[0].attemptCount += 1
        _ = commit(updatedItems)
    }

    func incrementHeadAttemptCount(matching item: LocationUpdateOutboxItem) -> Bool {
        guard recoverStorageIfNeeded() else { return false }
        guard let head = items.first,
              Self.isSameQueuedRecord(head, item) else {
            return false
        }
        var updatedItems = items
        updatedItems[0].attemptCount += 1
        return commit(updatedItems)
    }

    func count() -> Int {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return 0 }
        return items.count
    }

    func isEmpty() -> Bool {
        count() == 0
    }

    func itemsSnapshot() -> [LocationUpdateOutboxItem] {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return [] }
        return items
    }

    func activeDelayedBatchReleaseDate(now: Date) -> Date? {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return nil }
        return items
            .compactMap(\.availableAfter)
            .filter { $0 > now }
            .min()
    }

    func nextFlushDate(now: Date) -> Date? {
        pruneExpiredEntriesIfNeeded()
        guard !storageUnavailable else { return nil }
        guard let head = items.first else { return nil }
        guard let availableAfter = head.availableAfter, availableAfter > now else {
            return now
        }
        return availableAfter
    }

    private func pruneExpiredEntriesIfNeeded() {
        guard recoverStorageIfNeeded() else { return }
        guard let ttl else { return }
        let now = nowProvider()
        let retainedItems = items.filter { now.timeIntervalSince($0.enqueuedAt) <= ttl }
        if retainedItems.count != items.count {
            _ = commit(retainedItems)
        }
    }

    private func enforceMaximumItemCountIfNeeded() {
        guard recoverStorageIfNeeded() else { return }
        guard items.count > maxItems else { return }
        _ = commit(Self.limitedItems(items, maxItems: maxItems))
    }

    private func recoverStorageIfNeeded() -> Bool {
        guard storageUnavailable else { return true }
        switch Self.loadItems(from: fileURL, decoder: decoder) {
        case .loaded(let loadedItems):
            let prunedItems = Self.prunedItems(loadedItems, now: nowProvider(), ttl: ttl)
            let limitedItems = Self.limitedItems(prunedItems, maxItems: maxItems)
            if limitedItems.count != loadedItems.count,
               !Self.persist(limitedItems, to: fileURL, encoder: encoder) {
                return false
            }
            items = limitedItems
            storageUnavailable = false
            return true
        case .unavailable:
            return false
        }
    }

    private func commit(_ updatedItems: [LocationUpdateOutboxItem]) -> Bool {
        guard !storageUnavailable else { return false }
        guard Self.persist(updatedItems, to: fileURL, encoder: encoder) else {
            storageUnavailable = true
            return false
        }
        items = updatedItems
        return true
    }

    private static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let appContainerName = Bundle.main.bundleIdentifier ?? "miataru"
        return appSupportDirectory
            .appendingPathComponent(appContainerName, isDirectory: true)
            .appendingPathComponent("locationUpdateOutbox.json")
    }

    static func storageFileURL() -> URL {
        defaultFileURL()
    }

    private static func prunedItems(_ items: [LocationUpdateOutboxItem], now: Date, ttl: TimeInterval?) -> [LocationUpdateOutboxItem] {
        guard let ttl else { return items }
        return items.filter { now.timeIntervalSince($0.enqueuedAt) <= ttl }
    }

    private static func limitedItems(_ items: [LocationUpdateOutboxItem], maxItems: Int) -> [LocationUpdateOutboxItem] {
        guard items.count > maxItems else { return items }
        return Array(items.suffix(maxItems))
    }

    private static func isSameQueuedRecord(_ lhs: LocationUpdateOutboxItem, _ rhs: LocationUpdateOutboxItem) -> Bool {
        lhs.dedupeKey == rhs.dedupeKey
            && lhs.enqueuedAt == rhs.enqueuedAt
            && lhs.serverURLString == rhs.serverURLString
    }

    private static func loadItems(from fileURL: URL, decoder: JSONDecoder) -> LoadResult {
        do {
            let data = try Data(contentsOf: fileURL)
            do {
                return .loaded(try decoder.decode([LocationUpdateOutboxItem].self, from: data))
            } catch {
                // The bytes are readable but not a usable queue. Retain the original file
                // in App Support, then let new location updates use a fresh active outbox.
                let retainedURL = fileURL.deletingPathExtension()
                    .appendingPathExtension("unreadable-\(UUID().uuidString)")
                    .appendingPathExtension(fileURL.pathExtension)
                do {
                    try FileManager.default.moveItem(at: fileURL, to: retainedURL)
                    debugLog("[LocationUpdateOutboxStore] Retained undecodable outbox and started a fresh queue")
                    return .loaded([])
                } catch {
                    debugLog("[LocationUpdateOutboxStore] Could not retain undecodable outbox; preserving original file")
                    return .unavailable
                }
            }
        } catch {
            let fileError = error as NSError
            if fileError.domain == NSCocoaErrorDomain,
               fileError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                return .loaded([])
            }
            debugLog("[LocationUpdateOutboxStore] Could not read outbox; preserving existing file")
            return .unavailable
        }
    }

    private static func persist(_ items: [LocationUpdateOutboxItem], to fileURL: URL, encoder: JSONEncoder) -> Bool {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            debugLog("[LocationUpdateOutboxStore] Failed persisting outbox: \(error)")
            return false
        }
    }
}
