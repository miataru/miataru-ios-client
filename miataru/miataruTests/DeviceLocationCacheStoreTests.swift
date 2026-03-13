import Testing
import Combine
import Foundation
@testable import miataru

@MainActor
@Suite("Device location cache store")
struct DeviceLocationCacheStoreTests {

    @Test("applyLocationSnapshots publishes one consolidated update and preserves placemark data")
    func testApplyLocationSnapshotsPublishesSingleUpdate() async throws {
        let cache = DeviceLocationCacheStore.shared
        let firstID = "TEST_DEVICE_A_\(UUID().uuidString)"
        let secondID = "TEST_DEVICE_B_\(UUID().uuidString)"

        cache.removeLocation(for: firstID)
        cache.removeLocation(for: secondID)
        defer {
            cache.removeLocation(for: firstID)
            cache.removeLocation(for: secondID)
        }

        cache.setLocation(
            for: firstID,
            latitude: 52.5200,
            longitude: 13.4050,
            accuracy: 10,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            batteryLevel: 0.50,
            altitude: 34
        )
        cache.setPlacemark(for: firstID, country: "Germany", locality: "Berlin", timeZone: TimeZone(identifier: "Europe/Berlin"))
        cache.setLocation(
            for: secondID,
            latitude: 48.8566,
            longitude: 2.3522,
            accuracy: 15,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100),
            batteryLevel: 0.75,
            altitude: 12
        )

        var emissionCount = 0
        let cancellable = cache.$locations
            .dropFirst()
            .sink { _ in
                emissionCount += 1
            }
        defer { cancellable.cancel() }

        cache.applyLocationSnapshots([
            DeviceLocationSnapshot(
                deviceID: firstID,
                latitude: 52.5205,
                longitude: 13.4055,
                accuracy: 8,
                timestamp: Date(timeIntervalSince1970: 1_700_000_200),
                batteryLevel: 0.60,
                altitude: 35,
                speed: nil
            ),
            DeviceLocationSnapshot(
                deviceID: secondID,
                latitude: 48.8570,
                longitude: 2.3530,
                accuracy: 12,
                timestamp: Date(timeIntervalSince1970: 1_700_000_300),
                batteryLevel: 0.80,
                altitude: 14,
                speed: nil
            )
        ])

        #expect(emissionCount == 1)
        #expect(cache.getLocation(for: firstID)?.country == "Germany")
        #expect(cache.getLocation(for: firstID)?.locality == "Berlin")
        #expect(cache.getLocation(for: firstID)?.batteryLevel == 0.60)
        #expect(cache.getLocation(for: secondID)?.batteryLevel == 0.80)
    }

    @Test("applyLocationSnapshots removes devices marked missing")
    func testApplyLocationSnapshotsRemovesMissingDevices() async throws {
        let cache = DeviceLocationCacheStore.shared
        let retainedID = "TEST_DEVICE_KEEP_\(UUID().uuidString)"
        let removedID = "TEST_DEVICE_REMOVE_\(UUID().uuidString)"

        cache.removeLocation(for: retainedID)
        cache.removeLocation(for: removedID)
        defer {
            cache.removeLocation(for: retainedID)
            cache.removeLocation(for: removedID)
        }

        cache.setLocation(
            for: retainedID,
            latitude: 40.7128,
            longitude: -74.0060,
            accuracy: 9,
            timestamp: Date(timeIntervalSince1970: 1_700_000_400)
        )
        cache.setLocation(
            for: removedID,
            latitude: 41.8781,
            longitude: -87.6298,
            accuracy: 9,
            timestamp: Date(timeIntervalSince1970: 1_700_000_500)
        )

        cache.applyLocationSnapshots(
            [
                DeviceLocationSnapshot(
                    deviceID: retainedID,
                    latitude: 40.7130,
                    longitude: -74.0055,
                    accuracy: 7,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_600),
                    batteryLevel: nil,
                    altitude: nil,
                    speed: nil
                )
            ],
            removingMissingDeviceIDs: [removedID]
        )

        #expect(cache.getLocation(for: retainedID) != nil)
        #expect(cache.getLocation(for: removedID) == nil)
    }
}
