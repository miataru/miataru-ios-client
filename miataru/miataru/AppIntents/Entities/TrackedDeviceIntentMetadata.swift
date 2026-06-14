/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * TrackedDeviceIntentMetadata.swift
 * miataru
 *
 * Created by Codex on 12.06.26.
 */

import AppIntents
import CoreSpotlight
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum TrackedDeviceIntentMetadata {
    static let userActivityType = "com.miataru.ios.tracked-device"

    static func trimmedDeviceID(_ deviceID: String) -> String {
        deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedDeviceID(_ deviceID: String) -> String {
        trimmedDeviceID(deviceID).uppercased()
    }

    static func displayName(deviceName: String, deviceID: String) -> String {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty
            ? NSLocalizedString("intent_device_fallback_name", tableName: "AppIntents", comment: "Fallback display name for a device without a device name")
            : trimmedName
    }

    static func isVisible(deviceID: String, hasCurrentLocationAccess: Bool) -> Bool {
        !trimmedDeviceID(deviceID).isEmpty && hasCurrentLocationAccess
    }

    static func entity(for device: KnownDevice) -> TrackedDeviceEntity? {
        guard isVisible(deviceID: device.DeviceID, hasCurrentLocationAccess: device.hasCurrentLocationAccess) else {
            return nil
        }
        return TrackedDeviceEntity(
            id: trimmedDeviceID(device.DeviceID),
            name: displayName(deviceName: device.DeviceName, deviceID: device.DeviceID)
        )
    }

    static func entity(from record: IntentDeviceRecord) -> TrackedDeviceEntity? {
        guard isVisible(deviceID: record.id, hasCurrentLocationAccess: record.hasCurrentLocationAccess) else {
            return nil
        }
        return TrackedDeviceEntity(
            id: trimmedDeviceID(record.id),
            name: displayName(deviceName: record.name, deviceID: record.id)
        )
    }

    @available(iOS 26.0, *)
    static func entityIdentifier(for entity: TrackedDeviceEntity) -> EntityIdentifier {
        EntityIdentifier(for: entity)
    }

    @available(iOS 26.0, *)
    static func annotate(_ activity: NSUserActivity, with entity: TrackedDeviceEntity) {
        let identifier = entityIdentifier(for: entity)
        activity.title = entity.name
        activity.targetContentIdentifier = identifier.description
        activity.appEntityIdentifier = identifier
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        activity.isEligibleForHandoff = false
        activity.isEligibleForPrediction = false
    }

    static func searchableAttributeSet(for entity: TrackedDeviceEntity) -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        attributeSet.title = entity.name
        attributeSet.displayName = entity.name
        return attributeSet
    }
}

extension TrackedDeviceEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        TrackedDeviceIntentMetadata.searchableAttributeSet(for: self)
    }

    var hideInSpotlight: Bool {
        true
    }
}

extension View {
    @ViewBuilder
    func trackedDeviceUserActivity(for device: KnownDevice) -> some View {
        if #available(iOS 26.0, *), let entity = TrackedDeviceIntentMetadata.entity(for: device) {
            userActivity(TrackedDeviceIntentMetadata.userActivityType, element: entity) { entity, activity in
                TrackedDeviceIntentMetadata.annotate(activity, with: entity)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func trackedDeviceViewAnnotation(for device: KnownDevice) -> some View {
        if #available(iOS 26.0, *), let entity = TrackedDeviceIntentMetadata.entity(for: device) {
            userActivity(TrackedDeviceIntentMetadata.userActivityType, element: entity) { entity, activity in
                TrackedDeviceIntentMetadata.annotate(activity, with: entity)
            }
        } else {
            self
        }
    }
}
