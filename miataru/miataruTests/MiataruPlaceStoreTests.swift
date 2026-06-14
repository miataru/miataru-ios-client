/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruPlaceStoreTests.swift
 * miataruTests
 *
 * Created by Codex on 14.06.26.
 */

import Foundation
import Testing
@testable import miataru

@Suite("Miataru place store")
struct MiataruPlaceStoreTests {
    @Test("Places persist reload trim names and normalize radii")
    func placesPersistReloadTrimNamesAndNormalizeRadii() async throws {
        let url = try temporaryFileURL()
        let now = Date(timeIntervalSince1970: 1_810_000_000)
        let store = MiataruPlaceStore(fileURL: url, nowProvider: { now })

        let home = try await store.savePlace(deviceID: "DEVICE-1", name: "  Home  ", latitude: 52.52, longitude: 13.405, radiusMeters: 10)
        let office = try await store.savePlace(deviceID: "DEVICE-1", name: "Office", latitude: 52.50, longitude: 13.39, radiusMeters: 10_000)

        #expect(home.deviceID == "DEVICE-1")
        #expect(home.name == "Home")
        #expect(home.radiusMeters == MiataruPlaceStore.minimumRadiusMeters)
        #expect(office.radiusMeters == MiataruPlaceStore.maximumRadiusMeters)

        let reloadedStore = MiataruPlaceStore(fileURL: url, nowProvider: { now })
        let reloaded = await reloadedStore.allPlaces()
        let devicePlaces = await reloadedStore.places(forDeviceID: "device-1")

        #expect(reloaded.map(\.id) == [home.id, office.id])
        #expect(devicePlaces.map(\.id) == [home.id, office.id])
        #expect(reloaded.map(\.name) == ["Home", "Office"])
        #expect(reloaded.map(\.radiusMeters) == [
            MiataruPlaceStore.minimumRadiusMeters,
            MiataruPlaceStore.maximumRadiusMeters
        ])
    }

    @Test("Default radius is used for missing or invalid radius")
    func defaultRadiusIsUsedForMissingOrInvalidRadius() async throws {
        let store = MiataruPlaceStore(fileURL: try temporaryFileURL())

        let defaulted = try await store.savePlace(deviceID: "DEVICE-1", name: "Default", latitude: 52.52, longitude: 13.405, radiusMeters: nil)
        let nonFinite = try await store.savePlace(deviceID: "DEVICE-1", name: "Nonfinite", latitude: 52.53, longitude: 13.406, radiusMeters: .infinity)

        #expect(defaulted.radiusMeters == MiataruPlaceStore.defaultRadiusMeters)
        #expect(nonFinite.radiusMeters == MiataruPlaceStore.defaultRadiusMeters)
    }

    @Test("Invalid and duplicate places are rejected")
    func invalidAndDuplicatePlacesAreRejected() async throws {
        let store = MiataruPlaceStore(fileURL: try temporaryFileURL())
        _ = try await store.savePlace(deviceID: "DEVICE-1", name: "Café", latitude: 52.52, longitude: 13.405, radiusMeters: nil)
        let sameNameOtherDevice = try await store.savePlace(deviceID: "DEVICE-2", name: " cafe ", latitude: 52.53, longitude: 13.406, radiusMeters: nil)

        #expect(sameNameOtherDevice.deviceID == "DEVICE-2")
        await expectPlaceStoreError(.invalidName) {
            _ = try await store.savePlace(deviceID: "DEVICE-1", name: "  ", latitude: 52.52, longitude: 13.405, radiusMeters: nil)
        }
        await expectPlaceStoreError(.duplicateName) {
            _ = try await store.savePlace(deviceID: "device-1", name: " cafe ", latitude: 52.53, longitude: 13.406, radiusMeters: nil)
        }
        await expectPlaceStoreError(.invalidCoordinate) {
            _ = try await store.savePlace(deviceID: "DEVICE-1", name: "Invalid", latitude: 95, longitude: 13.405, radiusMeters: nil)
        }
        await expectPlaceStoreError(.invalidDeviceID) {
            _ = try await store.savePlace(deviceID: "  ", name: "Invalid", latitude: 52.52, longitude: 13.405, radiusMeters: nil)
        }
    }

    @Test("Corrupt place file starts empty and removes invalid file")
    func corruptPlaceFileStartsEmptyAndRemovesInvalidFile() async throws {
        let url = try temporaryFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: url)

        let store = MiataruPlaceStore(fileURL: url)

        #expect(await store.allPlaces().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    private func expectPlaceStoreError(
        _ expectedError: MiataruPlaceStoreError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expectedError), but operation succeeded")
        } catch let error as MiataruPlaceStoreError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), but got \(error)")
        }
    }

    private func temporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiataruPlaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("places.json")
    }
}
