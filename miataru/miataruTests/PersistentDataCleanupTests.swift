/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * PersistentDataCleanupTests.swift
 * miataruTests
 *
 * Created by Codex on 21.05.26.
 */

import Testing
import Foundation
import UIKit
@testable import miataru

@MainActor
@Suite("Persistent data cleanup")
struct PersistentDataCleanupTests {
    private let retention: TimeInterval = 7 * 24 * 60 * 60

    @Test("Snapshot cleanup keeps retained cache snapshots and removes orphaned and legacy files")
    func snapshotCleanupRemovesOrphanedAndLegacyFiles() throws {
        let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: containerURL) }

        let retainedID = "RETAINED-\(UUID().uuidString)"
        let orphanID = "ORPHAN-\(UUID().uuidString)"

        let retainedLightURL = try #require(SharedWidgetDataManager.mapSnapshotURL(for: retainedID, style: UIUserInterfaceStyle.light, containerURL: containerURL))
        let retainedDarkURL = try #require(SharedWidgetDataManager.mapSnapshotURL(for: retainedID, style: UIUserInterfaceStyle.dark, containerURL: containerURL))
        let orphanURL = try #require(SharedWidgetDataManager.mapSnapshotURL(for: orphanID, style: UIUserInterfaceStyle.light, containerURL: containerURL))
        let snapshotDirectoryURL = try #require(SharedWidgetDataManager.mapSnapshotDirectoryURL(containerURL: containerURL))
        let atomicTempURL = snapshotDirectoryURL.appendingPathComponent("WidgetMapSnapshot-\(retainedID)-light.png.sb-test")
        let legacyRootURL = containerURL.appendingPathComponent("WidgetMapSnapshot-\(retainedID)-light.png")

        try writeMarker(to: retainedLightURL)
        try writeMarker(to: retainedDarkURL)
        try writeMarker(to: orphanURL)
        try writeMarker(to: atomicTempURL)
        try writeMarker(to: legacyRootURL)

        let removedCount = SharedWidgetDataManager.pruneMapSnapshots(
            retainingDeviceIDs: [retainedID],
            containerURL: containerURL
        )

        #expect(removedCount == 3)
        #expect(FileManager.default.fileExists(atPath: retainedLightURL.path))
        #expect(FileManager.default.fileExists(atPath: retainedDarkURL.path))
        #expect(!FileManager.default.fileExists(atPath: orphanURL.path))
        #expect(!FileManager.default.fileExists(atPath: atomicTempURL.path))
        #expect(!FileManager.default.fileExists(atPath: legacyRootURL.path))
    }

    @Test("Location cache pruning keeps retained and recent unknown devices")
    func locationCachePruningKeepsRetainedAndRecentUnknownDevices() {
        let cache = DeviceLocationCacheStore.shared
        let now = Date(timeIntervalSince1970: 2_000_000)
        let retainedID = "RETAINED-\(UUID().uuidString)"
        let recentUnknownID = "RECENT-\(UUID().uuidString)"
        let staleUnknownID = "STALE-\(UUID().uuidString)"

        cache.removeLocation(for: retainedID)
        cache.removeLocation(for: recentUnknownID)
        cache.removeLocation(for: staleUnknownID)
        defer {
            cache.removeLocation(for: retainedID)
            cache.removeLocation(for: recentUnknownID)
            cache.removeLocation(for: staleUnknownID)
        }

        cache.setLocation(for: retainedID, latitude: 1, longitude: 1, accuracy: 5, timestamp: now.addingTimeInterval(-(retention + 60)))
        cache.setLocation(for: recentUnknownID, latitude: 2, longitude: 2, accuracy: 5, timestamp: now.addingTimeInterval(-60))
        cache.setLocation(for: staleUnknownID, latitude: 3, longitude: 3, accuracy: 5, timestamp: now.addingTimeInterval(-(retention + 60)))

        let removedCount = cache.prune(
            retainingDeviceIDs: [retainedID],
            unknownDeviceTTL: retention,
            now: now
        )

        #expect(removedCount == 1)
        #expect(cache.getLocation(for: retainedID) != nil)
        #expect(cache.getLocation(for: recentUnknownID) != nil)
        #expect(cache.getLocation(for: staleUnknownID) == nil)
    }

    @Test("Slogan cache pruning keeps retained and recent unknown devices")
    func sloganCachePruningKeepsRetainedAndRecentUnknownDevices() {
        let cache = DeviceSloganCacheStore.shared
        let now = Date(timeIntervalSince1970: 2_000_000)
        let retainedID = "RETAINED-\(UUID().uuidString)"
        let recentUnknownID = "RECENT-\(UUID().uuidString)"
        let staleUnknownID = "STALE-\(UUID().uuidString)"
        let neverFetchedID = "NOFETCH-\(UUID().uuidString)"

        for id in [retainedID, recentUnknownID, staleUnknownID, neverFetchedID] {
            cache.removeCachedEntry(for: id)
        }
        defer {
            for id in [retainedID, recentUnknownID, staleUnknownID, neverFetchedID] {
                cache.removeCachedEntry(for: id)
            }
        }

        cache.cacheSlogan("retained", for: retainedID)
        cache.cacheSlogan("recent", for: recentUnknownID)
        cache.markFreshNow(for: recentUnknownID, at: now.addingTimeInterval(-60))
        cache.cacheSlogan("stale", for: staleUnknownID)
        cache.markFreshNow(for: staleUnknownID, at: now.addingTimeInterval(-(retention + 60)))
        cache.cacheSlogan("never fetched", for: neverFetchedID)

        let removedCount = cache.prune(
            retainingDeviceIDs: [retainedID],
            unknownDeviceTTL: retention,
            now: now
        )

        #expect(removedCount == 2)
        #expect(cache.slogan(for: retainedID) == "retained")
        #expect(cache.slogan(for: recentUnknownID) == "recent")
        #expect(cache.slogan(for: staleUnknownID) == nil)
        #expect(cache.slogan(for: neverFetchedID) == nil)
    }

    private func writeMarker(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data([0x6d]).write(to: url)
    }
}
