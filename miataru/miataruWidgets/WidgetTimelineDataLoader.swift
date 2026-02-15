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
        let cachedDeviceIDs = cachedPayload?.devices.map { $0.id } ?? []
        let config = SharedWidgetConfigManager.read()
        let knownIDs = cachedDeviceIDs + (config?.deviceIDs ?? [])
        let targetID = canonicalID(configuration.device?.id, knownIDs: knownIDs)
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
            payload = merge(locations, into: payload, cached: cachedPayload, ownDeviceID: config.ownDeviceID ?? payload.ownDeviceID)
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
        if let primary, !primary.isEmpty {
            ordered.append(primary)
        }
        if let additional, !additional.isEmpty, !ordered.contains(additional) {
            ordered.append(additional)
        }
        return ordered
    }

    private static func canonicalID(_ id: String?, knownIDs: [String]) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if let exact = knownIDs.first(where: { $0 == id }) {
            return exact
        }
        let lowercasedID = id.lowercased()
        return knownIDs.first(where: { $0.lowercased() == lowercasedID })
    }

    private static func deviceMatching(_ id: String, in payload: WidgetSharedPayload) -> WidgetDeviceData? {
        if let exact = payload.devices.first(where: { $0.id == id }) {
            return exact
        }
        let lowercasedID = id.lowercased()
        return payload.devices.first(where: { $0.id.lowercased() == lowercasedID })
    }

    private static func merge(_ locations: [MiataruLocationData],
                              into payload: WidgetSharedPayload,
                              cached: WidgetSharedPayload?,
                              ownDeviceID: String?) -> WidgetSharedPayload {
        var updatedPayload = payload
        updatedPayload.ownDeviceID = ownDeviceID ?? payload.ownDeviceID

        for location in locations {
            let metadataSource = cached ?? payload
            let metadata = metadataSource.devices.first(where: { $0.id == location.Device })

            let entry = WidgetDeviceData(
                id: location.Device,
                name: metadata?.name ?? location.Device,
                latitude: location.Latitude,
                longitude: location.Longitude,
                locality: metadata?.locality,
                country: metadata?.country,
                timestamp: location.TimestampDate,
                accuracy: location.HorizontalAccuracy,
                color: metadata?.color
            )

            updatedPayload.devices.removeAll { $0.id == entry.id }
            updatedPayload.devices.append(entry)

            if entry.id == updatedPayload.ownDeviceID {
                updatedPayload.ownDevice = entry
            }
        }

        return updatedPayload
    }
}
