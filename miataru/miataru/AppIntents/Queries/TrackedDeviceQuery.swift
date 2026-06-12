/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedDeviceQuery.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents
import Foundation

struct TrackedDeviceQuery: EntityQuery, EntityStringQuery {
    func entities(for identifiers: [TrackedDeviceEntity.ID]) async throws -> [TrackedDeviceEntity] {
        var entities: [TrackedDeviceEntity] = []
        for identifier in identifiers {
            if let device = try await IntentLocationService.shared.device(for: identifier) {
                entities.append(device)
            }
        }
        return entities
    }

    func suggestedEntities() async throws -> [TrackedDeviceEntity] {
        try await IntentLocationService.shared.suggestedDevices()
    }

    func entities(matching string: String) async throws -> [TrackedDeviceEntity] {
        let searchText = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let devices = try await IntentLocationService.shared.suggestedDevices()
        guard !searchText.isEmpty else { return devices }

        return devices.filter {
            $0.name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
