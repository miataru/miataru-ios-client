/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * NavigationLiveActivityAttributes.swift
 * Shared by the miataru app and widget extension.
 */

import ActivityKit
import Foundation

struct NavigationLiveActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        let direction: String
        let transportMode: String
        let transportSymbolName: String
        let distanceMeters: Double
        let estimatedArrivalDate: Date
        let ownLocationTimestamp: Date?
        let remoteLocationTimestamp: Date?
        let lastUpdatedAt: Date
        let ownLocationIsStale: Bool
        let remoteLocationIsStale: Bool
        let refreshInterval: TimeInterval
        let presentationMode: String?
        let remoteLocationDescription: String?
        let maneuverInstruction: String?
        let maneuverSymbolName: String?
        let maneuverDistanceMeters: Double?

        var isFocusedNavigation: Bool {
            presentationMode == "focused"
        }
    }

    let deviceID: String
    let deviceDisplayName: String

    func navigationURL(for state: ContentState) -> URL? {
        var components = URLComponents()
        components.scheme = "miataru"
        components.host = deviceID
        components.queryItems = [
            URLQueryItem(name: "action", value: "navigate"),
            URLQueryItem(name: "direction", value: state.direction),
            URLQueryItem(name: "presentation", value: state.presentationMode ?? "focused"),
            URLQueryItem(name: "transport", value: state.transportMode)
        ]
        return components.url
    }
}
