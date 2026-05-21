import Foundation
import Testing
import UIKit
@testable import miataru

@Suite("Widget data sync")
struct WidgetDataSyncCoordinatorTests {
    @Test("buildPayload keeps the widget selection list in device-store order")
    func testBuildPayloadKeepsSelectionOrderIndependentFromCachedLocations() throws {
        let first = KnownDevice(name: "First", deviceID: "DEVICE-A", color: .systemRed)
        let second = KnownDevice(name: "Second", deviceID: "DEVICE-B", color: .systemGreen)
        let third = KnownDevice(name: "Third", deviceID: "DEVICE-C", color: .systemBlue)

        first.KnownDevicesTablePosition = 0
        second.KnownDevicesTablePosition = 1
        third.KnownDevicesTablePosition = 2

        let secondLocation = CachedDeviceLocation(
            deviceID: "DEVICE-B",
            latitude: 52.52,
            longitude: 13.405,
            accuracy: 12,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let payload = WidgetDataSyncCoordinator.buildPayload(
            devices: [first, second, third],
            locations: [secondLocation],
            ownDeviceID: "DEVICE-A"
        )

        #expect(payload.deviceSelections?.map(\.id) == ["DEVICE-A", "DEVICE-B", "DEVICE-C"])
        #expect(payload.deviceSelections?.map(\.name) == ["First", "Second", "Third"])
        #expect(payload.devices.map(\.id) == ["DEVICE-B"])
    }
}
