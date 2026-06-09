/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedPersonOptionsProvider.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents

struct TrackedPersonOptionsProvider: DynamicOptionsProvider {
    typealias Result = IntentItemCollection<String>
    typealias DefaultValue = String

    func results() async throws -> IntentItemCollection<String> {
        let people = try await IntentLocationService.shared.suggestedPeople()
        let items = people.map { person in
            IntentItem(
                person.id,
                title: LocalizedStringResource(stringLiteral: person.name)
            )
        }

        guard !items.isEmpty else { return .empty }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    func defaultResult() async -> String? {
        try? await IntentLocationService.shared.suggestedPeople().first?.id
    }
}
