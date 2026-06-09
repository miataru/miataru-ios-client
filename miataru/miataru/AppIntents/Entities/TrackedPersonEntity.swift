/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedPersonEntity.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents

struct TrackedPersonEntity: AppEntity, Identifiable, Sendable, Equatable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intent_tracked_person_type_name", defaultValue: "Person", comment: "Display name for a tracked person App Intent entity")
    )
    static var defaultQuery = TrackedPersonQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}
