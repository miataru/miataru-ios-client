import Testing
import Combine
import Foundation
import MiataruAPIClient
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

    @Test("ingestServerLocations applies newer or equal timestamps but ignores older data")
    func testIngestServerLocationsRespectsTimestamps() async throws {
        let cache = DeviceLocationCacheStore.shared
        let deviceID = "TEST_DEVICE_TIMESTAMP_\(UUID().uuidString)"

        cache.removeLocation(for: deviceID)
        defer { cache.removeLocation(for: deviceID) }

        cache.setLocation(
            for: deviceID,
            latitude: 52.0,
            longitude: 13.0,
            accuracy: 10,
            timestamp: Date(timeIntervalSince1970: 2_000),
            batteryLevel: 0.50,
            altitude: 30,
            speed: 4
        )

        cache.ingestServerLocations([
            location(deviceID: deviceID, timestamp: 1_000, latitude: 40, longitude: 9, batteryLevel: 0.90, altitude: 99, speed: 12)
        ])

        var cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.latitude == 52.0)
        #expect(cached.longitude == 13.0)
        #expect(cached.batteryLevel == 0.50)
        #expect(cached.altitude == 30)
        #expect(cached.speed == 4)

        cache.ingestServerLocations([
            location(deviceID: deviceID, timestamp: 2_000, latitude: 52, longitude: 13, batteryLevel: 0.80, altitude: 40, speed: 8)
        ])

        cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.batteryLevel == 0.80)
        #expect(cached.altitude == 40)
        #expect(cached.speed == 8)

        cache.ingestServerLocations([
            location(deviceID: deviceID, timestamp: 3_000, latitude: 53, longitude: 14, batteryLevel: 0.70, altitude: 50, speed: nil)
        ])

        cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.latitude == 53)
        #expect(cached.longitude == 14)
        #expect(cached.batteryLevel == 0.70)
        #expect(cached.altitude == 50)
        #expect(cached.speed == 8)
    }

    @Test("ingestServerLocations only removes missing devices when explicitly requested")
    func testIngestServerLocationsMissingRemovalIsOptIn() async throws {
        let cache = DeviceLocationCacheStore.shared
        let retainedID = "TEST_DEVICE_RETAIN_\(UUID().uuidString)"
        let missingID = "TEST_DEVICE_MISSING_\(UUID().uuidString)"

        cache.removeLocation(for: retainedID)
        cache.removeLocation(for: missingID)
        defer {
            cache.removeLocation(for: retainedID)
            cache.removeLocation(for: missingID)
        }

        cache.setLocation(for: retainedID, latitude: 1, longitude: 1, accuracy: 5, timestamp: Date(timeIntervalSince1970: 1_000))
        cache.setLocation(for: missingID, latitude: 2, longitude: 2, accuracy: 5, timestamp: Date(timeIntervalSince1970: 1_000))

        cache.ingestServerLocations([
            location(deviceID: retainedID, timestamp: 2_000, latitude: 3, longitude: 3)
        ])
        #expect(cache.getLocation(for: missingID) != nil)

        cache.ingestServerLocations(
            [location(deviceID: retainedID, timestamp: 3_000, latitude: 4, longitude: 4)],
            removingMissingDeviceIDs: [missingID]
        )
        #expect(cache.getLocation(for: missingID) == nil)
    }

    @Test("ingestLatestHistoryEntry only promotes the newest matching history entry")
    func testIngestLatestHistoryEntryUsesNewestMatchingEntry() async throws {
        let cache = DeviceLocationCacheStore.shared
        let deviceID = "TEST_DEVICE_HISTORY_\(UUID().uuidString)"
        let otherID = "TEST_DEVICE_HISTORY_OTHER_\(UUID().uuidString)"

        cache.removeLocation(for: deviceID)
        cache.removeLocation(for: otherID)
        defer {
            cache.removeLocation(for: deviceID)
            cache.removeLocation(for: otherID)
        }

        cache.ingestLatestHistoryEntry(
            [
                location(deviceID: deviceID, timestamp: 1_000, latitude: 10, longitude: 10, batteryLevel: 0.10),
                location(deviceID: otherID, timestamp: 4_000, latitude: 99, longitude: 99, batteryLevel: 0.99),
                location(deviceID: deviceID, timestamp: 3_000, latitude: 30, longitude: 30, batteryLevel: 0.30)
            ],
            for: deviceID
        )

        var cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.timestamp == Date(timeIntervalSince1970: 3_000))
        #expect(cached.latitude == 30)
        #expect(cache.getLocation(for: otherID) == nil)

        cache.setLocation(
            for: deviceID,
            latitude: 50,
            longitude: 50,
            accuracy: 10,
            timestamp: Date(timeIntervalSince1970: 5_000),
            batteryLevel: 0.50
        )
        cache.ingestLatestHistoryEntry(
            [location(deviceID: deviceID, timestamp: 4_000, latitude: 40, longitude: 40, batteryLevel: 0.40)],
            for: deviceID
        )

        cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.timestamp == Date(timeIntervalSince1970: 5_000))
        #expect(cached.latitude == 50)
        #expect(cached.batteryLevel == 0.50)

        cache.ingestLatestHistoryEntry(
            [location(deviceID: otherID, timestamp: 6_000, latitude: 60, longitude: 60, batteryLevel: 0.60)],
            for: deviceID
        )

        cached = try #require(cache.getLocation(for: deviceID))
        #expect(cached.timestamp == Date(timeIntervalSince1970: 5_000))
        #expect(cache.getLocation(for: otherID) == nil)
    }

    @Test("updateRecentVisitors stores normalized recent visitor IDs for the current device")
    func testUpdateRecentVisitorsNormalizesAndFiltersEntries() async throws {
        let cache = DeviceLocationCacheStore.shared
        let ownID = "OWN_DEVICE_\(UUID().uuidString)"
        let recentID = "recent_device_\(UUID().uuidString)"
        let oldID = "old_device_\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: 10_000)

        cache.setRecentVisitorDeviceIDs([])
        defer { cache.setRecentVisitorDeviceIDs([]) }

        cache.updateRecentVisitors(
            from: [
                visitor(deviceID: recentID, date: now.addingTimeInterval(-30)),
                visitor(deviceID: oldID, date: now.addingTimeInterval(-120)),
                visitor(deviceID: ownID, date: now.addingTimeInterval(-10))
            ],
            ownDeviceID: ownID,
            window: 90,
            now: now
        )

        #expect(cache.hasRecentVisitor(deviceID: recentID.uppercased()))
        #expect(cache.hasRecentVisitor(deviceID: recentID.lowercased()))
        #expect(!cache.hasRecentVisitor(deviceID: oldID))
        #expect(!cache.hasRecentVisitor(deviceID: ownID))
    }

    private func location(
        deviceID: String,
        timestamp: TimeInterval,
        latitude: Double,
        longitude: Double,
        accuracy: Double = 10,
        batteryLevel: Double? = nil,
        altitude: Double? = nil,
        speed: Double? = nil
    ) -> MiataruLocationData {
        MiataruLocationData(
            Device: deviceID,
            Timestamp: String(Int64(timestamp)),
            Longitude: longitude,
            Latitude: latitude,
            HorizontalAccuracy: accuracy,
            Speed: speed,
            BatteryLevel: batteryLevel,
            Altitude: altitude
        )
    }

    private func visitor(deviceID: String, date: Date) -> MiataruVisitor {
        MiataruVisitor(
            DeviceID: deviceID,
            TimeStamp: String(Int64((date.timeIntervalSince1970 * 1_000).rounded()))
        )
    }
}
