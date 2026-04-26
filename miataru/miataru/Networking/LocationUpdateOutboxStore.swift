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
    let enableHistory: Bool
    let retentionTime: Int

    init(
        serverURLString: String,
        enqueuedAt: Date,
        availableAfter: Date? = nil,
        attemptCount: Int = 0,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int
    ) {
        self.dedupeKey = Self.makeDedupeKey(for: payload)
        self.serverURLString = serverURLString
        self.enqueuedAt = enqueuedAt
        self.availableAfter = availableAfter
        self.attemptCount = attemptCount
        self.payload = payload
        self.enableHistory = enableHistory
        self.retentionTime = retentionTime
    }

    static func makeDedupeKey(for payload: UpdateLocationPayload) -> String {
        "\(payload.Device)|\(payload.Timestamp)|\(payload.Latitude)|\(payload.Longitude)"
    }
}

actor LocationUpdateOutboxStore {
    private var items: [LocationUpdateOutboxItem] = []

    private let fileURL: URL
    private var maxItems: Int
    private var ttl: TimeInterval?
    private let nowProvider: () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL? = nil,
        maxItems: Int = 500,
        ttl: TimeInterval? = 24 * 60 * 60,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.maxItems = max(1, maxItems)
        self.ttl = ttl.map { max(1, $0) }
        self.nowProvider = nowProvider

        let loadedItems = Self.loadItems(from: self.fileURL, decoder: self.decoder)
        let prunedItems = Self.prunedItems(loadedItems, now: self.nowProvider(), ttl: self.ttl)
        let limitedItems = Self.limitedItems(prunedItems, maxItems: self.maxItems)
        self.items = limitedItems
        if limitedItems.count != loadedItems.count {
            Self.persist(limitedItems, to: self.fileURL, encoder: self.encoder)
        }
    }

    func updatePolicy(maxItems: Int, ttl: TimeInterval?) {
        self.maxItems = max(1, maxItems)
        self.ttl = ttl.map { max(1, $0) }
        pruneExpiredEntriesIfNeeded()
        enforceMaximumItemCountIfNeeded()
    }

    func updateServerURLForPendingItems(_ serverURL: URL) -> Bool {
        pruneExpiredEntriesIfNeeded()

        let serverURLString = serverURL.absoluteString
        var didChange = false
        for index in items.indices where items[index].serverURLString != serverURLString {
            items[index].serverURLString = serverURLString
            didChange = true
        }

        if didChange {
            persist()
        }
        return didChange
    }

    func enqueue(
        serverURL: URL,
        payload: UpdateLocationPayload,
        enableHistory: Bool,
        retentionTime: Int,
        availableAfter: Date? = nil
    ) {
        pruneExpiredEntriesIfNeeded()

        let item = LocationUpdateOutboxItem(
            serverURLString: serverURL.absoluteString,
            enqueuedAt: nowProvider(),
            availableAfter: availableAfter,
            payload: payload,
            enableHistory: enableHistory,
            retentionTime: retentionTime
        )

        guard !items.contains(where: { $0.dedupeKey == item.dedupeKey }) else {
            return
        }

        if items.count >= maxItems {
            let overflow = (items.count - maxItems) + 1
            items.removeFirst(overflow)
        }

        items.append(item)
        persist()
    }

    func pruneExpiredEntries() {
        pruneExpiredEntriesIfNeeded()
    }

    func peekHead() -> LocationUpdateOutboxItem? {
        pruneExpiredEntriesIfNeeded()
        return items.first
    }

    func removeHead() {
        guard !items.isEmpty else { return }
        items.removeFirst()
        persist()
    }

    func removeHead(matching item: LocationUpdateOutboxItem) -> Bool {
        guard let head = items.first,
              Self.isSameQueuedRecord(head, item) else {
            return false
        }
        items.removeFirst()
        persist()
        return true
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        items.removeAll()
        persist()
    }

    func incrementHeadAttemptCount() {
        guard !items.isEmpty else { return }
        items[0].attemptCount += 1
        persist()
    }

    func incrementHeadAttemptCount(matching item: LocationUpdateOutboxItem) -> Bool {
        guard let head = items.first,
              Self.isSameQueuedRecord(head, item) else {
            return false
        }
        items[0].attemptCount += 1
        persist()
        return true
    }

    func count() -> Int {
        pruneExpiredEntriesIfNeeded()
        return items.count
    }

    func isEmpty() -> Bool {
        count() == 0
    }

    func itemsSnapshot() -> [LocationUpdateOutboxItem] {
        pruneExpiredEntriesIfNeeded()
        return items
    }

    func activeDelayedBatchReleaseDate(now: Date) -> Date? {
        pruneExpiredEntriesIfNeeded()
        return items
            .compactMap(\.availableAfter)
            .filter { $0 > now }
            .min()
    }

    func nextFlushDate(now: Date) -> Date? {
        pruneExpiredEntriesIfNeeded()
        guard let head = items.first else { return nil }
        guard let availableAfter = head.availableAfter, availableAfter > now else {
            return now
        }
        return availableAfter
    }

    private func pruneExpiredEntriesIfNeeded() {
        guard let ttl else { return }
        let now = nowProvider()
        let originalCount = items.count
        items.removeAll { now.timeIntervalSince($0.enqueuedAt) > ttl }
        if items.count != originalCount {
            persist()
        }
    }

    private func enforceMaximumItemCountIfNeeded() {
        guard items.count > maxItems else { return }
        let overflow = items.count - maxItems
        items.removeFirst(overflow)
        persist()
    }

    private func loadItems() -> [LocationUpdateOutboxItem] {
        Self.loadItems(from: fileURL, decoder: decoder)
    }

    private func persist() {
        Self.persist(items, to: fileURL, encoder: encoder)
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

    private static func loadItems(from fileURL: URL, decoder: JSONDecoder) -> [LocationUpdateOutboxItem] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        do {
            return try decoder.decode([LocationUpdateOutboxItem].self, from: data)
        } catch {
            debugLog("[LocationUpdateOutboxStore] Failed decoding outbox, starting empty: \(error)")
            return []
        }
    }

    private static func persist(_ items: [LocationUpdateOutboxItem], to fileURL: URL, encoder: JSONEncoder) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[LocationUpdateOutboxStore] Failed persisting outbox: \(error)")
        }
    }
}
