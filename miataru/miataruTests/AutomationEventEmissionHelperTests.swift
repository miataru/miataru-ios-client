/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * AutomationEventEmissionHelperTests.swift
 * miataruTests
 *
 * Created by Codex on 13.06.26.
 */

import Foundation
import Testing
@testable import miataru

@Suite("Automation event emission helpers")
struct AutomationEventEmissionHelperTests {
    @Test("Low battery helper records only battery percent and threshold")
    func lowBatteryHelperRecordsBatteryPercentAndThreshold() async {
        let recorder = HelperAutomationEventRecorder()

        await LocationManager.recordLowBatteryDisabledFrequentTrackingEvent(
            batteryPercent: 19,
            thresholdPercent: 20,
            recorder: recorder
        )

        let events = await recorder.recordedEvents()
        #expect(events.map(\.kind) == [.lowBatteryDisabledFrequentTracking])
        #expect(events.first?.privacyLevel == .publicSummary)
        #expect(events.first?.payload == [
            "batteryPercent": "19",
            "thresholdPercent": "20"
        ])
    }

    @Test("Expiration helper records ISO timestamp")
    func expirationHelperRecordsISOTimestamp() async {
        let recorder = HelperAutomationEventRecorder()
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        await LocationManager.recordFrequentTrackingExpiredEvent(at: date, recorder: recorder)

        let events = await recorder.recordedEvents()
        #expect(events.map(\.kind) == [.frequentTrackingExpired])
        #expect(events.first?.privacyLevel == .publicSummary)
        #expect(events.first?.payload["expiredAt"] == ISO8601DateFormatter().string(from: date))
    }
}

private actor HelperAutomationEventRecorder: MiataruAutomationEventRecording {
    private var events: [MiataruAutomationEventRecord] = []

    func record(_ event: MiataruAutomationEventRecord) async {
        events.append(event)
    }

    func record(
        kind: MiataruAutomationEventKind,
        privacyLevel: MiataruAutomationEventPrivacyLevel,
        deviceID: String?,
        deviceDisplayName: String?,
        placeID: String?,
        placeName: String?,
        payload: [String: String]
    ) async {
        events.append(MiataruAutomationEventRecord(
            kind: kind,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            privacyLevel: privacyLevel,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            placeID: placeID,
            placeName: placeName,
            payload: payload
        ))
    }

    func recordedEvents() -> [MiataruAutomationEventRecord] {
        events
    }
}
