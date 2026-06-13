/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruAutomationEventRecorder.swift
 * miataru
 *
 * Created by Codex on 13.06.26.
 */

import Foundation

protocol MiataruAutomationEventRecording: Sendable {
    func record(_ event: MiataruAutomationEventRecord) async
    func record(
        kind: MiataruAutomationEventKind,
        privacyLevel: MiataruAutomationEventPrivacyLevel,
        deviceID: String?,
        deviceDisplayName: String?,
        placeID: String?,
        placeName: String?,
        payload: [String: String]
    ) async
}

struct MiataruAutomationEventRecorder: MiataruAutomationEventRecording {
    static let shared = MiataruAutomationEventRecorder()

    private let store: any MiataruAutomationEventStoring
    private let nowProvider: @Sendable () -> Date

    init(
        store: any MiataruAutomationEventStoring = MiataruAutomationEventStore.shared,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.nowProvider = nowProvider
    }

    func record(_ event: MiataruAutomationEventRecord) async {
        await store.append(event)
    }

    func record(
        kind: MiataruAutomationEventKind,
        privacyLevel: MiataruAutomationEventPrivacyLevel,
        deviceID: String? = nil,
        deviceDisplayName: String? = nil,
        placeID: String? = nil,
        placeName: String? = nil,
        payload: [String: String] = [:]
    ) async {
        await record(MiataruAutomationEventRecord(
            kind: kind,
            timestamp: nowProvider(),
            privacyLevel: privacyLevel,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            placeID: placeID,
            placeName: placeName,
            payload: payload
        ))
    }
}

struct NoOpMiataruAutomationEventRecorder: MiataruAutomationEventRecording {
    func record(_ event: MiataruAutomationEventRecord) async {
        _ = event
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
        _ = kind
        _ = privacyLevel
        _ = deviceID
        _ = deviceDisplayName
        _ = placeID
        _ = placeName
        _ = payload
    }
}
