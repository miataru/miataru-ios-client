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

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
enum WidgetTimelineDataLoader {
    static func loadEntryData(configuration: DeviceSelectionIntent) async -> (WidgetSharedPayload, WidgetDeviceData?) {
        let cachedPayload = SharedWidgetDataManager.read()
        let cachedDeviceIDs = cachedPayload?.devices.map { $0.id } ?? []
        let config = SharedWidgetConfigManager.read()
        let targetID = configuration.device?.id
            ?? cachedPayload?.devices.first?.id
            ?? config?.deviceIDs.first

        var payload = cachedPayload ?? WidgetSharedPayload(
            devices: [],
            ownDeviceID: config?.ownDeviceID,
            ownDevice: nil
        )

        guard let config, let serverURL = URL(string: config.miataruServerURL) else {
            let device = targetID.flatMap { id in payload.devices.first(where: { $0.id == id }) }
            return (payload, device)
        }

        let requestIDs = uniqueDeviceIDs(primary: targetID, additional: config.ownDeviceID)
        guard !requestIDs.isEmpty else {
            let device = targetID.flatMap { id in payload.devices.first(where: { $0.id == id }) }
            return (payload, device)
        }

        do {
            let locations = try await MiataruAPIClient.getLocation(
                serverURL: serverURL,
                forDeviceIDs: requestIDs,
                requestingDeviceID: config.ownDeviceID
            )
            payload = merge(locations, into: payload, cached: cachedPayload, ownDeviceID: config.ownDeviceID ?? payload.ownDeviceID)
            SharedWidgetDataManager.write(payload)
        } catch {
#if DEBUG
            print("[Widget] Failed to fetch locations for IDs \(requestIDs): \(error)")
#endif
            // Fall back to cached payload
        }

        let selectedDeviceID = targetID ?? requestIDs.first ?? cachedDeviceIDs.first
        let device = selectedDeviceID.flatMap { id in payload.devices.first(where: { $0.id == id }) }
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

