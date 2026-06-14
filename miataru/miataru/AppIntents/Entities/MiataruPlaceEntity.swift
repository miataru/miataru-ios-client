/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * MiataruPlaceEntity.swift
 * miataru
 *
 * Created by Codex on 14.06.26.
 */

import AppIntents
import CoreSpotlight
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct MiataruPlaceEntity: AppEntity, Identifiable, Sendable, Equatable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "intent_place_type_name",
            defaultValue: "Saved Place",
            comment: "Display name for a saved place App Intent entity"
        )
    )
    static var defaultQuery = MiataruPlaceQuery()

    let id: UUID
    let deviceID: String
    let name: String
    let radiusMeters: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: name),
            subtitle: LocalizedStringResource(stringLiteral: MiataruPlaceIntentMetadata.radiusSubtitle(radiusMeters))
        )
    }
}

enum MiataruPlaceIntentMetadata {
    static let userActivityType = "com.miataru.ios.saved-place"

    static func entity(from record: MiataruPlaceRecord) -> MiataruPlaceEntity {
        MiataruPlaceEntity(
            id: record.id,
            deviceID: record.deviceID,
            name: record.name,
            radiusMeters: record.radiusMeters
        )
    }

    static func radiusSubtitle(_ radiusMeters: Double) -> String {
        let format = NSLocalizedString(
            "intent_place_radius_subtitle_format",
            comment: "Subtitle for a saved place. Argument: localized radius distance."
        )
        return String.localizedStringWithFormat(format, IntentStatusFormatting.localizedDistance(radiusMeters))
    }

    @available(iOS 26.0, *)
    static func entityIdentifier(for entity: MiataruPlaceEntity) -> EntityIdentifier {
        EntityIdentifier(for: entity)
    }

    @available(iOS 26.0, *)
    static func annotate(_ activity: NSUserActivity, with entity: MiataruPlaceEntity) {
        let identifier = entityIdentifier(for: entity)
        activity.title = entity.name
        activity.targetContentIdentifier = identifier.description
        activity.appEntityIdentifier = identifier
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false
        activity.isEligibleForHandoff = false
        activity.isEligibleForPrediction = false
        activity.userInfo = nil
    }

    static func searchableAttributeSet(for entity: MiataruPlaceEntity) -> CSSearchableItemAttributeSet {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .item)
        attributeSet.title = entity.name
        attributeSet.displayName = entity.name
        attributeSet.contentDescription = radiusSubtitle(entity.radiusMeters)
        return attributeSet
    }
}

extension MiataruPlaceEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        MiataruPlaceIntentMetadata.searchableAttributeSet(for: self)
    }

    var hideInSpotlight: Bool {
        false
    }
}

extension View {
    @ViewBuilder
    func miataruPlaceUserActivity(for place: MiataruPlaceRecord) -> some View {
        if #available(iOS 26.0, *) {
            let entity = MiataruPlaceIntentMetadata.entity(from: place)
            userActivity(MiataruPlaceIntentMetadata.userActivityType, element: entity) { entity, activity in
                MiataruPlaceIntentMetadata.annotate(activity, with: entity)
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func miataruPlaceViewAnnotation(for place: MiataruPlaceRecord) -> some View {
        if #available(iOS 26.0, *) {
            let entity = MiataruPlaceIntentMetadata.entity(from: place)
            userActivity(MiataruPlaceIntentMetadata.userActivityType, element: entity) { entity, activity in
                MiataruPlaceIntentMetadata.annotate(activity, with: entity)
            }
        } else {
            self
        }
    }
}
