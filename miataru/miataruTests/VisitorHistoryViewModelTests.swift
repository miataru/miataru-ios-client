/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * VisitorHistoryViewModelTests.swift
 * miataruTests
 *
 * Created by Daniel Kirstenpfad on 2026-01-19.
 */

import Testing
import Foundation
import UIKit
@testable import miataru
import MiataruAPIClient

@MainActor
struct VisitorHistoryViewModelTests {
    
    @Test("Known device resolution from visitor history")
    func testKnownDeviceResolution() async throws {
        let deviceStore = KnownDeviceStore.shared
        let testDeviceID = "KNOWN_DEVICE_\(UUID().uuidString)"
        let testDeviceName = "Test Device"
        deviceStore.removeDevice(byID: testDeviceID)
        defer { deviceStore.removeDevice(byID: testDeviceID) }
        
        // Create a known device
        let knownDevice = KnownDevice(
            name: testDeviceName,
            deviceID: testDeviceID,
            color: UIColor.systemBlue
        )
        let wasAdded = deviceStore.add(device: knownDevice)
        #expect(wasAdded == true)
        
        // Create a visitor entry with the same device ID
        let visitor = MiataruVisitor(
            DeviceID: testDeviceID,
            TimeStamp: millisecondsTimestampString(for: Date())
        )
        
        // Check that we can find the known device
        let foundDevice = deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() }
        #expect(foundDevice != nil)
        #expect(foundDevice?.DeviceName == testDeviceName)
        
    }
    
    @Test("Unknown device resolution from visitor history")
    func testUnknownDeviceResolution() async throws {
        let deviceStore = KnownDeviceStore.shared
        let unknownDeviceID = "UNKNOWN_DEVICE_\(UUID().uuidString)"
        deviceStore.removeDevice(byID: unknownDeviceID)
        
        // Create a visitor entry with unknown device ID
        let visitor = MiataruVisitor(
            DeviceID: unknownDeviceID,
            TimeStamp: millisecondsTimestampString(for: Date())
        )
        
        // Check that device is not found in known devices
        let foundDevice = deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() }
        #expect(foundDevice == nil)
    }
    
    @Test("Device resolution after adding unknown device")
    func testDeviceResolutionAfterAdd() async throws {
        let deviceStore = KnownDeviceStore.shared
        let testDeviceID = "NEWLY_ADDED_DEVICE_\(UUID().uuidString)"
        let testDeviceName = "Newly Added Device"
        deviceStore.removeDevice(byID: testDeviceID)
        defer { deviceStore.removeDevice(byID: testDeviceID) }
        
        // Initially, device should be unknown
        let visitor = MiataruVisitor(
            DeviceID: testDeviceID,
            TimeStamp: millisecondsTimestampString(for: Date())
        )
        
        var foundDevice = deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() }
        #expect(foundDevice == nil)
        
        // Add the device
        let newDevice = KnownDevice(
            name: testDeviceName,
            deviceID: testDeviceID,
            color: UIColor.systemGreen
        )
        let wasAdded = deviceStore.add(device: newDevice)
        #expect(wasAdded == true)
        
        // Now device should be known
        foundDevice = deviceStore.devices.first { $0.DeviceID.uppercased() == visitor.DeviceID.uppercased() }
        #expect(foundDevice != nil)
        #expect(foundDevice?.DeviceName == testDeviceName)
        
    }
    
    @Test("Visitor history sorting by timestamp")
    func testVisitorHistorySorting() async throws {
        let now = Date()
        let visitors = [
            MiataruVisitor(
                DeviceID: "DEVICE_1",
                TimeStamp: millisecondsTimestampString(for: now.addingTimeInterval(-300))
            ),
            MiataruVisitor(
                DeviceID: "DEVICE_2",
                TimeStamp: millisecondsTimestampString(for: now.addingTimeInterval(-60))
            ),
            MiataruVisitor(
                DeviceID: "DEVICE_3",
                TimeStamp: millisecondsTimestampString(for: now.addingTimeInterval(-120))
            )
        ]
        
        // Sort by most recent first
        let sorted = visitors.sorted { $0.TimeStampDate > $1.TimeStampDate }
        
        // Most recent should be first
        #expect(sorted.first?.DeviceID == "DEVICE_2")
        #expect(sorted.last?.DeviceID == "DEVICE_1")
    }
    
    @Test("Shortened device ID format")
    func testShortenedDeviceID() async throws {
        let longDeviceID = "1234567890ABCDEF"
        let shortened = shortenedDeviceID(longDeviceID)
        
        // Should be first 6 + ... + last 4
        #expect(shortened.hasPrefix("123456"))
        #expect(shortened.hasSuffix("CDEF"))
        #expect(shortened.contains("..."))
    }
    
    // Helper function matching the implementation
    private func shortenedDeviceID(_ deviceID: String) -> String {
        guard deviceID.count > 10 else { return deviceID }
        let start = String(deviceID.prefix(6))
        let end = String(deviceID.suffix(4))
        return "\(start)...\(end)"
    }

    private func millisecondsTimestampString(for date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000.0).rounded()))
    }
}
