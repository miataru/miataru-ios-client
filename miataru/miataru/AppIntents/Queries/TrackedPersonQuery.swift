/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedPersonQuery.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents
import Foundation

struct TrackedPersonQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [TrackedPersonEntity.ID]) async throws -> [TrackedPersonEntity] {
        var entities: [TrackedPersonEntity] = []
        for identifier in identifiers {
            if let person = try await IntentLocationService.shared.person(for: identifier) {
                entities.append(person)
            }
        }
        return entities
    }

    func suggestedEntities() async throws -> [TrackedPersonEntity] {
        try await IntentLocationService.shared.suggestedPeople()
    }

    func entities(matching string: String) async throws -> [TrackedPersonEntity] {
        let searchText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let people = try await IntentLocationService.shared.suggestedPeople()
        guard !searchText.isEmpty else { return people }

        return people.filter {
            $0.name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
