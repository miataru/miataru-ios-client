/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * DeviceLinkResolver.swift
 * miataru
 *
 * Created by Codex on 24.05.26.
 */

import Foundation

enum DeviceNavigationRouteDirection: String, CaseIterable, Equatable {
    case userToDevice
    case deviceToUser

    init(queryValue: String?) {
        guard let queryValue else {
            self = .userToDevice
            return
        }
        self = Self.allCases.first { $0.rawValue.lowercased() == queryValue.lowercased() } ?? .userToDevice
    }
}

enum DeviceNavigationPresentation: String, CaseIterable, Equatable {
    case focused
    case overview

    init(queryValue: String?) {
        guard let queryValue else {
            self = .focused
            return
        }
        self = Self.allCases.first { $0.rawValue.lowercased() == queryValue.lowercased() } ?? .focused
    }
}

struct DeviceNavigationLaunchOptions: Equatable {
    let direction: DeviceNavigationRouteDirection
    let presentation: DeviceNavigationPresentation
    let transportMode: IntentTransportMode?

    init(
        direction: DeviceNavigationRouteDirection,
        presentation: DeviceNavigationPresentation,
        transportMode: IntentTransportMode? = nil
    ) {
        self.direction = direction
        self.presentation = presentation
        self.transportMode = transportMode
    }

    static let standard = DeviceNavigationLaunchOptions(
        direction: .deviceToUser,
        presentation: .overview
    )

    static let defaultDeepLink = DeviceNavigationLaunchOptions(
        direction: .userToDevice,
        presentation: .focused
    )
}

enum DeviceLinkDestination: Equatable {
    case device(String)
    case navigation(String, options: DeviceNavigationLaunchOptions)
}

enum DeviceLinkResolver {
    static let miataruScheme = "miataru"
    static let canonicalPrefix = "miataru://"
    private static let actionQueryItemName = "action"
    private static let navigationActionValue = "navigate"
    private static let directionQueryItemName = "direction"
    private static let presentationQueryItemName = "presentation"
    private static let transportQueryItemName = "transport"

    static func urlString(for deviceID: String) -> String {
        "\(canonicalPrefix)\(deviceID)"
    }

    static func navigationURL(for deviceID: String, options: DeviceNavigationLaunchOptions = .defaultDeepLink) -> URL {
        var components = URLComponents(string: urlString(for: deviceID))!
        var queryItems = [
            URLQueryItem(name: actionQueryItemName, value: navigationActionValue),
            URLQueryItem(name: directionQueryItemName, value: options.direction.rawValue),
            URLQueryItem(name: presentationQueryItemName, value: options.presentation.rawValue)
        ]
        if let transportMode = options.transportMode {
            queryItems.append(URLQueryItem(name: transportQueryItemName, value: transportMode.rawValue))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func navigationURLString(for deviceID: String, options: DeviceNavigationLaunchOptions = .defaultDeepLink) -> String {
        navigationURL(for: deviceID, options: options).absoluteString
    }

    static func deviceID(from url: URL) -> String? {
        guard let destination = destination(from: url) else { return nil }
        switch destination {
        case .device(let deviceID), .navigation(let deviceID, _):
            return deviceID
        }
    }

    static func destination(from url: URL) -> DeviceLinkDestination? {
        guard url.scheme?.lowercased() == miataruScheme else { return nil }

        let rawDeviceID: String
        if let host = url.host, !host.isEmpty {
            rawDeviceID = host
        } else {
            rawDeviceID = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        guard let deviceID = trimmedDeviceID(rawDeviceID) else { return nil }
        guard navigationActionRequested(in: url) else { return .device(deviceID) }

        return .navigation(deviceID, options: navigationOptions(from: url))
    }

    static func deviceID(fromCanonicalCode rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.lowercased().hasPrefix(canonicalPrefix) else { return nil }

        let rawDeviceID = String(trimmedValue.dropFirst(canonicalPrefix.count))
        return trimmedDeviceID(rawDeviceID)
    }

    static func trimmedDeviceID(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedDeviceID(_ rawValue: String) -> String? {
        guard let trimmed = trimmedDeviceID(rawValue) else { return nil }
        let normalized = trimmed.uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    @MainActor
    static func canonicalKnownDeviceID(for rawValue: String, store: KnownDeviceStore = .shared) -> String? {
        guard let normalizedDeviceID = normalizedDeviceID(rawValue) else { return nil }
        return store.devices.first {
            self.normalizedDeviceID($0.DeviceID) == normalizedDeviceID
        }?.DeviceID
    }

    private static func navigationActionRequested(in url: URL) -> Bool {
        queryValue(for: actionQueryItemName, in: url)?.lowercased() == navigationActionValue
    }

    private static func navigationOptions(from url: URL) -> DeviceNavigationLaunchOptions {
        DeviceNavigationLaunchOptions(
            direction: DeviceNavigationRouteDirection(queryValue: queryValue(for: directionQueryItemName, in: url)),
            presentation: DeviceNavigationPresentation(queryValue: queryValue(for: presentationQueryItemName, in: url)),
            transportMode: queryValue(for: transportQueryItemName, in: url).flatMap(IntentTransportMode.init(rawValue:))
        )
    }

    private static func queryValue(for name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }
}
