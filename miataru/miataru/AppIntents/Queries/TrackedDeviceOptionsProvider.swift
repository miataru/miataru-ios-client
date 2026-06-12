/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedDeviceOptionsProvider.swift
 * miataru
 *
 * Created by Codex on 09.06.26.
 */

import AppIntents

struct TrackedDeviceOptionsProvider: DynamicOptionsProvider {
    typealias Result = IntentItemCollection<String>
    typealias DefaultValue = String

    func results() async throws -> IntentItemCollection<String> {
        let devices = try await IntentLocationService.shared.suggestedDevices()
        let optionValues = Self.optionValues(for: devices)
        let items = zip(optionValues, devices).map { value, device in
            IntentItem(
                value,
                title: LocalizedStringResource(stringLiteral: device.name)
            )
        }

        guard !items.isEmpty else { return .empty }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    func defaultResult() async -> String? {
        try? await IntentLocationService.shared.suggestedDevices().first?.id
    }

    static func optionValues(for devices: [TrackedDeviceEntity]) -> [String] {
        devices.map(\.id)
    }
}
