/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedDeviceEntity.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents

struct TrackedDeviceEntity: AppEntity, Identifiable, Sendable, Equatable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_tracked_device_type_name", defaultValue: "Tracked Device", table: "AppIntents", comment: "Display name for a tracked device App Intent entity")
    )
    static var defaultQuery = TrackedDeviceQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}
