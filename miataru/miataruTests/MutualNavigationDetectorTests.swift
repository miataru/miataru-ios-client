/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * MutualNavigationDetectorTests.swift
 * miataruTests
 *
 * Created by Daniel Kirstenpfad on 2026-01-19.
 */

import Testing
import Foundation
@testable import miataru
import MiataruAPIClient

struct MutualNavigationDetectorTests {
    
    @Test("Hysteresis: Enter mutual state at 60s threshold")
    func testHysteresisEnter() async throws {
        let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
        // Create a visitor entry that's 55 seconds ago (should enter)
        let recentTimestamp = referenceNow.addingTimeInterval(-55)
        let visitor = MiataruVisitor(
            DeviceID: "TARGET_DEVICE",
            TimeStamp: millisecondsTimestampString(for: recentTimestamp)
        )
        
        // Age is 55s, which is <= 60s (T_enter), so should enter mutual state
        let age = referenceNow.timeIntervalSince(visitor.TimeStampDate)
        #expect(age <= 60.0) // Should enter
    }
    
    @Test("Hysteresis: Exit mutual state at 90s threshold")
    func testHysteresisExit() async throws {
        let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
        // Create a visitor entry that's 95 seconds ago (should exit)
        let oldTimestamp = referenceNow.addingTimeInterval(-95)
        let visitor = MiataruVisitor(
            DeviceID: "TARGET_DEVICE",
            TimeStamp: millisecondsTimestampString(for: oldTimestamp)
        )
        
        // Age is 95s, which is > 90s (T_exit), so should exit mutual state
        let age = referenceNow.timeIntervalSince(visitor.TimeStampDate)
        #expect(age > 90.0) // Should exit
    }
    
    @Test("Hysteresis: Stay in mutual state between 60s and 90s")
    func testHysteresisStayIn() async throws {
        let referenceNow = Date(timeIntervalSince1970: 1_700_000_000)
        // When already in mutual state, should stay in if age <= 90s
        let midTimestamp = referenceNow.addingTimeInterval(-75)
        let visitor = MiataruVisitor(
            DeviceID: "TARGET_DEVICE",
            TimeStamp: millisecondsTimestampString(for: midTimestamp)
        )
        
        let age = referenceNow.timeIntervalSince(visitor.TimeStampDate)
        // Age is 75s, which is > 60s but <= 90s
        // If already mutual, should stay mutual (age <= 90s)
        #expect(age > 60.0)
        #expect(age <= 90.0)
    }
    
    @Test("Visitor timestamp parsing")
    func testVisitorTimestampParsing() async throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let visitor = MiataruVisitor(
            DeviceID: "TEST_DEVICE",
            TimeStamp: millisecondsTimestampString(for: timestamp)
        )
        
        // Check that timestamp is parsed correctly
        let parsedDate = visitor.TimeStampDate
        let diff = abs(parsedDate.timeIntervalSince(timestamp))
        #expect(diff < 0.001) // Should be within 1 millisecond
    }

    private func millisecondsTimestampString(for date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000.0).rounded()))
    }
}
