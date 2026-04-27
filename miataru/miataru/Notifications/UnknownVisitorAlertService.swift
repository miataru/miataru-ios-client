/*
 * Copyright (c) 2013-2026, Daniel Kirstenpfad, www.miataru.com
 *
 * UnknownVisitorAlertService.swift
 * miataru
 *
 * Created by Codex on 09.03.26.
 */

import Foundation
import UserNotifications
import MiataruAPIClient

protocol UnknownVisitorAlertNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

struct LiveUnknownVisitorAlertNotifier: UnknownVisitorAlertNotifying {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct UnknownVisitorAlertCandidate: Equatable {
    let deviceID: String
    let visitTimestampMs: Int64

    var visitDate: Date {
        Date(timeIntervalSince1970: Double(visitTimestampMs) / 1000.0)
    }
}

struct UnknownVisitorAlertEvaluationResult {
    let candidates: [UnknownVisitorAlertCandidate]
    let newWatermarkMs: Int64
}

struct BackgroundVisitorCheckThrottle {
    static func shouldRun(lastCheckAt: Date?,
                          now: Date,
                          minimumInterval: TimeInterval?) -> Bool {
        guard let minimumInterval, minimumInterval > 0 else { return true }
        guard let lastCheckAt else { return true }
        return now.timeIntervalSince(lastCheckAt) >= minimumInterval
    }
}

struct UnknownVisitorAlertEvaluator {
    static func evaluate(visitors: [MiataruVisitor],
                         lastProcessedTimestampMs: Int64,
                         ownDeviceID: String,
                         knownDeviceIDs: Set<String>,
                         ignoredDeviceIDs: Set<String>,
                         lastNotifiedAtByDeviceID: [String: Date],
                         cooldown: TimeInterval = 24 * 60 * 60) -> UnknownVisitorAlertEvaluationResult {
        let normalizedOwnDeviceID = normalizeDeviceID(ownDeviceID)
        let normalizedKnownIDs = Set(knownDeviceIDs.map(normalizeDeviceID))
        let normalizedIgnoredIDs = Set(ignoredDeviceIDs.map(normalizeDeviceID))

        var newestTimestamp = lastProcessedTimestampMs
        var newestVisitByDevice: [String: Int64] = [:]

        for visitor in visitors {
            guard let visitTimestampMs = parseTimestampMs(visitor.TimeStamp) else { continue }
            newestTimestamp = max(newestTimestamp, visitTimestampMs)

            guard visitTimestampMs > lastProcessedTimestampMs else { continue }

            let normalizedVisitorDeviceID = normalizeDeviceID(visitor.DeviceID)
            guard !normalizedVisitorDeviceID.isEmpty else { continue }

            let existingTimestamp = newestVisitByDevice[normalizedVisitorDeviceID] ?? Int64.min
            if visitTimestampMs > existingTimestamp {
                newestVisitByDevice[normalizedVisitorDeviceID] = visitTimestampMs
            }
        }

        let candidates = newestVisitByDevice.compactMap { deviceID, visitTimestampMs -> UnknownVisitorAlertCandidate? in
            guard deviceID != normalizedOwnDeviceID else { return nil }
            guard !normalizedKnownIDs.contains(deviceID) else { return nil }
            guard !normalizedIgnoredIDs.contains(deviceID) else { return nil }

            if let lastNotifiedAt = lastNotifiedAtByDeviceID[deviceID] {
                let visitDate = Date(timeIntervalSince1970: Double(visitTimestampMs) / 1000.0)
                if visitDate.timeIntervalSince(lastNotifiedAt) < cooldown {
                    return nil
                }
            }

            return UnknownVisitorAlertCandidate(deviceID: deviceID, visitTimestampMs: visitTimestampMs)
        }
        .sorted { $0.visitTimestampMs < $1.visitTimestampMs }

        return UnknownVisitorAlertEvaluationResult(
            candidates: candidates,
            newWatermarkMs: newestTimestamp
        )
    }

    static func parseTimestampMs(_ rawValue: String) -> Int64? {
        if let intValue = Int64(rawValue) {
            return intValue
        }
        if let doubleValue = Double(rawValue), doubleValue.isFinite {
            return Int64(doubleValue.rounded())
        }
        return nil
    }

    static func normalizeDeviceID(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

actor UnknownVisitorAlertService {
    enum SetFeatureResult: Equatable {
        case enabled
        case disabled
        case denied
    }

    static let shared = UnknownVisitorAlertService()

    static let notificationTypeUserInfoKey = "miataru_notification_type"
    static let unknownVisitorNotificationType = "unknown_visitor_alert"

    private enum Keys {
        static let lastProcessedVisitorTimestampMs = "unknown_visitor_alert_last_processed_ts_ms"
        static let lastNotifiedByDeviceID = "unknown_visitor_alert_last_notified_by_device"
        static let lastBackgroundVisitorCheckAt = "unknown_visitor_alert_last_background_check_at"
    }

    private let defaults: UserDefaults
    private let notifier: UnknownVisitorAlertNotifying
    private let nowProvider: () -> Date

    private var isProcessing: Bool = false
    private var pendingServerURL: URL?

    init(defaults: UserDefaults = .standard,
         notifier: UnknownVisitorAlertNotifying = LiveUnknownVisitorAlertNotifier(),
         nowProvider: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.notifier = notifier
        self.nowProvider = nowProvider
    }

    func setFeatureEnabled(_ enabled: Bool) async -> SetFeatureResult {
        guard enabled else {
            return .disabled
        }

        let status = await notifier.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            setLastProcessedTimestampMs(currentTimestampMs())
            return .enabled
        case .notDetermined:
            do {
                let granted = try await notifier.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    setLastProcessedTimestampMs(currentTimestampMs())
                    return .enabled
                }
            } catch {
                debugLog("[UnknownVisitorAlertService] Notification authorization request failed: \(error)")
            }
            return .denied
        case .denied:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func processAfterSuccessfulLocationUpdate(serverURL: URL,
                                              minimumInterval: TimeInterval? = nil) async {
        guard await shouldProcessUnknownVisitorAlerts() else { return }
        guard shouldRunVisitorCheck(minimumInterval: minimumInterval) else { return }

        if isProcessing {
            pendingServerURL = serverURL
            return
        }

        isProcessing = true
        defer {
            isProcessing = false
        }

        var currentURL: URL? = serverURL
        while let url = currentURL {
            pendingServerURL = nil
            await processOnce(serverURL: url)
            currentURL = pendingServerURL
        }
    }

    private func shouldProcessUnknownVisitorAlerts() async -> Bool {
        let featureEnabled = await MainActor.run {
            SettingsManager.shared.unknownVisitorAlertsEnabled
        }
        guard featureEnabled else { return false }

        let status = await notifier.authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func shouldRunVisitorCheck(minimumInterval: TimeInterval?) -> Bool {
        guard let minimumInterval, minimumInterval > 0 else { return true }

        let now = nowProvider()
        let lastCheckAt = defaults.object(forKey: Keys.lastBackgroundVisitorCheckAt) as? Date
        guard BackgroundVisitorCheckThrottle.shouldRun(
            lastCheckAt: lastCheckAt,
            now: now,
            minimumInterval: minimumInterval
        ) else {
            return false
        }

        defaults.set(now, forKey: Keys.lastBackgroundVisitorCheckAt)
        return true
    }

    private func processOnce(serverURL: URL) async {
        let runtime = await MainActor.run {
            let settings = SettingsManager.shared
            let ownDeviceID = UnknownVisitorAlertEvaluator.normalizeDeviceID(thisDeviceIDManager.shared.deviceID)
            let knownIDs = Set(KnownDeviceStore.shared.devices.map { UnknownVisitorAlertEvaluator.normalizeDeviceID($0.DeviceID) })
            let ignoredIDs = Set(IgnoredVisitorDeviceStore.shared.getAllIgnoredDeviceIDs().map(UnknownVisitorAlertEvaluator.normalizeDeviceID))

            return (
                ownDeviceID: ownDeviceID,
                deviceKey: settings.deviceKey,
                knownIDs: knownIDs,
                ignoredIDs: ignoredIDs
            )
        }

        guard !runtime.ownDeviceID.isEmpty else { return }
        guard let deviceKey = runtime.deviceKey, !deviceKey.isEmpty else { return }

        do {
            APIRequestCounter.shared.record(.getVisitorHistory)
            let visitors = try await MiataruAppAPI.getVisitorHistory(
                serverURL: serverURL,
                forDeviceID: runtime.ownDeviceID,
                deviceKey: deviceKey,
                amount: 100
            )

            let lastProcessedTimestampMs = getLastProcessedTimestampMs()
            var lastNotifiedAtByDeviceID = getLastNotifiedAtByDeviceID()

            let evaluation = UnknownVisitorAlertEvaluator.evaluate(
                visitors: visitors,
                lastProcessedTimestampMs: lastProcessedTimestampMs,
                ownDeviceID: runtime.ownDeviceID,
                knownDeviceIDs: runtime.knownIDs,
                ignoredDeviceIDs: runtime.ignoredIDs,
                lastNotifiedAtByDeviceID: lastNotifiedAtByDeviceID
            )

            setLastProcessedTimestampMs(evaluation.newWatermarkMs)
            guard !evaluation.candidates.isEmpty else { return }

            let candidateDeviceIDs = evaluation.candidates.map(\.deviceID)
            let cityByDeviceID = await bestEffortCityLookup(for: candidateDeviceIDs,
                                                            serverURL: serverURL,
                                                            requestingDeviceID: runtime.ownDeviceID,
                                                            requestingDeviceKey: deviceKey)

            for candidate in evaluation.candidates {
                let slogan = await bestEffortSloganLookup(for: candidate.deviceID,
                                                          serverURL: serverURL,
                                                          requestingDeviceID: runtime.ownDeviceID,
                                                          requestingDeviceKey: deviceKey)
                let city = cityByDeviceID[candidate.deviceID]

                let format = NSLocalizedString(
                    "unknown_visitor_alert_notification_body_with_details",
                    comment: "Notification body when slogan and city are available for an unknown visitor alert"
                )
                let fallbackBody = NSLocalizedString(
                    "unknown_visitor_alert_notification_body_fallback",
                    comment: "Fallback notification body when no supplemental details are available for an unknown visitor alert"
                )
                let body: String
                if let slogan, !slogan.isEmpty,
                   let city, !city.isEmpty {
                    body = String(format: format, locale: Locale.current, slogan, city)
                } else {
                    body = fallbackBody
                }

                let content = UNMutableNotificationContent()
                content.title = NSLocalizedString(
                    "unknown_visitor_alert_notification_title",
                    comment: "Notification title for unknown visitor alert"
                )
                content.body = body
                content.sound = .default
                content.userInfo = [
                    Self.notificationTypeUserInfoKey: Self.unknownVisitorNotificationType,
                    "device_id": candidate.deviceID,
                    "visit_ts_ms": candidate.visitTimestampMs
                ]

                let request = UNNotificationRequest(
                    identifier: "unknown-visitor-\(candidate.deviceID)-\(candidate.visitTimestampMs)",
                    content: content,
                    trigger: nil
                )

                do {
                    try await notifier.add(request)
                    lastNotifiedAtByDeviceID[candidate.deviceID] = nowProvider()
                } catch {
                    debugLog("[UnknownVisitorAlertService] Failed scheduling notification: \(error)")
                }
            }

            setLastNotifiedAtByDeviceID(lastNotifiedAtByDeviceID)
        } catch {
            _ = DeviceKeyAuthHandler.handle(error: error)
            debugLog("[UnknownVisitorAlertService] Failed processing unknown visitor alerts: \(error)")
        }
    }

    private func bestEffortCityLookup(for deviceIDs: [String],
                                      serverURL: URL,
                                      requestingDeviceID: String,
                                      requestingDeviceKey: String) async -> [String: String] {
        var cityByDeviceID: [String: String] = await MainActor.run {
            let cache = DeviceLocationCacheStore.shared
            var result: [String: String] = [:]
            for deviceID in deviceIDs {
                if let locality = cache.getLocation(for: deviceID)?.locality,
                   !locality.isEmpty {
                    result[deviceID] = locality
                }
            }
            return result
        }

        let missingDeviceIDs = deviceIDs.filter { cityByDeviceID[$0] == nil }
        guard !missingDeviceIDs.isEmpty else { return cityByDeviceID }

        do {
            APIRequestCounter.shared.record(.getLocation)
            let locations = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: missingDeviceIDs,
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )

            await MainActor.run {
                let cache = DeviceLocationCacheStore.shared
                for location in locations {
                    cache.setLocation(
                        for: location.Device,
                        latitude: location.Latitude,
                        longitude: location.Longitude,
                        accuracy: location.HorizontalAccuracy,
                        timestamp: location.TimestampDate,
                        batteryLevel: location.BatteryLevel,
                        altitude: location.Altitude,
                        speed: location.Speed
                    )
                }
            }

            let refreshedCities = await MainActor.run {
                let cache = DeviceLocationCacheStore.shared
                var result: [String: String] = [:]
                for deviceID in missingDeviceIDs {
                    if let locality = cache.getLocation(for: deviceID)?.locality,
                       !locality.isEmpty {
                        result[deviceID] = locality
                    }
                }
                return result
            }

            for (deviceID, city) in refreshedCities {
                cityByDeviceID[deviceID] = city
            }
        } catch {
            debugLog("[UnknownVisitorAlertService] Failed best-effort city lookup: \(error)")
        }

        return cityByDeviceID
    }

    private func bestEffortSloganLookup(for deviceID: String,
                                        serverURL: URL,
                                        requestingDeviceID: String,
                                        requestingDeviceKey: String) async -> String? {
        let cachedSlogan = await MainActor.run {
            DeviceSloganCacheStore.shared.slogan(for: deviceID)
        }
        if let cachedSlogan, !cachedSlogan.isEmpty {
            return cachedSlogan
        }

        do {
            APIRequestCounter.shared.record(.getLocation)
            _ = try await MiataruAppAPI.getLocation(
                serverURL: serverURL,
                forDeviceIDs: [deviceID],
                requestingDeviceID: requestingDeviceID,
                requestingDeviceKey: requestingDeviceKey
            )
        } catch {
            debugLog("[UnknownVisitorAlertService] Failed best-effort slogan lookup via GetLocation: \(error)")
        }

        let refreshedSlogan = await MainActor.run {
            DeviceSloganCacheStore.shared.slogan(for: deviceID)
        }
        guard let refreshedSlogan,
              !refreshedSlogan.isEmpty else {
            return nil
        }
        return refreshedSlogan
    }

    private func currentTimestampMs() -> Int64 {
        Int64((nowProvider().timeIntervalSince1970 * 1000.0).rounded())
    }

    private func getLastProcessedTimestampMs() -> Int64 {
        Int64(defaults.double(forKey: Keys.lastProcessedVisitorTimestampMs))
    }

    private func setLastProcessedTimestampMs(_ timestampMs: Int64) {
        defaults.set(Double(timestampMs), forKey: Keys.lastProcessedVisitorTimestampMs)
    }

    private func getLastNotifiedAtByDeviceID() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: Keys.lastNotifiedByDeviceID) as? [String: TimeInterval] else {
            return [:]
        }

        return raw.reduce(into: [String: Date]()) { partialResult, entry in
            let normalizedID = UnknownVisitorAlertEvaluator.normalizeDeviceID(entry.key)
            guard !normalizedID.isEmpty else { return }
            partialResult[normalizedID] = Date(timeIntervalSince1970: entry.value)
        }
    }

    private func setLastNotifiedAtByDeviceID(_ values: [String: Date]) {
        let serialized = values.reduce(into: [String: TimeInterval]()) { partialResult, entry in
            let normalizedID = UnknownVisitorAlertEvaluator.normalizeDeviceID(entry.key)
            guard !normalizedID.isEmpty else { return }
            partialResult[normalizedID] = entry.value.timeIntervalSince1970
        }
        defaults.set(serialized, forKey: Keys.lastNotifiedByDeviceID)
    }
}
