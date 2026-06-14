/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruPlaceQuery.swift
 * miataru
 *
 * Created by Codex on 14.06.26.
 */

import AppIntents
import Foundation

struct MiataruPlaceQuery: EntityQuery, EntityStringQuery {
    private let service: any IntentLocationServicing

    init() {
        service = IntentLocationService.shared
    }

    init(service: any IntentLocationServicing) {
        self.service = service
    }

    func entities(for identifiers: [MiataruPlaceEntity.ID]) async throws -> [MiataruPlaceEntity] {
        var entities: [MiataruPlaceEntity] = []
        for identifier in identifiers {
            if let place = try await service.place(for: identifier) {
                entities.append(place)
            }
        }
        return entities
    }

    func suggestedEntities() async throws -> [MiataruPlaceEntity] {
        try await service.knownPlaces()
    }

    func entities(matching string: String) async throws -> [MiataruPlaceEntity] {
        let searchText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let places = try await service.knownPlaces()
        guard !searchText.isEmpty else { return places }

        return places.filter {
            $0.name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
