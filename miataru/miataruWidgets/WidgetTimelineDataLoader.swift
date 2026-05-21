/*
 * Copyright (c) 2013-2025, Daniel Kirstenpfad, www.miataru.com
 *
 * WidgetTimelineDataLoader.swift
 * miataru
 *
 * Created by Daniel Kirstenpfad on 2026-01-06.
 */

import Foundation
import MiataruAPIClient
#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
enum WidgetTimelineDataLoader {
    static func loadEntryData(configuration: DeviceSelectionIntent, generateMapSnapshots: Bool = false) async -> (WidgetSharedPayload, WidgetDeviceData?) {
        let cachedPayload = SharedWidgetDataManager.read()
        let cachedDeviceIDs = orderedDeviceIDs(in: cachedPayload)
        let config = SharedWidgetConfigManager.read()
        let knownIDs = cachedDeviceIDs + (config?.deviceIDs ?? [])
        let configuredDeviceID = cleanedID(configuration.device)
        let targetID = configuredDeviceID.flatMap { canonicalID($0, knownIDs: knownIDs) ?? $0 }
            ?? firstSelectionID(in: cachedPayload)
            ?? cachedPayload?.devices.first?.id
            ?? config?.deviceIDs.first

        var payload = cachedPayload ?? WidgetSharedPayload(
            devices: [],
            ownDeviceID: config?.ownDeviceID,
            ownDevice: nil
        )

        guard let config, let serverURL = URL(string: config.miataruServerURL) else {
            let device = targetID.flatMap { id in deviceMatching(id, in: payload) }
            return (payload, device)
        }

        let requestIDs = uniqueDeviceIDs(
            primary: targetID,
            additional: canonicalID(config.ownDeviceID, knownIDs: knownIDs) ?? config.ownDeviceID
        )
        guard !requestIDs.isEmpty else {
            let device = targetID.flatMap { id in deviceMatching(id, in: payload) }
            return (payload, device)
        }

        do {
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: serverURL,
                forDeviceIDs: requestIDs,
                requestingDeviceID: config.ownDeviceID ?? payload.ownDeviceID ?? "",
                requestingDeviceKey: config.ownDeviceKey
            )
            // Track widget-initiated request
            SharedWidgetDataManager.recordWidgetRequest()
            payload = merge(
                locations,
                into: payload,
                cached: cachedPayload,
                ownDeviceID: config.ownDeviceID ?? payload.ownDeviceID,
                configuredDeviceID: configuredDeviceID
            )
            SharedWidgetDataManager.write(payload)
        } catch {
#if DEBUG
            print("[Widget] Failed to fetch locations for IDs \(requestIDs): \(error)")
#endif
            // Fall back to cached payload
        }

        let selectedDeviceID = targetID ?? requestIDs.first ?? cachedDeviceIDs.first
        let device = selectedDeviceID.flatMap { id in deviceMatching(id, in: payload) }

        if generateMapSnapshots, let device {
            // Generating MKMapSnapshotter images can be slow and may exceed WidgetKit's
            // tight execution budget if awaited during timeline generation.
            // However, detached tasks can be delayed/suspended; we prefer to render the
            // currently displayed appearance synchronously so the widget can update promptly.
            #if canImport(UIKit)
            let preferred = UITraitCollection.current.userInterfaceStyle
            await WidgetMapSnapshotGenerator.ensureSnapshotsUpToDate(for: device, preferredStyle: preferred)

            // Best-effort: also render the other appearance so switching light/dark
            // doesn't force a placeholder as often.
            Task.detached(priority: .background) {
                await WidgetMapSnapshotGenerator.ensureOtherStyleBestEffort(for: device, preferredStyle: preferred)
            }
            #else
            await WidgetMapSnapshotGenerator.ensureSnapshotsUpToDate(for: device)
            #endif
        }

        return (payload, device)
    }

    private static func uniqueDeviceIDs(primary: String?, additional: String?) -> [String] {
        var ordered: [String] = []
        if let primary = cleanedID(primary), !primary.isEmpty {
            ordered.append(primary)
        }
        if let additional = cleanedID(additional),
           !additional.isEmpty,
           !ordered.contains(where: { normalizedDeviceID($0) == normalizedDeviceID(additional) }) {
            ordered.append(additional)
        }
        return ordered
    }

    private static func canonicalID(_ id: String?, knownIDs: [String]) -> String? {
        guard let id = cleanedID(id), !id.isEmpty else { return nil }
        if let exact = knownIDs.first(where: { $0 == id }) {
            return exact
        }
        let normalizedID = normalizedDeviceID(id)
        return knownIDs.first(where: { normalizedDeviceID($0) == normalizedID })
    }

    private static func deviceMatching(_ id: String, in payload: WidgetSharedPayload) -> WidgetDeviceData? {
        if let exact = payload.devices.first(where: { $0.id == id }) {
            return exact
        }
        let normalizedID = normalizedDeviceID(id)
        return payload.devices.first(where: { normalizedDeviceID($0.id) == normalizedID })
    }

    private static func merge(_ locations: [MiataruLocationData],
                              into payload: WidgetSharedPayload,
                              cached: WidgetSharedPayload?,
                              ownDeviceID: String?,
                              configuredDeviceID: String?) -> WidgetSharedPayload {
        var updatedPayload = payload
        updatedPayload.ownDeviceID = ownDeviceID ?? payload.ownDeviceID
        if (updatedPayload.deviceSelections?.isEmpty ?? true),
           let cachedSelections = cached?.deviceSelections,
           !cachedSelections.isEmpty {
            updatedPayload.deviceSelections = cachedSelections
        }

        var entriesByID = updatedPayload.devices.reduce(into: [String: WidgetDeviceData]()) { result, entry in
            let normalizedID = normalizedDeviceID(entry.id)
            guard !normalizedID.isEmpty else { return }
            result[normalizedID] = entry
        }
        let knownIDs = orderedDeviceIDs(in: updatedPayload) + orderedDeviceIDs(in: cached)

        for location in locations {
            let entryID = canonicalID(location.Device, knownIDs: knownIDs) ?? location.Device
            let metadata = deviceMatching(entryID, in: updatedPayload)
                ?? cached.flatMap { deviceMatching(entryID, in: $0) }
                ?? deviceMatching(location.Device, in: updatedPayload)
                ?? cached.flatMap { deviceMatching(location.Device, in: $0) }
            let selection = selectionMatching(entryID, in: updatedPayload)
                ?? cached.flatMap { selectionMatching(entryID, in: $0) }
                ?? selectionMatching(location.Device, in: updatedPayload)
                ?? cached.flatMap { selectionMatching(location.Device, in: $0) }
            let configuredSelectionMatches = configuredDeviceID.map {
                normalizedDeviceID($0) == normalizedDeviceID(entryID)
                    || normalizedDeviceID($0) == normalizedDeviceID(location.Device)
            } ?? false

            let entry = WidgetDeviceData(
                id: entryID,
                name: selection?.name
                    ?? metadata?.name
                    ?? (configuredSelectionMatches ? configuredDeviceID : nil)
                    ?? location.Device,
                latitude: location.Latitude,
                longitude: location.Longitude,
                locality: metadata?.locality,
                country: metadata?.country,
                timestamp: location.TimestampDate,
                accuracy: location.HorizontalAccuracy,
                color: selection?.color ?? metadata?.color
            )

            entriesByID[normalizedDeviceID(entry.id)] = entry
        }

        updatedPayload.devices = orderedDevices(from: entriesByID, payload: updatedPayload, cached: cached)
        updatedPayload.ownDevice = updatedPayload.ownDeviceID.flatMap { deviceMatching($0, in: updatedPayload) }

        return updatedPayload
    }

    private static func orderedDevices(from entriesByID: [String: WidgetDeviceData],
                                       payload: WidgetSharedPayload,
                                       cached: WidgetSharedPayload?) -> [WidgetDeviceData] {
        var result: [WidgetDeviceData] = []
        var seenIDs = Set<String>()

        func appendEntry(for id: String) {
            let normalizedID = normalizedDeviceID(id)
            guard !normalizedID.isEmpty,
                  seenIDs.insert(normalizedID).inserted,
                  let entry = entriesByID[normalizedID] else {
                return
            }
            result.append(entry)
        }

        for id in orderedDeviceIDs(in: payload) {
            appendEntry(for: id)
        }
        for id in orderedDeviceIDs(in: cached) {
            appendEntry(for: id)
        }
        for entry in payload.devices {
            appendEntry(for: entry.id)
        }
        for entry in cached?.devices ?? [] {
            appendEntry(for: entry.id)
        }
        for entry in entriesByID.values.sorted(by: {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }) {
            appendEntry(for: entry.id)
        }

        return result
    }

    private static func firstSelectionID(in payload: WidgetSharedPayload?) -> String? {
        selectionData(in: payload).first?.id
    }

    private static func orderedDeviceIDs(in payload: WidgetSharedPayload?) -> [String] {
        var seenIDs = Set<String>()
        var orderedIDs: [String] = []

        func append(_ id: String) {
            let normalizedID = normalizedDeviceID(id)
            guard !normalizedID.isEmpty, seenIDs.insert(normalizedID).inserted else { return }
            orderedIDs.append(id)
        }

        for selection in selectionData(in: payload) {
            append(selection.id)
        }
        for device in payload?.devices ?? [] {
            append(device.id)
        }

        return orderedIDs
    }

    private static func selectionData(in payload: WidgetSharedPayload?) -> [WidgetDeviceSelectionData] {
        guard let payload else { return [] }
        if let selections = payload.deviceSelections, !selections.isEmpty {
            return selections
        }
        return payload.devices.map {
            WidgetDeviceSelectionData(id: $0.id, name: $0.name, color: $0.color)
        }
    }

    private static func selectionMatching(_ id: String, in payload: WidgetSharedPayload) -> WidgetDeviceSelectionData? {
        let selections = selectionData(in: payload)
        if let exact = selections.first(where: { $0.id == id }) {
            return exact
        }
        let normalizedID = normalizedDeviceID(id)
        return selections.first(where: { normalizedDeviceID($0.id) == normalizedID })
    }

    private static func cleanedID(_ id: String?) -> String? {
        id?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
